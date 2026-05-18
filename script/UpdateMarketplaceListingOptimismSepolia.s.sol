// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { GameItemMarketplace } from "../src/GameItemMarketplace.sol";

contract UpdateMarketplaceListingOptimismSepolia is Script {
    uint256 private constant OLD_LISTING_ID = 1;
    uint256 private constant DEMO_ITEM_ID = 30;
    uint256 private constant DEMO_AMOUNT = 1;
    uint256 private constant NEW_PRICE = 0.001 ether;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        GameItemMarketplace marketplace = GameItemMarketplace(vm.envAddress("MARKETPLACE"));

        vm.startBroadcast(deployerKey);

        marketplace.cancel(OLD_LISTING_ID);
        uint256 newListingId =
            marketplace.createListing(DEMO_ITEM_ID, DEMO_AMOUNT, NEW_PRICE, payable(deployer));

        vm.stopBroadcast();

        console2.log("MARKETPLACE_LISTING_ID=", newListingId);
        console2.log("MARKETPLACE_LISTING_PRICE_WEI=", NEW_PRICE);
    }
}
