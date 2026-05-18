// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";

contract RedeployGovernanceOptimismSepolia is Script {
    uint256 private constant INITIAL_GOV_SUPPLY = 1_000_000 ether;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        GovernanceToken governanceToken = new GovernanceToken(
            "Capstone Governance", "CGOV", INITIAL_GOV_SUPPLY, deployer, deployer
        );
        governanceToken.delegate(deployer);

        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        TimelockController timelock = new TimelockController(2 days, proposers, executors, deployer);
        uint256 threshold = (INITIAL_GOV_SUPPLY * 100) / 10_000;
        ProtocolGovernor governor = new ProtocolGovernor(governanceToken, timelock, threshold);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        vm.stopBroadcast();

        console2.log("GOVERNANCE_TOKEN=", address(governanceToken));
        console2.log("TIMELOCK=", address(timelock));
        console2.log("GOVERNOR=", address(governor));
        console2.log("VOTING_DELAY=", governor.votingDelay());
        console2.log("VOTING_PERIOD=", governor.votingPeriod());
    }
}
