# Timelock Verification Script

## Script
- File: `script/VerifyGovernanceConfig.s.sol`

## What It Verifies
- Governor is bound to the expected timelock.
- Timelock delay is exactly `2 days`.
- Governor parameters:
  - `votingDelay = 1 day`
  - `votingPeriod = 1 week`
  - `quorumNumerator = 4`
- Governor has required timelock roles (`PROPOSER_ROLE`, `CANCELLER_ROLE`).
- Timelock executor is open (`EXECUTOR_ROLE` granted to `address(0)`).
- Timelock has `VAULT_MANAGER_ROLE` on treasury vault.
- Legacy admin does **not** retain `VAULT_MANAGER_ROLE`.
- Legacy admin does **not** retain `DEFAULT_ADMIN_ROLE` on timelock/vault.

## Run
```bash
forge script script/VerifyGovernanceConfig.s.sol:VerifyGovernanceConfig \
  --sig "run(address,address,address,address)" \
  0xGovernor 0xTimelock 0xTreasuryVault 0xLegacyAdmin
```
