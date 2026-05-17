// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {GameItems} from "../src/GameItems.sol";
import {IGameItems} from "../src/interfaces/IGameItems.sol";
import {CraftingSystem} from "../src/CraftingSystem.sol";
import {GamePriceOracle} from "../src/GamePriceOracle.sol";
import {VRFLootDrop} from "../src/VRFLootDrop.sol";
import {AMMFactory} from "../src/AMMFactory.sol";
import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";

contract DeployOptimismSepolia is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");

        vm.startBroadcast(deployerKey);

        ConstantProductAMM implementation = new ConstantProductAMM();
        AMMFactory factory = new AMMFactory(address(implementation), deployer, deployer);

        GameItems gameItems = new GameItems("ipfs://game-items/{id}.json", deployer);
        CraftingSystem crafting = new CraftingSystem(IGameItems(address(gameItems)), deployer);
        GamePriceOracle oracle = new GamePriceOracle(deployer);
        VRFLootDrop lootDrop =
            new VRFLootDrop(IGameItems(address(gameItems)), vrfCoordinator, subscriptionId, keyHash, deployer);

        gameItems.grantRole(gameItems.MINTER_ROLE(), address(crafting));
        gameItems.grantRole(gameItems.MINTER_ROLE(), address(lootDrop));

        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](2);
        ingredients[0] = CraftingSystem.Ingredient({itemId: 1, amount: 2});
        ingredients[1] = CraftingSystem.Ingredient({itemId: 2, amount: 1});
        crafting.createRecipe(10, 1, ingredients);

        VRFLootDrop.LootEntry[] memory lootEntries = new VRFLootDrop.LootEntry[](3);
        lootEntries[0] = VRFLootDrop.LootEntry({itemId: 20, weight: 70, minAmount: 1, maxAmount: 2});
        lootEntries[1] = VRFLootDrop.LootEntry({itemId: 21, weight: 25, minAmount: 1, maxAmount: 1});
        lootEntries[2] = VRFLootDrop.LootEntry({itemId: 22, weight: 5, minAmount: 1, maxAmount: 1});
        lootDrop.setLootTable(lootEntries);

        console2.log("AMM_IMPLEMENTATION=", address(implementation));
        console2.log("AMM_FACTORY=", address(factory));
        console2.log("GAME_ITEMS=", address(gameItems));
        console2.log("CRAFTING_SYSTEM=", address(crafting));
        console2.log("GAME_PRICE_ORACLE=", address(oracle));
        console2.log("VRF_LOOT_DROP=", address(lootDrop));
        console2.log("BOOTSTRAP_RECIPE_ID=1");

        vm.stopBroadcast();
    }
}