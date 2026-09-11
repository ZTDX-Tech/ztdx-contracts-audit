# ZTDX Contracts — CertiK Remediation

This repository contains the ZTDX contracts reviewed in the CertiK preliminary comments (Sept 10th, 2026) and the remediation for those findings.

## Audited deployments

| Contract | Network | Verified address | Path |
|---|---|---|---|
| `ZtdxReserveVault` | Arbitrum One | `0x6be516b0f23ff267fb604cc2321b15d508c395a4` | `vault_contract/src/contracts/core/vault/ZtdxReserveVault.sol` |
| `AffiliateRegistry` | Arbitrum One | `0x3e9d969118b0c73673ee8c99656b0e19776caf37` | `referral_storage_contract/src/contracts/referral/AffiliateRegistry.sol` |
| `ZtdxRewardRouter` | Arbitrum One | `0x89ccd7c28223f4f6a3cd70af418be7a614c50707` | `rebate_contract/src/contracts/core/referral/ZtdxRewardRouter.sol` |
| `SpotVault` | BNB Smart Chain | `0xcd3ee13d7ce9aacd13f778a1b1455c339e779543` | Not included yet (see ZTD-05) |

`ZtdxSpotVault` in `vault_contract` is a separate implementation and is not the audited BSC `SpotVault`.

## How to review

1. **Baseline** (first commit) — the contracts as audited. The three Arbitrum contracts and their interfaces and libraries match the verified sources byte for byte.
2. **Remediation** (later commits) — all code changes for the findings. Diff the baseline commit against `main` to see only the fixes.

## Findings

| ID | Severity | Resolution |
|---|---|---|
| ZTD-01 | Centralization | Acknowledged. |
| ZTD-02 | Centralization | Acknowledged. |
| ZTD-03 | Centralization | Acknowledged. The ZTD-04 limits bound the impact of a compromised signer. |
| ZTD-04 | Medium | By design, with a new bound (see below). |
| ZTD-05 | Minor | Pending: BSC `SpotVault` source to be provided. |
| ZTD-06 | Minor | Fixed: `_setReferralCode` returns the code bound in the registry (zero if none), and `AccountFunded` emits that value. |
| ZTD-07 | Minor | Fixed: `setAffiliateRegistry` rejects the zero address in the Vault and the Router. |
| ZTD-08 | Minor | Fixed: `assignAffiliateTier` reverts with `TierNotConfigured` for tiers never set via `configureTier`. Tiers configured before the upgrade are recognized by a non-zero total rebate. |
| ZTD-09 | Minor | Fixed: `batchSettleRewards` requires `users` to be strictly ascending, which rules out duplicates. |
| ZTD-10 | Informational | Fixed: `setAffiliateRegistry` emits `AffiliateRegistryChanged(old, new)`. |
| ZTD-11 | Informational | Fixed: a referral code can only be bound before or at the account's first funding. `fundAccount` binds only when `fundedTotals` was zero, and `bindAffiliateCode` reverts with `AffiliateBindingClosed` once the account has been funded. |
| ZTD-12 | Discussion | Clarified: `aggregateReleases` is documented as user releases only; partner settlements are tracked in `partnerLedgerDebits`. |
| ZTD-13 | Discussion | Fixed: `authorizeHandler` / `removeHandler` use `_grantRole` / `_revokeRole`, so `ADMIN_ROLE` alone can manage handlers. |
| ZTD-14 | Discussion | Fixed: batch settlement advances each paid user's `rewardNonces`, which invalidates any outstanding `redeemReward` signature. |
| ZTD-15 | Discussion | The helper is used by `ZtdxSpotVault` in the same package. It is an internal function, so it is not in the `ZtdxReserveVault` bytecode. |

### ZTD-04: releases above recorded principal

`_balances` records on-chain principal only. The withdrawable balance is kept off-chain and includes realized trading PnL and referral commissions, so an authorized release can legitimately exceed a user's recorded principal. Requiring `amount <= _balances[user]` would block those withdrawals.

To bound the risk of a compromised or faulty signer, the portion of a release above the caller's recorded principal is now subject to two owner-set limits, `setExcessReleaseLimits(txLimit, windowLimit)`:

- `txLimit` caps the excess in a single `releaseFunds` call.
- `windowLimit` caps the cumulative excess per 24-hour window.

Zero disables a limit. Releases within principal do not consume the allowance. Because a signature binds `account = msg.sender`, an attacker holding the signer key can only withdraw to addresses they control, so the loss is bounded by the window limit.

### Other change

`pause` / `unpause` in `ZtdxReserveVault` no longer emit `Paused` / `Unpaused` a second time; `PausableUpgradeable` already emits them.

## Upgrade safety

All three contracts are UUPS implementations. New state is appended after the existing variables and `__gap` is shrunk to match, so existing slots, types and the end of the gap are unchanged against the deployed implementations. No reinitializer is needed; the new limits default to zero (disabled).

## Build and test

Each directory is a standalone Foundry project. Dependencies are not committed.

```bash
cd vault_contract   # or rebate_contract, referral_storage_contract
forge install --no-git foundry-rs/forge-std
forge install --no-git OpenZeppelin/openzeppelin-contracts@v5.0.2
forge install --no-git OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2
forge build
forge test
```

Compiler settings are in each `foundry.toml`: solc 0.8.20, optimizer 200 runs, evm `shanghai`.
