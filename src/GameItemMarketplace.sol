// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IGameItems } from "./interfaces/IGameItems.sol";

/// @notice Minimal payable marketplace for demo item purchases.
contract GameItemMarketplace is AccessControl, ReentrancyGuard {
    bytes32 public constant LISTING_MANAGER_ROLE = keccak256("LISTING_MANAGER_ROLE");

    struct Listing {
        uint256 itemId;
        uint256 amount;
        uint256 price;
        address payable seller;
        bool active;
    }

    IGameItems public immutable gameItems;
    uint256 public nextListingId = 1;
    mapping(uint256 listingId => Listing listing) public listings;

    error ZeroAddress();
    error InvalidListing();
    error ListingInactive();
    error IncorrectPayment(uint256 expected, uint256 actual);

    event ListingCreated(
        uint256 indexed listingId,
        uint256 indexed itemId,
        uint256 amount,
        uint256 price,
        address indexed seller
    );
    event ListingCanceled(uint256 indexed listingId);
    event ListingPurchased(uint256 indexed listingId, address indexed buyer);

    constructor(IGameItems gameItems_, address admin) {
        if (address(gameItems_) == address(0) || admin == address(0)) revert ZeroAddress();
        gameItems = gameItems_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LISTING_MANAGER_ROLE, admin);
    }

    function createListing(uint256 itemId, uint256 amount, uint256 price, address payable seller)
        external
        onlyRole(LISTING_MANAGER_ROLE)
        returns (uint256 listingId)
    {
        if (itemId == 0 || amount == 0 || price == 0 || seller == address(0)) {
            revert InvalidListing();
        }

        listingId = nextListingId++;
        listings[listingId] =
            Listing({ itemId: itemId, amount: amount, price: price, seller: seller, active: true });
        emit ListingCreated(listingId, itemId, amount, price, seller);
    }

    function cancel(uint256 listingId) external onlyRole(LISTING_MANAGER_ROLE) {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingInactive();
        listing.active = false;
        emit ListingCanceled(listingId);
    }

    function buy(uint256 listingId) external payable nonReentrant {
        Listing memory listing = listings[listingId];
        if (!listing.active) revert ListingInactive();
        if (msg.value != listing.price) revert IncorrectPayment(listing.price, msg.value);

        listing.seller.transfer(msg.value);
        gameItems.mint(msg.sender, listing.itemId, listing.amount, "");
        emit ListingPurchased(listingId, msg.sender);
    }
}
