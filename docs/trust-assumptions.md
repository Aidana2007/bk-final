# Trust Assumptions

## Governance and Timelock
- Token holders are assumed to delegate and participate honestly enough to avoid capture.
- `ProtocolGovernor` is trusted only as an execution router; authority is constrained by voting outcomes.
- `TimelockController` is the effective privileged operator for treasury actions.
- A 2-day delay is assumed sufficient for community monitoring and emergency exit actions.

## Admin and Role Holders
- Any account with `DEFAULT_ADMIN_ROLE` can reconfigure roles; this is a centralization risk until fully transferred to governance.
- `MINTER_ROLE` and `BURNER_ROLE` on `GovernanceToken` can materially change voting dynamics if abused.
- `LISTING_MANAGER_ROLE` in `RentalVault` can settle defaults and therefore influences collateral distribution.

## Treasury and Vault Security
- `TreasuryVault` admin operations must be executed through timelock-controlled roles in production.
- `rescueToken` intentionally disallows the vault asset to avoid draining depositor funds.
- ERC4626 rounding behavior follows OpenZeppelin v5 and is tested with conversion invariants.

## Operational Assumptions
- Off-chain monitoring should track:
  - queued timelock operations,
  - role changes on all contracts,
  - governance parameter changes (threshold/quorum/delay/period).
- Deployment scripts must revoke legacy direct manager privileges after role transfer to timelock.
