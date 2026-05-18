// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract GamePriceOracle is AccessControl {
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    uint256 public constant DEFAULT_MAX_PRICE_AGE = 1 days;

    mapping(bytes32 => AggregatorV3Interface) public feeds;
    uint256 public maxPriceAge;

    event FeedSet(bytes32 indexed pair, address indexed feed);
    event MaxPriceAgeSet(uint256 oldMaxPriceAge, uint256 newMaxPriceAge);

    error ZeroAddress();
    error MissingFeed();
    error InvalidPrice();
    error StalePrice(uint256 updatedAt, uint256 maxPriceAge);

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_MANAGER_ROLE, admin);
        maxPriceAge = DEFAULT_MAX_PRICE_AGE;
    }

    function setFeed(bytes32 pair, AggregatorV3Interface feed)
        external
        onlyRole(ORACLE_MANAGER_ROLE)
    {
        if (address(feed) == address(0)) revert ZeroAddress();
        feeds[pair] = feed;
        emit FeedSet(pair, address(feed));
    }

    function setMaxPriceAge(uint256 newMaxPriceAge) external onlyRole(ORACLE_MANAGER_ROLE) {
        if (newMaxPriceAge == 0) revert InvalidPrice();
        uint256 oldMaxPriceAge = maxPriceAge;
        maxPriceAge = newMaxPriceAge;
        emit MaxPriceAgeSet(oldMaxPriceAge, newMaxPriceAge);
    }

    function latestPrice(bytes32 pair)
        external
        view
        returns (int256 price, uint8 decimals, uint256 updatedAt)
    {
        AggregatorV3Interface feed = feeds[pair];
        if (address(feed) == address(0)) revert MissingFeed();
        (, price,, updatedAt,) = feed.latestRoundData();
        if (price <= 0 || updatedAt == 0 || updatedAt > block.timestamp) revert InvalidPrice();
        if (block.timestamp - updatedAt > maxPriceAge) revert StalePrice(updatedAt, maxPriceAge);
        return (price, feed.decimals(), updatedAt);
    }
}
