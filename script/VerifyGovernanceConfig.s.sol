// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ProtocolGovernor} from "../src/ProtocolGovernor.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";

/// @notice Post-deploy verification script for governance/timelock hard requirements.
contract VerifyGovernanceConfig is Script {
    function run(address governorAddress, address timelockAddress, address treasuryVaultAddress, address legacyAdmin)
        external
        view
    {
        ProtocolGovernor governor = ProtocolGovernor(payable(governorAddress));
        TimelockController timelock = TimelockController(payable(timelockAddress));
        TreasuryVault treasuryVault = TreasuryVault(treasuryVaultAddress);

        require(governor.timelock() == timelockAddress, "Governor timelock mismatch");
        require(timelock.getMinDelay() == 2 days, "Timelock delay must be 2 days");
        require(governor.votingDelay() == 1 days, "Governor votingDelay must be 1 day");
        require(governor.votingPeriod() == 1 weeks, "Governor votingPeriod must be 1 week");
        require(governor.quorumNumerator() == 4, "Governor quorum must be 4 percent");
        require(
            timelock.hasRole(timelock.PROPOSER_ROLE(), governorAddress), "Governor must have PROPOSER_ROLE"
        );
        require(
            timelock.hasRole(timelock.CANCELLER_ROLE(), governorAddress), "Governor must have CANCELLER_ROLE"
        );
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Timelock executor should be open");
        require(
            treasuryVault.hasRole(treasuryVault.VAULT_MANAGER_ROLE(), timelockAddress),
            "Timelock must manage treasury vault"
        );
        require(
            !treasuryVault.hasRole(treasuryVault.VAULT_MANAGER_ROLE(), legacyAdmin),
            "Legacy admin still has vault manager role"
        );
        require(!timelock.hasRole(0x00, legacyAdmin), "Legacy admin still has timelock admin role");
        require(!treasuryVault.hasRole(0x00, legacyAdmin), "Legacy admin still has vault admin role");

        console2.log("Governance verification succeeded.");
        console2.log("Governor", governorAddress);
        console2.log("Timelock", timelockAddress);
        console2.log("TreasuryVault", treasuryVaultAddress);
    }
}
