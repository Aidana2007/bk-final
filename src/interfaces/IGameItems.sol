// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGameItems {
    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external;
    function burn(address from, uint256 id, uint256 amount) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}