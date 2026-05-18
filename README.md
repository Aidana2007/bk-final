# Capstone Constant-Product AMM

Production-style Solidity protocol module for a Blockchain Technologies 2 capstone. The system implements an upgradeable constant-product AMM (`x * y = k`) with LP shares, CREATE/CREATE2 factory deployments, slippage protection, a 0.3% swap fee, fuzz/invariant tests, and a Yul gas benchmark.

## Stack

- Solidity `^0.8.24`
- Foundry project layout
- OpenZeppelin Contracts `v5.6.1`
- OpenZeppelin UUPS/ERC1967 upgrade pattern
- `SafeERC20` for all token transfers
- Custom errors, CEI-oriented flow, pausing, and `ReentrancyGuard`

## Suggested Repo Structure

```text
src/
  AMMFactory.sol
  AMMLPToken.sol
  ConstantProductAMM.sol
  ConstantProductAMMV2.sol
  GovernanceToken.sol
  ProtocolGovernor.sol
  TreasuryVault.sol
  RentalVault.sol
  interfaces/
    IAMMLPToken.sol
test/
  AMMFactory.t.sol
  AMMFuzz.t.sol
  AMMInvariant.t.sol
  AMMGas.t.sol
  GovernanceLifecycle.t.sol
  GovernanceDelegation.t.sol
  TreasuryVaultInvariant.t.sol
  AccessControlCaseStudy.t.sol
  RentalVault.t.sol
  mocks/
    MockERC20.sol
    MockERC721.sol
script/
  DeployOptimismSepolia.s.sol
  VerifyGovernanceConfig.s.sol
docs/
  governance-architecture.md
  storage-layout-diagrams.md
  trust-assumptions.md
  security-access-control-case-study.md
  timelock-verification.md
## Commands

```bash
forge fmt
forge fmt --check
forge build
forge test
forge coverage
forge test --match-contract AMMInvariantTest
forge test --match-contract GovernanceLifecycleTest
forge test --match-contract TreasuryVaultInvariantTest
forge snapshot --match-contract AMMGasTest
slither . --filter-paths "node_modules|test|script"
```

Deploy to Optimism Sepolia:

```bash
forge script script/DeployOptimismSepolia.s.sol:DeployOptimismSepolia \
  --rpc-url $OPTIMISM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

The deployer address becomes both `upgradeAdmin` and `factoryOwner`. Transfer ownership to a multisig or timelock after deployment for a production-like L2 setup.

## Architecture

`AMMFactory` deploys one UUPS/ERC1967 proxy per pair. `createPool` uses normal `CREATE`; `createPoolDeterministic` uses `CREATE2` for both the LP token and the pool proxy. The factory sorts token addresses, prevents duplicate pairs, and transfers LP token ownership to the deployed pool.

`ConstantProductAMM` stores reserves in an ERC-7201-style namespaced storage slot so future upgrades can add storage without colliding with inherited OpenZeppelin state. The pool owner is the configured upgrade admin and must authorize UUPS upgrades.

`AMMLPToken` is a minimal ERC20 receipt token. Only the owning pool can mint or burn LP shares. Initial liquidity locks `MINIMUM_LIQUIDITY` to avoid first-LP share inflation edge cases.

The governance module uses a full OpenZeppelin stack: `GovernanceToken` (`ERC20Votes + Permit`) + `ProtocolGovernor` + `TimelockController` (2-day delay). `TreasuryVault` is an `ERC4626` treasury vault with role-gated management, designed to be controlled by timelock roles after deployment.

## CREATE2 Salt Scheme

The public salt is combined with the sorted token pair and a domain string:

```text
LP salt    = keccak256("LP", token0, token1, userSalt)
Pool salt  = keccak256("POOL", token0, token1, userSalt)
```

The predicted pool address depends on the predicted LP token address because the LP token is included in the proxy initializer calldata.

## Security Considerations

- Standard ERC20 tokens are assumed. Fee-on-transfer, rebasing, callback-heavy, or ERC777-like assets should be blocked at listing/governance level.
- Swaps enforce `amountOutMin`; liquidity add/remove enforce minimum output bounds.
- The swap path checks that `k` does not decrease after applying the 0.3% fee formula.
- External token interactions use `SafeERC20`; state-changing entry points use `nonReentrant`.
- The pool owner can pause and unpause liquidity and swap entry points.
- UUPS upgrades are owner-gated and tested for storage preservation.
- The factory should be owned by a multisig or timelock for an L2 deployment.
- Run `forge snapshot`, invariant tests, and a storage layout check before each implementation upgrade.
- The contracts are capstone-ready but should still receive a human audit before handling real value.

## Checklist Status

- AMM logic: implemented.
- Security basics: implemented, including pause support, custom errors, `SafeERC20`, owner-gated admin actions, and no ETH transfer surface.
- Upgradeability: UUPS implementation, initializer, `_authorizeUpgrade`, V1 to V2 test target, storage preservation test, namespaced storage, and explicit gap.
- Factory and CREATE2: implemented with address prediction and documented salt derivation.
- Tests: unit, fuzz, invariant, and gas benchmark contracts are present.
- Yul benchmark: local `solc` estimates show `getAmountOutYul` at 703 gas vs 837 gas for the Solidity benchmark wrapper. A real `.gas-snapshot` is generated with `forge snapshot` once Foundry is available.
- CI/CD: GitHub Actions runs format, build, tests, coverage, gas snapshot check, and Slither.
- Code comments: NatSpec is included on the public contract surface for checklist/readiness review.
- Local verification: Foundry `v1.7.1` installed; `forge fmt --check`, `forge build`, `forge test`, `forge coverage`, and the AMM gas snapshot have been run.
- Current full test result: 134 passing Solidity tests, 0 failing tests, and 0 skipped tests.
- Current fork test result: 3 passing Optimism Sepolia fork tests, 0 failing tests, and 0 skipped tests when `OPTIMISM_SEPOLIA_RPC_URL` is configured.
- Coverage: 92.63% source line coverage; see `docs/coverage-report.md`.
- Gas report: current AMM formula benchmark is documented in `docs/gas-report.md`.
- Security report: local Slither detector execution is documented in `docs/slither-report.md`; the run is blocked by a local `crytic-compile`/Foundry build-info parsing issue.
