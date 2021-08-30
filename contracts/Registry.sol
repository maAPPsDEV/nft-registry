// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/String.sol";
import "./libs/Bytes32.sol";

/**
 * @dev NFT Registry
 *
 * Implements ERC721.
 * name:    Valory Registry
 * symbol:  VRT
 *
 * It registers(mint) NFT using it's IFPS hash as token ID.
 * It registers Service that is a collection of NFTs.
 * It executes Service as requested.
 *
 * @notice All external functions accept meta-transactions.
 * The owner sends the transactions behind the signers, every external function is only callable by the owner.
 * Accounts must provide the signature and signer, but it doesn't implement EIP-712.
 * Thus, accounts must provide the transaction message configured based on the each individual function implementation.
 *
 * @notice Token has many to many relationship to Service.
 */
contract Registry is ERC721("Valory Registry", "VRT"), Ownable {
  /* Constructor */

  /* Events */
  /**
   * @dev Occurs when a new service is registered.
   *
   * @param name  - The service name
   * @param owner - The service owner
   */
  event ServiceRegistered(string name, address indexed owner);

  /**
   * @dev Occurs when a new service is unregistered.
   *
   * @param name  - The service name
   * @param owner - The service owner
   */
  event ServiceUnregistered(string name, address indexed owner);

  /**
   * @dev Occurs when a token is used for a service.
   *
   * @param tokenId     - The token id
   * @param serviceName - The service name
   */
  event TokenUsed(bytes32 indexed tokenId, string serviceName);

  /**
   * @dev Occurs when a token is unused for a service.
   *
   * @param tokenId     - The token id
   * @param serviceName - The service name
   */
  event TokenUnused(bytes32 indexed tokenId, string serviceName);

  /* Constancs */
  /// @dev The external operation types.
  uint256 private constant OPERATION_CALL = 0;
  uint256 private constant OPERATION_DELEGATECALL = 1;
  uint256 private constant OPERATION_CREATE2 = 2;
  uint256 private constant OPERATION_CREATE = 3;

  /* Libraries */
  /// @notice Use libraries to handle many to many relationship.
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using String for string;
  using Bytes32 for bytes32;

  /* Data Struct */
  /// @dev Service struct represents the registered services.
  struct Service {
    address owner; // The EOA who owned the service
    EnumerableSet.Bytes32Set tokenIds; // The collection of token Ids that belong to the service
  }

  /* State Variables */
  /// @dev The map of services by the service name as the key.
  mapping(string => Service) private services;

  /// @dev The map of services by the token Id as the key.
  /// @notice A token can be used for multiple services.
  mapping(bytes32 => EnumerableSet.Bytes32Set) private uses;

  /// @dev The nonces used for recovering signer, prevents replay attack.
  mapping(address => uint256) public nonces;

  /* Modifiers */
  /// @dev Restricts the length of string to be less than or equal to the given length.
  modifier lengthedString(string calldata name, uint256 length) {
    require(bytes(name).length <= length, "VRT: String length exceeds the limitation");
    _;
  }

  /* Public Functions */
  /**
   * @dev Registers a service and set the caller to the owner.
   * Reverts if the service was registered already.
   * Emits ServiceRegistered on completion.
   *
   * @param name - The name of the service being registered, limited to be less than or equal 32 bytes,
   * as the name is used for resolving token to service relationship as bytes32 type
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function registerService(
    string calldata name,
    bytes calldata signature,
    address signer
  ) external onlyOwner lengthedString(name, 32) {
    _verifySign(keccak256(abi.encodePacked(name)), signature, signer);
    require(!_serviceExists(name), "VRT: Service already exist");

    services[name].owner = signer;

    emit ServiceRegistered(name, signer);
  }

  /**
   * @dev Unregisters a service and releases all used tokens.
   * Reverts if the service was not found, or when the sender is not the owner.
   * Emits ServiceUnregistered on completion.
   *
   * @param name        - The name of the service being unregistered
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function unregisterService(
    string calldata name,
    bytes calldata signature,
    address signer
  ) external onlyOwner {
    _verifySign(keccak256(abi.encodePacked(name)), signature, signer);
    require(_serviceExists(name), "VRT: Service not found");
    Service storage service = services[name];
    address owner = service.owner;
    require(owner == signer, "VRT: No permission");

    // remove token to service relationships.
    EnumerableSet.Bytes32Set storage tokenIds = service.tokenIds;
    uint256 length = tokenIds.length();
    for (uint256 i = 0; i < length; i++) {
      uses[tokenIds.at(i)].remove(name.toBytes32());
    }

    // remove service to token relationships.
    delete services[name];

    emit ServiceUnregistered(name, owner);
  }

  /**
   * @dev Registers(mint) a token.
   * Emits Transfer on completion.
   *
   * @param to          - The address of the owner of the token being newly registered
   * @param tokenId     - The IFPS hash of the asset
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function registerToken(
    address to,
    bytes32 tokenId,
    bytes calldata signature,
    address signer
  ) public onlyOwner {
    _verifySign(keccak256(abi.encodePacked(to, tokenId)), signature, signer);
    _safeMint(to, tokenId.toUint());
  }

  /**
   * @dev Registers(mint) a token and add to a service.
   * Reverts if the service doesn't exist.
   * Emits Transfer, TokenUsed on completion.
   *
   * @param to          - The address of the owner of the token being newly registered
   * @param tokenId     - The IFPS hash of the asset
   * @param serviceName - The service name which uses the token
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function registerToken(
    address to,
    bytes32 tokenId,
    string calldata serviceName,
    bytes calldata signature,
    address signer
  ) external onlyOwner {
    _verifySign(keccak256(abi.encodePacked(to, tokenId, serviceName)), signature, signer);
    require(_serviceExists(serviceName), "VRT: Service not found");

    _safeMint(to, tokenId.toUint());

    _useToken(tokenId, serviceName);
  }

  /**
   * @dev Unregisters(burn) a token and removes from services.
   * Reverts if the token doesn't exist, or the caller is not the owner.
   * Emits Transfer on completion.
   *
   * @param tokenId     - The IFPS hash of the asset
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function unregisterToken(
    bytes32 tokenId,
    bytes calldata signature,
    address signer
  ) external onlyOwner {
    _verifySign(keccak256(abi.encodePacked(tokenId)), signature, signer);
    uint256 uId = tokenId.toUint();
    require(_exists(uId), "VRT: Token not found");
    require(ownerOf(uId) == signer, "VRT: No permission");

    _burn(uId);

    // remove service to token relationships.
    EnumerableSet.Bytes32Set storage usedServiceNames = uses[tokenId];
    uint256 length = usedServiceNames.length();
    for (uint256 i = 0; i < length; ++i) {
      services[usedServiceNames.at(i).toString()].tokenIds.remove(tokenId);
    }

    // remove token to service relationships.
    delete uses[tokenId];
  }

  /**
   * @dev Adds a token to a service.
   * Emits TokenUsed on completion.
   *
   * @param tokenId     - The IFPS hash of the asset
   * @param serviceName - The service name which uses the token
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function useToken(
    bytes32 tokenId,
    string calldata serviceName,
    bytes calldata signature,
    address signer
  ) external onlyOwner {
    _verifySign(keccak256(abi.encodePacked(tokenId, serviceName)), signature, signer);
    require(_serviceExists(serviceName), "VRT: Service not found");
    uint256 uId = tokenId.toUint();
    require(_exists(uId), "VRT: Token not found");
    require(ownerOf(uId) == signer, "VRT: No permission");
    require(!_tokenUsed(tokenId, serviceName), "VRT: Token already is used");

    _useToken(tokenId, serviceName);
  }

  /**
   * @dev Removes a token from a service.
   * Emits TokenUnused on completion.
   *
   * @param tokenId     - The IFPS hash of the asset
   * @param serviceName - The service name which uses the token
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function unuseToken(
    bytes32 tokenId,
    string calldata serviceName,
    bytes calldata signature,
    address signer
  ) external onlyOwner {
    _verifySign(keccak256(abi.encodePacked(tokenId, serviceName)), signature, signer);
    require(_serviceExists(serviceName), "VRT: Service not found");
    uint256 uId = tokenId.toUint();
    require(_exists(uId), "VRT: Token not found");
    require(ownerOf(uId) == signer, "VRT: No permission");
    require(_tokenUsed(tokenId, serviceName), "VRT: Token was not used");

    _unuseToken(tokenId, serviceName);
  }

  /**
   * @dev Executes any other smart contract. Is only callable by the owner.
   * Reverts if the signer has no permission to do.
   *
   * @param operation   - The operation to execute, only supports call: CALL = 0; DELEGATECALL = 1; CREATE2 = 2; CREATE = 3;
   * @param to          - The external smart contract
   * @param value       - The value of Ether to transfer
   * @param data        - The call data
   * @param serviceName - The service name used to validate the permission of the signer
   * @param signature   - The signature
   * @param signer      - The signer of the transaction
   */
  function execute(
    uint256 operation,
    address to,
    uint256 value,
    bytes calldata data,
    string calldata serviceName,
    bytes calldata signature,
    address signer
  ) external payable onlyOwner {
    _verifySign(keccak256(abi.encodePacked(operation, to, value, data, serviceName)), signature, signer);
    require(services[serviceName].owner == signer, "VRT: No permission");

    // build error data
    bytes memory unsupportedOpErrData = abi.encodeWithSignature("Error(string)", "VRT: Unsupported operation"); // less than 32 bytes

    assembly {
      // only supports CALL operation, otherwise reverts
      if eq(xor(operation, OPERATION_CALL), 1) {
        revert(add(unsupportedOpErrData, 0x20), mload(unsupportedOpErrData))
      }
    }

    // make external call, with limited amount of gas.
    _executeCall(to, value, gasleft() - 2500, data); // Used to avoid stack too deep error.
  }

  /* Private Functions */
  /**
   * @dev Verify if the transaction has been signed by a valid signer.
   * Increases the nonce of the signer on validation success.
   */
  function _verifySign(
    bytes32 message,
    bytes memory signature,
    address signer
  ) private {
    message = keccak256(abi.encodePacked(nonces[signer], message));
    require(_recoverSigner(message, signature) == signer, "VRT: Invalid signer");
    nonces[signer]++;
  }

  /**
   * @dev Recovers the signer of the transaction.
   * Reverts if invalid signature was provided.
   *
   * @param message   - The transaction message consists of parameters
   * @param signature - The signature of the transaction
   * @return signer   - The valid signer of the transaction
   */
  function _recoverSigner(bytes32 message, bytes memory signature) private pure returns (address signer) {
    require(signature.length == 65, "VRT: Invalid signature length");

    // build a prefixed hash to mimic the behavior of eth_sign.
    message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));

    // split signature
    uint8 v;
    bytes32 r;
    bytes32 s;
    assembly {
      // first 32 bytes, after the length prefix.
      r := mload(add(signature, 32))
      // second 32 bytes.
      s := mload(add(signature, 64))
      // final byte (first byte of the next 32 bytes).
      v := byte(0, mload(add(signature, 96)))

      // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
      // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
      // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
      // signatures from current libraries generate a unique signature with an s-value in the lower half order.
      //
      // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
      // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
      // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
      // these malleable signatures as well.
      if gt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
        s := sub(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141, s)
      }
      if or(eq(v, 0), eq(v, 1)) {
        v := add(v, 27)
      }
    }
    // recover signer
    signer = ecrecover(message, v, r, s);

    /// @notice Invalid signatures will produce an empty address.
    require(signer != address(0), "VRT: Invalid signature");
  }

  /**
   * @dev Executes external contract call.
   * Returns data returned from the external contract if the call was successful, otherwise reverts.
   *
   * @param to    - The address of the external contract being called
   * @param value - The value of Ether to transfer
   * @param gasTo - The amount gas allowed for the external contract
   * @param data  - The call data
   */
  function _executeCall(
    address to,
    uint256 value,
    uint256 gasTo,
    bytes memory data
  ) private {
    assembly {
      // call external contract.
      let result := call(gasTo, to, value, add(data, 0x20), mload(data), 0, 0)

      // alloc memory for returned data.
      let pos := mload(0x40)
      let len := returndatasize()
      mstore(0x40, add(pos, len))
      // copy the returned data.
      returndatacopy(pos, 0, len)

      switch result
      // call returns 0 on error.
      case 0 {
        revert(pos, len)
      }
      default {
        return(pos, len)
      }
    }
  }

  /**
   * @dev Checks if the service of name exists.
   *
   * @param name - The service name
   * @return true if the service of name exists, otherwise false
   */
  function _serviceExists(string calldata name) private view returns (bool) {
    return services[name].owner != address(0);
  }

  /**
   * @dev Checks if the token is used for the service.
   *
   * @param tokenId     - The IFPS hash of the asset
   * @param serviceName - The service name which uses the token
   * @return true if the token is used for the service of name, otherwise false
   */
  function _tokenUsed(bytes32 tokenId, string calldata serviceName) private view returns (bool) {
    return uses[tokenId].contains(serviceName.toBytes32());
  }

  /**
   * @dev Adds a token to a service.
   *
   * @param tokenId     - The IFPS hash of the asset
   * @param serviceName - The service name which uses the token
   */
  function _useToken(bytes32 tokenId, string calldata serviceName) private {
    // add service to token relationship.
    services[serviceName].tokenIds.add(tokenId);
    // add token to service relationship.
    uses[tokenId].add(serviceName.toBytes32());

    emit TokenUsed(tokenId, serviceName);
  }

  /**
   * @dev Removes a token from a service.
   *
   * @param tokenId     - The IFPS hash of the asset
   * @param serviceName - The service name which uses the token
   */
  function _unuseToken(bytes32 tokenId, string calldata serviceName) private {
    // remove service to token relationship.
    services[serviceName].tokenIds.remove(tokenId);
    // remove token to service relationship.
    uses[tokenId].remove(serviceName.toBytes32());

    emit TokenUnused(tokenId, serviceName);
  }
}
