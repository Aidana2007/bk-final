// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {AMMFactory} from "../src/AMMFactory.sol";
import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";

contract DeployOptimismSepolia is Script {
    function run() external returns (ConstantProductAMM implementation, AMMFactory factory) {
        vm.startBroadcast();
        address deployer = msg.sender;
        implementation = new ConstantProductAMM();
        factory = new AMMFactory(address(implementation), deployer, deployer);
        vm.stopBroadcast();
    }
}
