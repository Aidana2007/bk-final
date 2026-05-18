// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";

contract CreateDemoProposalOptimismSepolia is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        ProtocolGovernor governor = ProtocolGovernor(payable(vm.envAddress("GOVERNOR")));

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Keep voting period at 1 day";

        targets[0] = address(governor);
        calldatas[0] = abi.encodeCall(governor.setVotingPeriod, (uint32(1 days)));

        vm.startBroadcast(deployerKey);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopBroadcast();

        console2.log("PROPOSAL_ID=", proposalId);
        console2.log("DESCRIPTION=", description);
        console2.log("VOTING_DELAY_SECONDS=", governor.votingDelay());
        console2.log("TRACK_THIS_ID_IN_WEBSITE=", proposalId);
    }
}
