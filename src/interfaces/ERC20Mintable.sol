// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ERC20Mintable {
  function mint(address receiver, uint256 amount) external;

  function mint(uint256 amount) external;

  function balanceOf(address receiver) external returns (uint256);

  function approve(address approver, uint256 amount) external;
}
