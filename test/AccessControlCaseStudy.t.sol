// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";

contract InsecureTreasury {
    IERC20 public immutable asset;
    address public treasuryRecipient;

    constructor(IERC20 asset_, address recipient_) {
        asset = asset_;
        treasuryRecipient = recipient_;
    }

    // Vulnerable: missing access control.
    function setTreasuryRecipient(address newRecipient) external {
        treasuryRecipient = newRecipient;
    }

    function drainToRecipient() external {
        asset.transfer(treasuryRecipient, asset.balanceOf(address(this)));
    }
}

contract AccessControlCaseStudyTest is Test {
    MockERC20 internal asset;
    address internal attacker = address(0xBAD);
    address internal legitimateRecipient = address(0x1234);

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC");
    }

    function testVulnerability_InsecureRecipientCanBeHijacked() public {
        InsecureTreasury insecure = new InsecureTreasury(asset, legitimateRecipient);
        asset.mint(address(insecure), 1_000 ether);

        vm.prank(attacker);
        insecure.setTreasuryRecipient(attacker);

        vm.prank(attacker);
        insecure.drainToRecipient();

        assertEq(asset.balanceOf(attacker), 1_000 ether);
        assertEq(asset.balanceOf(legitimateRecipient), 0);
    }

    function testFix_SecureVaultRejectsUnauthorizedAdminCall() public {
        TreasuryVault secure = new TreasuryVault(
            asset, "Treasury Vault Share", "tvSHARE", address(this), legitimateRecipient, type(uint256).max
        );
        secure.revokeRole(secure.VAULT_MANAGER_ROLE(), address(this));

        vm.prank(attacker);
        vm.expectRevert();
        secure.setTreasuryRecipient(attacker);
    }
}
