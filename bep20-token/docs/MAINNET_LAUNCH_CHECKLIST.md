# BUBBAS — Mainnet Launch Checklist

This checklist MUST be completed before deploying to mainnet.

Do not skip steps.

Do not assume values.

Verify everything.

---

# SECTION 1 — Contract Addresses

Confirm the frontend uses the correct deployed addresses.

## Verify:

- [ ] Token address is correct
- [ ] GameRouter address is correct
- [ ] PayoutManager address is correct
- [ ] Chain ID is correct
- [ ] All contract addresses match production deployment records

## Expected

```
chainId = 56
```

---

# SECTION 2 — Wallet Role Mapping

Define the production wallet roles.

These must be verified before deployment.

## Expected Mapping

Owner wallet and Engine wallet are the SAME address.

```
OWNER_WALLET = ENGINE_WALLET
```

## Confirm:

- [ ] OWNER_WALLET is the Ledger hardware wallet
- [ ] ENGINE_WALLET is the same Ledger hardware wallet
- [ ] OPS_WALLET is the backend / server wallet
- [ ] No test wallets are used
- [ ] All private keys are stored securely

## Safety Confirmation

- [ ] Ledger device is accessible
- [ ] Ledger PIN works
- [ ] Ledger is not locked
- [ ] Recovery phrase is backed up offline

## Gas Readiness

- [ ] Engine wallet has sufficient BNB
- [ ] Ops wallet has sufficient BNB
- [ ] Estimated gas for launch is funded

---

# SECTION 3 — Wallet Ownership Verification

Verify control of all critical wallets.

Run:

```
await token.owner()
await token.engine()
await token.opsWallet()
```

Both `owner()` and `engine()` must return the **same address** (Ledger).

## Confirm:

- [ ] owner is the Ledger hardware wallet
- [ ] engine is the same Ledger hardware wallet
- [ ] owner() === engine() (same address)
- [ ] opsWallet is the backend wallet
- [ ] No test wallets are used

---

# SECTION 4 — System State

Verify the contract is in the correct operational state.

Run:

```
await token.maxPayoutPerTx()
await token.feesEnabled()
await token.emergencyMode()
await token.enginePaused()
await token.owner()

await router.engine()
await payoutManager.owner()
```

## Confirm:

- [ ] feesEnabled = true
- [ ] emergencyMode = false
- [ ] enginePaused = false
- [ ] maxPayoutPerTx is correct
- [ ] router.engine() matches token ENGINE_WALLET
- [ ] payoutManager.owner() matches Ledger wallet

---

# SECTION 5 — Security Controls

Verify emergency and pause controls.

## Confirm:

- [ ] emergencyMode works
- [ ] enginePaused works
- [ ] systemPayout still works when emergencyMode is enabled
- [ ] Only engine wallet can execute router calls

---

# SECTION 6 — Contract Verification

Confirm contracts are verified on BSCScan.

## Confirm:

- [ ] Token is verified
- [ ] GameRouter is verified
- [ ] PayoutManager is verified
- [ ] Source code is visible

---

# SECTION 7 — Frontend Configuration

Verify production configuration.

## Confirm:

- [ ] RPC endpoint is correct
- [ ] Network is BSC mainnet
- [ ] No testnet addresses remain
- [ ] Environment variables are correct

---

# SECTION 8 — Final Sanity Test

Perform one live test.

## Test:

1) Send a small transfer
2) Execute one system payout
3) Confirm balances update

## Confirm:

- [ ] Transfer works
- [ ] Payout works
- [ ] Fees behave correctly
- [ ] Events are emitted

---

# SECTION 9 — Launch Approval

All checks must pass.

## Sign-off

```
Deployment Approved By:

Name: Stroem
Date: 2026-03-29
Time: 12:03 (CEST)
```

---

# SECTION 10 — Backup & Recovery

Verify that recovery paths exist.

## Confirm:

- [ ] Engine wallet recovery phrase is backed up securely
- [ ] Owner wallet recovery phrase is backed up securely
- [ ] Ops wallet recovery phrase is backed up securely
- [ ] Hardware wallet PIN and passphrase are documented
- [ ] Emergency contacts are defined

---

# SECTION 11 — Monitoring

Verify monitoring is active.

## Confirm:

- [ ] BSCScan alerts configured
- [ ] RPC health monitoring configured
- [ ] Error logging enabled
- [ ] Transaction failure alerts configured
- [ ] Payout failure alerts configured

---

# CRITICAL — Deploy → Verify → Launch Sequence

Follow this exact order.

Do not skip steps.

---

## STEP 1 — Deploy Contracts

Deploy:

- BUBBAS Token
- GameRouter
- PayoutManager

Confirm:

- [ ] Deployment succeeded
- [ ] Transactions confirmed
- [ ] Contract addresses recorded

---

## STEP 2 — Verify Contracts

Verify on BSCScan.

Confirm:

- [ ] Token verified
- [ ] GameRouter verified
- [ ] PayoutManager verified
- [ ] Source code visible

---

## STEP 3 — Update Addresses

Replace old addresses everywhere.

Update:

- backend .env
- frontend config
- monitoring
- scripts

Confirm:

- [ ] BUBBA_TOKEN_ADDRESS updated
- [ ] ROUTER_ADDRESS updated
- [ ] PAYOUT_MANAGER_ADDRESS updated
- [ ] No old addresses remain

---

## STEP 4 — Create Liquidity Pair

Create new PancakeSwap LP pair.

Confirm:

- [ ] LP pair created
- [ ] Pair address saved
- [ ] Price service updated

---

## STEP 5 — Verify Contract State

Run:

```
await token.feesEnabled()
await token.emergencyMode()
await token.enginePaused()
await token.payoutsPaused()
await token.dailyPayoutLimit()
```

Confirm:

- [ ] feesEnabled = true
- [ ] emergencyMode = false
- [ ] enginePaused = false
- [ ] payoutsPaused = false
- [ ] dailyPayoutLimit = 0

---

## STEP 6 — Verify Wallets

Confirm:

- [ ] OWNER = Ledger wallet
- [ ] ENGINE = Ledger wallet
- [ ] OPS = backend wallet
- [ ] Wallets have BNB for gas

---

## STEP 7 — Run Live Test

Test:

1) Transfer small amount
2) Execute one withdrawal
3) Verify balances

Confirm:

- [ ] Transfer works
- [ ] Withdrawal works
- [ ] Events emitted
- [ ] No errors

---

## FINAL RULE

Deploy first.
Launch only after all checks pass.

Production launch is allowed only when every box above is checked.

---

This document is mandatory for production deployment.
