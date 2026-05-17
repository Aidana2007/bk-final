# Storage Layout Diagrams

## GovernanceToken
```text
[ERC20]
  _balances
  _allowances
  _totalSupply
  _name
  _symbol

[ERC20Votes/Votes]
  _delegatee
  _delegateCheckpoints
  _totalCheckpoints

[AccessControl]
  _roles[role].hasRole[account]
  _roles[role].adminRole
```

## ProtocolGovernor
```text
[Governor]
  _name
  _proposals[proposalId] => ProposalCore
  _governanceCall (queue)

[GovernorSettings]
  _proposalThreshold
  _votingDelay
  _votingPeriod

[GovernorVotesQuorumFraction]
  _quorumNumeratorHistory

[GovernorTimelockControl]
  _timelock
  _timelockIds[proposalId]
```

## TreasuryVault
```text
[ERC20 share token]
  _balances
  _allowances
  _totalSupply

[ERC4626]
  _asset (immutable)
  _underlyingDecimals (immutable)

[TreasuryVault custom]
  depositCap
  treasuryRecipient

[AccessControl]
  _roles mapping
```

## RentalVault
```text
[RentalVault custom]
  paymentToken (immutable)
  feeRecipient
  protocolFeeBps
  offerNonce
  offers[offerId] => RentalOffer

[AccessControl]
  _roles mapping
```

## Upgrade/Collision Notes
- `GovernanceToken`, `ProtocolGovernor`, `TreasuryVault`, and `RentalVault` are non-proxy contracts in this module.
- The AMM module remains the UUPS-upgradeable component; this governance/vault module keeps standard constructor-based storage to minimize complexity.
- For any future proxy migration, keep storage append-only and run layout diff checks before upgrade.
