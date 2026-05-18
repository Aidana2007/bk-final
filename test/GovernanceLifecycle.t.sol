// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { GovernanceToken } from "../src/GovernanceToken.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";
import { TreasuryVault } from "../src/TreasuryVault.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract GovernanceLifecycleTest is Test {
    GovernanceToken internal govToken;
    ProtocolGovernor internal governor;
    TimelockController internal timelock;
    TreasuryVault internal treasuryVault;
    MockERC20 internal usdc;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal executor = address(0xE11);
    address internal treasuryRecipient = address(0x7777);
    address internal newRecipient = address(0x8888);

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC");
        govToken = new GovernanceToken(
            "Governance Token", "GOV", INITIAL_SUPPLY, address(this), address(this)
        );

        // Distribute voting power and self-delegate.
        govToken.transfer(alice, 120_000 ether);
        govToken.transfer(bob, 80_000 ether);
        vm.prank(alice);
        govToken.delegate(alice);
        vm.prank(bob);
        govToken.delegate(bob);

        // Timestamp-based voting snapshots need one second before "past vote" lookups.
        vm.warp(block.timestamp + 1);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new TimelockController(2 days, proposers, executors, address(this));

        uint256 threshold = (INITIAL_SUPPLY * 100) / 10_000;
        governor = new ProtocolGovernor(govToken, timelock, threshold);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        treasuryVault = new TreasuryVault(
            usdc,
            "Treasury Vault Share",
            "tvSHARE",
            address(this),
            treasuryRecipient,
            type(uint256).max
        );
        treasuryVault.grantRole(treasuryVault.VAULT_MANAGER_ROLE(), address(timelock));
        treasuryVault.revokeRole(treasuryVault.VAULT_MANAGER_ROLE(), address(this));
    }

    function testGovernanceConfigMatchesSpec() public {
        assertEq(governor.votingDelay(), 1 minutes);
        assertEq(governor.votingPeriod(), 1 days);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function testDirectTreasuryAdminCallRevertsAfterRoleRevocation() public {
        vm.expectRevert();
        treasuryVault.setTreasuryRecipient(newRecipient);
    }

    function testProposeVoteQueueExecuteLifecycle() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Update treasury recipient via governance";

        targets[0] = address(treasuryVault);
        calldatas[0] = abi.encodeCall(TreasuryVault.setTreasuryRecipient, (newRecipient));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, uint8(1)); // For
        vm.prank(bob);
        governor.castVote(proposalId, uint8(1)); // For

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        vm.prank(executor);
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(treasuryVault.treasuryRecipient(), newRecipient);
    }
}
