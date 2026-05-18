// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import {
    IVRFSubscriptionV2Plus
} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";
import { GameItems } from "../src/GameItems.sol";
import { IGameItems } from "../src/interfaces/IGameItems.sol";
import { VRFLootDrop } from "../src/VRFLootDrop.sol";

contract RepairLootDropOptimismSepolia is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        GameItems gameItems = GameItems(vm.envAddress("GAME_ITEMS"));
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");

        vm.startBroadcast(deployerKey);

        VRFLootDrop lootDrop = new VRFLootDrop(
            IGameItems(address(gameItems)), vrfCoordinator, subscriptionId, keyHash, deployer
        );

        gameItems.grantRole(gameItems.MINTER_ROLE(), address(lootDrop));
        IVRFSubscriptionV2Plus(vrfCoordinator).addConsumer(subscriptionId, address(lootDrop));

        VRFLootDrop.LootEntry[] memory lootEntries = new VRFLootDrop.LootEntry[](3);
        lootEntries[0] =
            VRFLootDrop.LootEntry({ itemId: 20, weight: 70, minAmount: 1, maxAmount: 2 });
        lootEntries[1] =
            VRFLootDrop.LootEntry({ itemId: 21, weight: 25, minAmount: 1, maxAmount: 1 });
        lootEntries[2] =
            VRFLootDrop.LootEntry({ itemId: 22, weight: 5, minAmount: 1, maxAmount: 1 });
        lootDrop.setLootTable(lootEntries);

        vm.stopBroadcast();

        console2.log("VRF_LOOT_DROP=", address(lootDrop));
    }
}
