// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/// @notice Governance token with delegation snapshots and permit signatures.
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    error ZeroAddress();

    /// @notice Creates the governance token and mints initial supply to `treasury`.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address admin,
        address treasury
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (admin == address(0) || treasury == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);

        _mint(treasury, initialSupply);
    }

    /// @notice Mints tokens to `to`. Restricted to accounts with `MINTER_ROLE`.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burns tokens from `from`. Restricted to accounts with `BURNER_ROLE`.
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /// @dev Uses timestamp checkpoints so governance durations are exact seconds.
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /// @dev ERC-6372 clock description for timestamp-based governance.
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        return "mode=timestamp";
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
