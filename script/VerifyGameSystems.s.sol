// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract VerifyGameSystems is Script {
    function run() external view {
        require(vm.envAddress("GAME_ITEMS") != address(0), "GAME_ITEMS missing");
        require(vm.envAddress("CRAFTING_SYSTEM") != address(0), "CRAFTING_SYSTEM missing");
        require(vm.envAddress("VRF_LOOT_DROP") != address(0), "VRF_LOOT_DROP missing");
        require(vm.envAddress("GAME_PRICE_ORACLE") != address(0), "GAME_PRICE_ORACLE missing");
    }
}