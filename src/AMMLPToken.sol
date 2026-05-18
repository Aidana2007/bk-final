// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice ERC20 receipt token minted and burned only by its owning AMM pool.
contract AMMLPToken is ERC20, Ownable {
    error ZeroAddress();

    /// @notice Deploys an LP token and assigns mint/burn authority to `initialOwner`.
    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC20(name_, symbol_)
        Ownable(initialOwner)
    {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    /// @notice Mints LP shares to a liquidity provider.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burns LP shares during liquidity removal.
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
