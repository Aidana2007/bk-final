// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";

contract TreasuryVaultInvariantTest is Test {
    MockERC20 internal asset;
    TreasuryVault internal vault;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC");
        vault = new TreasuryVault(
            asset, "Treasury Vault Share", "tvSHARE", address(this), address(0x7777), type(uint256).max
        );

        asset.mint(alice, 10_000_000 ether);
        asset.mint(bob, 10_000_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(alice);
        vault.deposit(1_000_000 ether, alice);
    }

    function testFuzzConvertAssetsToSharesToAssetsDoesNotIncrease(uint128 rawAssets) public {
        uint256 assets = bound(uint256(rawAssets), 1, 5_000_000 ether);
        uint256 shares = vault.convertToShares(assets);
        uint256 roundTripAssets = vault.convertToAssets(shares);

        assertTrue(roundTripAssets <= assets);
    }

    function testFuzzConvertSharesToAssetsToSharesDoesNotIncrease(uint128 rawShares) public {
        uint256 shares = bound(uint256(rawShares), 1, 5_000_000 ether);
        uint256 assets = vault.convertToAssets(shares);
        uint256 roundTripShares = vault.convertToShares(assets);

        assertTrue(roundTripShares <= shares);
    }

    function testFuzzDepositRedeemRoundTripBoundedLoss(uint96 rawAssets) public {
        uint256 assets = bound(uint256(rawAssets), 1, 1_000_000 ether);

        uint256 shares;
        vm.startPrank(bob);
        shares = vault.deposit(assets, bob);
        uint256 assetsOut = vault.redeem(shares, bob, bob);
        vm.stopPrank();

        assertTrue(assets - assetsOut <= 1);
    }

    function testFuzzPreviewConsistency(uint128 rawAssets) public {
        uint256 assets = bound(uint256(rawAssets), 1, 5_000_000 ether);
        uint256 shares = vault.convertToShares(assets);

        assertEq(vault.previewDeposit(assets), shares);
        assertEq(vault.previewRedeem(shares), vault.convertToAssets(shares));
    }
}
