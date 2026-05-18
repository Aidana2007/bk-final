// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal LP token interface used by AMM pools.
interface IAMMLPToken is IERC20 {
    /// @notice Mints LP shares to `to`.
    function mint(address to, uint256 amount) external;

    /// @notice Burns LP shares from `from`.
    function burn(address from, uint256 amount) external;
}
