// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { GovernanceToken } from "../src/GovernanceToken.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";

contract MockGovTarget {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

contract GovernanceDelegationTest is Test {
    GovernanceToken internal govToken;
    ProtocolGovernor internal governor;
    TimelockController internal timelock;
    MockGovTarget internal target;

    address internal proposer = address(0xAA01);
    address internal voter = address(0xBB02);
    address internal lowPower = address(0xCC03);

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

    function setUp() public {
        govToken = new GovernanceToken(
            "Governance Token", "GOV", INITIAL_SUPPLY, address(this), address(this)
        );
        target = new MockGovTarget();

        govToken.transfer(proposer, 120_000 ether);
        govToken.transfer(voter, 80_000 ether);
        govToken.transfer(lowPower, 2_000 ether);

        vm.prank(proposer);
        govToken.delegate(proposer);
        vm.prank(voter);
        govToken.delegate(voter);
        vm.prank(lowPower);
        govToken.delegate(lowPower);

        vm.warp(block.timestamp + 1);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new TimelockController(2 days, proposers, executors, address(this));

        uint256 threshold = (INITIAL_SUPPLY * 100) / 10_000;
        governor = new ProtocolGovernor(govToken, timelock, threshold);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
    }

    function testDelegationTracksVotingPower() public {
        assertEq(govToken.getVotes(proposer), 120_000 ether);
        assertEq(govToken.getVotes(voter), 80_000 ether);
        assertEq(govToken.getVotes(lowPower), 2_000 ether);
    }

    function testLowPowerProposerReverts() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(target);
        calldatas[0] = abi.encodeCall(MockGovTarget.setValue, (42));

        vm.prank(lowPower);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Low power should fail");
    }

    function testVoteWeightUsesSnapshotNotCurrentBalance() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Snapshot behavior";

        targets[0] = address(target);
        calldatas[0] = abi.encodeCall(MockGovTarget.setValue, (7));

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        uint256 snapshot = governor.proposalSnapshot(proposalId);
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        uint256 expectedWeight = govToken.getPastVotes(proposer, snapshot);

        vm.prank(proposer);
        govToken.transfer(voter, 60_000 ether);
        vm.prank(voter);
        govToken.delegate(voter);

        vm.prank(proposer);
        governor.castVote(proposalId, uint8(1)); // For

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, expectedWeight);
    }

    function testFuzzDelegatedVotingPowerTracksBalance(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1 ether, 50_000 ether);
        address delegatee = address(0xD1E6A7E);

        govToken.transfer(delegatee, amount);
        vm.prank(delegatee);
        govToken.delegate(delegatee);

        assertEq(govToken.getVotes(delegatee), amount);
    }

    function testFuzzProposalThresholdIsOnePercent(uint128 rawSupply) public view {
        uint256 supply = bound(uint256(rawSupply), 100 ether, type(uint128).max);

        assertEq(governor.thresholdFromSupply(supply), supply / 100);
    }
}
