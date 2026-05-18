// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice NFT rental escrow with role-gated settlement and collateral handling.
contract RentalVault is AccessControl, IERC721Receiver, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant LISTING_MANAGER_ROLE = keccak256("LISTING_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant BPS = 10_000;

    struct RentalOffer {
        address lender;
        address renter;
        IERC721 nft;
        uint256 tokenId;
        uint64 startTimestamp;
        uint64 endTimestamp;
        uint256 collateralAmount;
        uint256 rentAmount;
        bool accepted;
        bool settled;
    }

    IERC20 public immutable paymentToken;
    address public feeRecipient;
    uint16 public protocolFeeBps;
    uint256 public offerNonce;

    mapping(bytes32 offerId => RentalOffer offer) public offers;

    error ZeroAddress();
    error InvalidTimeWindow();
    error OfferAlreadyAccepted();
    error OfferNotAccepted();
    error OfferAlreadySettled();
    error OnlyExpectedRenter();
    error OfferNotFinished();
    error InvalidFeeBps();

    event RentalOfferCreated(
        bytes32 indexed offerId,
        address indexed lender,
        address indexed renter,
        address nft,
        uint256 tokenId,
        uint64 startTimestamp,
        uint64 endTimestamp,
        uint256 collateralAmount,
        uint256 rentAmount
    );
    event RentalOfferAccepted(bytes32 indexed offerId, address indexed renter);
    event RentalOfferSettled(bytes32 indexed offerId, bool defaulted);
    event FeeConfigUpdated(
        uint16 oldFeeBps, uint16 newFeeBps, address oldRecipient, address newRecipient
    );

    /// @notice Creates a rental vault for ERC721 assets settled in `paymentToken_`.
    constructor(
        IERC20 paymentToken_,
        address admin,
        address feeRecipient_,
        uint16 protocolFeeBps_
    ) {
        if (
            address(paymentToken_) == address(0) || admin == address(0)
                || feeRecipient_ == address(0)
        ) {
            revert ZeroAddress();
        }
        if (protocolFeeBps_ > BPS) revert InvalidFeeBps();

        paymentToken = paymentToken_;
        feeRecipient = feeRecipient_;
        protocolFeeBps = protocolFeeBps_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LISTING_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @notice Lender deposits an NFT and creates a rental offer for a specific renter.
    function createOffer(
        IERC721 nft,
        uint256 tokenId,
        address renter,
        uint64 startTimestamp,
        uint64 endTimestamp,
        uint256 collateralAmount,
        uint256 rentAmount
    ) external whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (address(nft) == address(0) || renter == address(0)) {
            revert ZeroAddress();
        }
        if (endTimestamp <= startTimestamp || startTimestamp < block.timestamp) {
            revert InvalidTimeWindow();
        }

        offerId = keccak256(abi.encode(msg.sender, address(nft), tokenId, renter, offerNonce++));
        RentalOffer storage offer = offers[offerId];
        offer.lender = msg.sender;
        offer.renter = renter;
        offer.nft = nft;
        offer.tokenId = tokenId;
        offer.startTimestamp = startTimestamp;
        offer.endTimestamp = endTimestamp;
        offer.collateralAmount = collateralAmount;
        offer.rentAmount = rentAmount;

        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        emit RentalOfferCreated(
            offerId,
            msg.sender,
            renter,
            address(nft),
            tokenId,
            startTimestamp,
            endTimestamp,
            collateralAmount,
            rentAmount
        );
    }

    /// @notice Renter funds rent+collateral and receives the NFT for the rental period.
    function acceptOffer(bytes32 offerId) external whenNotPaused nonReentrant {
        RentalOffer storage offer = offers[offerId];
        if (msg.sender != offer.renter) revert OnlyExpectedRenter();
        if (offer.accepted) revert OfferAlreadyAccepted();
        if (offer.settled) revert OfferAlreadySettled();

        offer.accepted = true;
        uint256 totalPayment = offer.collateralAmount + offer.rentAmount;
        if (totalPayment > 0) {
            paymentToken.safeTransferFrom(msg.sender, address(this), totalPayment);
        }
        offer.nft.safeTransferFrom(address(this), msg.sender, offer.tokenId);

        emit RentalOfferAccepted(offerId, msg.sender);
    }

    /// @notice Settles the rental after end time; default keeps collateral with lender.
    function settleOffer(bytes32 offerId, bool defaulted)
        external
        onlyRole(LISTING_MANAGER_ROLE)
        nonReentrant
    {
        RentalOffer storage offer = offers[offerId];
        if (!offer.accepted) revert OfferNotAccepted();
        if (offer.settled) revert OfferAlreadySettled();
        if (block.timestamp < offer.endTimestamp) revert OfferNotFinished();

        offer.settled = true;

        // Manager can reclaim the NFT only if renter approved this vault as operator.
        offer.nft.safeTransferFrom(offer.renter, offer.lender, offer.tokenId);

        uint256 fee = (offer.rentAmount * protocolFeeBps) / BPS;
        if (fee > 0) {
            paymentToken.safeTransfer(feeRecipient, fee);
        }
        paymentToken.safeTransfer(offer.lender, offer.rentAmount - fee);
        paymentToken.safeTransfer(defaulted ? offer.lender : offer.renter, offer.collateralAmount);

        emit RentalOfferSettled(offerId, defaulted);
    }

    /// @notice Updates protocol fee basis points and recipient.
    function setFeeConfig(uint16 newFeeBps, address newFeeRecipient)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newFeeBps > BPS) revert InvalidFeeBps();
        if (newFeeRecipient == address(0)) revert ZeroAddress();

        uint16 oldFeeBps = protocolFeeBps;
        address oldFeeRecipient = feeRecipient;
        protocolFeeBps = newFeeBps;
        feeRecipient = newFeeRecipient;

        emit FeeConfigUpdated(oldFeeBps, newFeeBps, oldFeeRecipient, newFeeRecipient);
    }

    /// @notice Pauses creating and accepting offers.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses creating and accepting offers.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
