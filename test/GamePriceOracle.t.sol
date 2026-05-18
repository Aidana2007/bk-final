// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { GamePriceOracle } from "../src/GamePriceOracle.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

contract GamePriceOracleTest is Test {
    bytes32 internal constant ETH_USD = keccak256("ETH/USD");

    GamePriceOracle internal oracle;
    MockAggregatorV3 internal feed;

    function setUp() public {
        oracle = new GamePriceOracle(address(this));
        feed = new MockAggregatorV3(8, 3_000e8, block.timestamp);
        oracle.setFeed(ETH_USD, AggregatorV3Interface(address(feed)));
    }

    function testLatestPriceReturnsFreshFeedData() public {
        (int256 price, uint8 decimals, uint256 updatedAt) = oracle.latestPrice(ETH_USD);

        assertEq(price, 3_000e8);
        assertEq(decimals, 8);
        assertEq(updatedAt, block.timestamp);
    }

    function testStalePriceReverts() public {
        vm.warp(2 days);
        oracle.setMaxPriceAge(30 minutes);
        feed.setRoundData(3_000e8, block.timestamp - 31 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                GamePriceOracle.StalePrice.selector, block.timestamp - 31 minutes, 30 minutes
            )
        );
        oracle.latestPrice(ETH_USD);
    }

    function testMissingFeedReverts() public {
        vm.expectRevert(GamePriceOracle.MissingFeed.selector);
        oracle.latestPrice(keccak256("BTC/USD"));
    }

    function testInvalidPriceReverts() public {
        feed.setRoundData(0, block.timestamp);

        vm.expectRevert(GamePriceOracle.InvalidPrice.selector);
        oracle.latestPrice(ETH_USD);
    }
}
