// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6 <0.9.0;

contract ExternalMock {
  string public bar;

  function foo(string memory value) external payable returns (bool) {
    bar = value;
    return true;
  }
}
