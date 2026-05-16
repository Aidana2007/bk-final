// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AMMLPToken is ERC20, Ownable {
    error ZeroAddress();

    constructor(string memory name_, string memory symbol_, address initialOwner) ERC20(name_, symbol_) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
