// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

library Bytes32 {
  function toString(bytes32 value) internal pure returns (string memory) {
    return string(bytes.concat(value));
  }

  function toUint(bytes32 value) internal pure returns (uint256) {
    return uint256(value);
  }
}
