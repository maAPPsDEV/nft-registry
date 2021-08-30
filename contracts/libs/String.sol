// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

library String {
  function toBytes32(string memory value) internal pure returns (bytes32) {
    return bytes32(bytes(value));
  }
}
