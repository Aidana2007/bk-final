# Access-Control Vulnerability Case Study

## Finding
- **Title:** Unguarded treasury recipient mutation
- **Severity:** High
- **Pattern:** Missing access control on privileged setter

## Vulnerable Pattern (Before)
- An insecure treasury allowed any caller to execute:
  - `setTreasuryRecipient(address)`
  - then drain funds to the attacker-controlled recipient.

## Exploit Path
1. Attacker calls unguarded `setTreasuryRecipient(attacker)`.
2. Attacker triggers withdrawal/drain function.
3. Treasury funds are redirected.

## Fix (After)
- Replaced unguarded admin mutation with role-gated logic:
  - `TreasuryVault.setTreasuryRecipient` uses `onlyRole(VAULT_MANAGER_ROLE)`.
- In production configuration:
  - `VAULT_MANAGER_ROLE` must be granted to timelock.
  - legacy EOA manager role must be revoked.

## Proof in Tests
- Vulnerability reproduction:
  - `test/AccessControlCaseStudy.t.sol::testVulnerability_InsecureRecipientCanBeHijacked`
- Fix verification:
  - `test/AccessControlCaseStudy.t.sol::testFix_SecureVaultRejectsUnauthorizedAdminCall`

## Residual Risk
- If `DEFAULT_ADMIN_ROLE` remains with a hot wallet, role escalation is still possible.
- Mitigation: move `DEFAULT_ADMIN_ROLE` under timelock governance or hardened multisig.
