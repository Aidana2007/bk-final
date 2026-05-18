// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Governance-controlled ERC4626 treasury vault with role-gated admin actions.
contract TreasuryVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public depositCap;
    address public treasuryRecipient;

    error ZeroAddress();
    error AssetRescueForbidden();

    event DepositCapUpdated(uint256 oldDepositCap, uint256 newDepositCap);
    event TreasuryRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Creates a tokenized treasury vault backed by `asset_`.
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin,
        address treasuryRecipient_,
        uint256 depositCap_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        if (admin == address(0) || treasuryRecipient_ == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VAULT_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        treasuryRecipient = treasuryRecipient_;
        depositCap = depositCap_;
    }

    /// @notice Updates the maximum total assets accepted by the vault.
    function setDepositCap(uint256 newDepositCap) external onlyRole(VAULT_MANAGER_ROLE) {
        uint256 oldCap = depositCap;
        depositCap = newDepositCap;
        emit DepositCapUpdated(oldCap, newDepositCap);
    }

    /// @notice Updates the designated treasury payout recipient.
    function setTreasuryRecipient(address newRecipient) external onlyRole(VAULT_MANAGER_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        address oldRecipient = treasuryRecipient;
        treasuryRecipient = newRecipient;
        emit TreasuryRecipientUpdated(oldRecipient, newRecipient);
    }

    /// @notice Pauses deposits and mints.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes deposits and mints.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Recovers non-asset tokens mistakenly sent to the vault.
    function rescueToken(IERC20 token, address to, uint256 amount)
        external
        onlyRole(VAULT_MANAGER_ROLE)
        nonReentrant
    {
        if (address(token) == asset()) revert AssetRescueForbidden();
        token.safeTransfer(to, amount);
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;

        if (depositCap == type(uint256).max) {
            return type(uint256).max;
        }

        uint256 assets = totalAssets();
        if (assets >= depositCap) return 0;
        return depositCap - assets;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        return convertToShares(maxAssets);
    }
}
