// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { RentalVault } from "../src/RentalVault.sol";

contract RentalVaultTest is Test {
    MockERC20 internal paymentToken;
    MockERC721 internal gameItem;
    RentalVault internal rentalVault;

    address internal lender = address(0xA11CE);
    address internal renter = address(0xB0B);
    address internal feeRecipient = address(0xFEE);

    uint256 internal tokenId;

    function setUp() public {
        paymentToken = new MockERC20("Mock USDC", "mUSDC");
        gameItem = new MockERC721("Game Item", "ITEM");
        rentalVault = new RentalVault(paymentToken, address(this), feeRecipient, 500); // 5%

        vm.prank(lender);
        tokenId = gameItem.mint(lender);

        paymentToken.mint(renter, 10_000 ether);

        vm.prank(lender);
        gameItem.approve(address(rentalVault), tokenId);

        vm.prank(renter);
        paymentToken.approve(address(rentalVault), type(uint256).max);
    }

    function testCreateAcceptAndSettleOffer() public {
        uint64 startTs = uint64(block.timestamp + 10);
        uint64 endTs = uint64(block.timestamp + 1 days);

        vm.prank(lender);
        bytes32 offerId = rentalVault.createOffer(
            gameItem, tokenId, renter, startTs, endTs, 1_000 ether, 200 ether
        );

        vm.prank(renter);
        rentalVault.acceptOffer(offerId);

        assertEq(gameItem.ownerOf(tokenId), renter);

        vm.warp(endTs + 1);

        vm.prank(renter);
        gameItem.setApprovalForAll(address(rentalVault), true);

        rentalVault.settleOffer(offerId, false);

        // 5% of 200 = 10 fee, lender gets 190 rent + collateral flow back to renter.
        assertEq(paymentToken.balanceOf(feeRecipient), 10 ether);
        assertEq(paymentToken.balanceOf(lender), 190 ether);
        assertEq(
            paymentToken.balanceOf(renter), 10_000 ether - 200 ether - 1_000 ether + 1_000 ether
        );
        assertEq(gameItem.ownerOf(tokenId), lender);
    }

    function testOnlyExpectedRenterCanAccept() public {
        uint64 startTs = uint64(block.timestamp + 10);
        uint64 endTs = uint64(block.timestamp + 1 days);

        vm.prank(lender);
        bytes32 offerId =
            rentalVault.createOffer(gameItem, tokenId, renter, startTs, endTs, 100 ether, 50 ether);

        vm.prank(address(0xCAFE));
        vm.expectRevert();
        rentalVault.acceptOffer(offerId);
    }
}
