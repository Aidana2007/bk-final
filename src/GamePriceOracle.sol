// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract GamePriceOracle is AccessControl {
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    mapping(bytes32 => AggregatorV3Interface) public feeds;

    event FeedSet(bytes32 indexed pair, address indexed feed);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_MANAGER_ROLE, admin);
    }

    function setFeed(bytes32 pair, AggregatorV3Interface feed) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(address(feed) != address(0), "Oracle: zero feed");
        feeds[pair] = feed;
        emit FeedSet(pair, address(feed));
    }

    function latestPrice(bytes32 pair) external view returns (int256 price, uint8 decimals, uint256 updatedAt) {
        AggregatorV3Interface feed = feeds[pair];
        require(address(feed) != address(0), "Oracle: missing feed");
        (, price,, updatedAt,) = feed.latestRoundData();
        require(price > 0, "Oracle: invalid price");
        return (price, feed.decimals(), updatedAt);
    }
}