# BUBBAS Operations Runbook

> **Runbook Version:** 1.0  
> **Last Updated:** 2026-03-25  
> **Contract Version:** v2.0.0

All operations below assume you are the **contract owner** unless otherwise noted.  
Call functions via your multisig, Hardhat console, Foundry cast, or BSCScan Write Contract UI.

---

## Table of Contents

1. [Pause & Resume Payouts](#1-pause--resume-payouts)
2. [Pause the Entire Engine](#2-pause-the-entire-engine)
3. [Emergency Mode (Freeze All Transfers)](#3-emergency-mode-freeze-all-transfers)
4. [Adjust Payout Limits](#4-adjust-payout-limits)
5. [Rotate the Engine Address](#5-rotate-the-engine-address)
6. [Rotate the OPS Wallet](#6-rotate-the-ops-wallet)
7. [Enable / Disable Fees](#7-enable--disable-fees)
8. [LP Management](#8-lp-management)
9. [PayoutManager — Global Pause](#9-payoutmanager--global-pause)
10. [PayoutManager — Pool Configuration](#10-payoutmanager--pool-configuration)
11. [PayoutManager — Enable / Disable a Pool](#11-payoutmanager--enable--disable-a-pool)
12. [PayoutManager — Adjust Limits at Runtime](#12-payoutmanager--adjust-limits-at-runtime)
13. [PayoutManager — Engine Rotation](#13-payoutmanager--engine-rotation)
14. [PayoutManager — Emergency Withdraw](#14-payoutmanager--emergency-withdraw)
15. [GameRouter — Register / Remove a Game](#15-gamerouter--register--remove-a-game)
16. [GameRouter — Engine Rotation](#16-gamerouter--engine-rotation)
17. [Quick Reference — Incident Response](#17-quick-reference--incident-response)
18. [System Health Check](#18-system-health-check)
19. [Pre-Deployment Checklist](#19-pre-deployment-checklist)
20. [Post-Incident Recovery](#20-post-incident-recovery)
21. [Safe Defaults](#21-safe-defaults)

---

## 1. Pause & Resume Payouts

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`  
**Effect:** Blocks `systemPayout()` calls. Normal user transfers are unaffected.

```solidity
// Stop payouts
setPayoutsPaused(true)

// Resume payouts
setPayoutsPaused(false)
```

Emits: `PayoutsPaused(bool)`

---

## 2. Pause the Entire Engine

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`  
**Effect:** Blocks all `systemPayout()` calls via the `engineActive` modifier. Stronger than `payoutsPaused` — both are checked, either one blocks.

```solidity
// Pause engine
setEnginePaused(true)

// Resume engine
setEnginePaused(false)
```

Emits: `EnginePaused(bool)`

---

## 3. Emergency Mode (Freeze All Transfers)

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`  
**Effect:** Only system wallets and the engine can send tokens. All user transfers are blocked.

```solidity
// Activate emergency mode
setEmergencyMode(true)

// Deactivate
setEmergencyMode(false)
```

Emits: `EmergencyModeSet(bool)`

> **Warning:** This halts ALL user trading including DEX swaps. Use only in critical situations.

---

## 4. Adjust Payout Limits

### Max payout per transaction

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`

```solidity
// Lower the cap (e.g. 100k tokens)
setMaxPayoutPerTx(100000000000000000000000)

// Set to 0 to block all payouts
setMaxPayoutPerTx(0)

// Restore default (1M tokens)
setMaxPayoutPerTx(1000000000000000000000000)
```

Emits: `MaxPayoutUpdated(uint256)`

> **Note:** Setting to `0` effectively stops all payouts since `require(amount <= maxPayoutPerTx)` will fail for any positive amount.

### Daily payout limit

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`

```solidity
// Set daily cap (e.g. 5M tokens)
setDailyPayoutLimit(5000000000000000000000000)

// Disable daily cap
setDailyPayoutLimit(0)
```

Emits: `DailyPayoutLimitUpdated(uint256)`

> **Note:** Setting to `0` disables the daily cap entirely (no limit enforced).

---

## 5. Rotate the Engine Address

**Contract:** BUBBAS Token  
**Access:** Step 1 = `onlyOwner`, Step 2 = new engine signs

This is a **2-step process** to prevent accidental engine changes.

```
Step 1 — Owner proposes:
proposeEngine(0xNEW_ENGINE_ADDRESS)

Step 2 — New engine accepts (must call from the new address):
acceptEngine()
```

Emits: `EngineProposed(oldEngine, newEngine)` → `EngineUpdated(oldEngine, newEngine)`

> The owner can call `proposeEngine()` again to change the nominee before acceptance.

---

## 6. Rotate the OPS Wallet

**Contract:** BUBBAS Token  
**Access:** Step 1 = `onlyOwner`, Step 2 = new wallet signs

2-step process. The new wallet inherits fee and reward exclusions.

```
Step 1 — Owner proposes:
proposeOpsWallet(0xNEW_OPS_ADDRESS)

Step 2 — New wallet accepts:
acceptOpsWallet()
```

Emits: `OpsWalletProposed(old, new)` → `OpsWalletUpdated(old, new)`

What happens automatically on acceptance:
- Old wallet loses fee/reward exclusions
- Old wallet is removed from the `_excluded` array
- New wallet gets fee/reward exclusions
- New wallet `_tOwned` is synced from `_rOwned`

---

## 7. Enable / Disable Fees

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`

```solidity
// Disable all transaction fees
setFeesEnabled(false)

// Re-enable fees
setFeesEnabled(true)
```

Emits: `FeesEnabledSet(bool)`

> Takes effect immediately on the next transfer.

---

## 8. LP Management

**Contract:** BUBBAS Token  
**Access:** `onlyOwner`

### Register an LP pair

```solidity
setLP(0xLP_PAIR_ADDRESS)
```

The LP is automatically excluded from fees and reflections. Emits: `LPSet(address)`

### Unregister an LP pair (DEX migration)

```solidity
unsetLP(0xLP_PAIR_ADDRESS)
```

Re-includes in fees and reflections. Cleans up the `_excluded` array. Emits: `LPUnset(address)`

---

## 9. PayoutManager — Global Pause

**Contract:** PayoutManager  
**Access:** `onlyOwner`  
**Effect:** Blocks ALL payouts (single and batch) across ALL pools.

```solidity
// Pause everything
setGlobalPaused(true)

// Resume
setGlobalPaused(false)
```

Emits: `GlobalPaused(bool)`

---

## 10. PayoutManager — Pool Configuration

**Contract:** PayoutManager  
**Access:** `onlyEngine`

### Set a pool wallet

```solidity
setPoolWallet(PoolType.LOTTERY, 0xLOTTERY_WALLET)
```

### Configure pool limits

```solidity
setPoolConfig(
    PoolType.LOTTERY,        // pool type
    500000e18,               // payoutLimitPerBlock
    2000000e18,              // payoutLimitPerMinute
    30,                      // cooldownSeconds (30s between payouts)
    500,                     // maxValuePerMinuteBps (5% of pool per minute)
    1000,                    // maxSinglePayoutBps (10% of pool per payout)
    2000,                    // minReserveBps (20% must remain)
    false                    // drainsOnPayout (cannot drain to zero)
)
```

This sets `initialized = true` and enables the pool for payouts.

Emits: `PoolConfigUpdated(PoolType)` + `PoolInitialized(PoolType)`

> **Important:** `setPoolConfig` can be called again at any time to update limits. New values take effect immediately.

---

## 11. PayoutManager — Enable / Disable a Pool

**Contract:** PayoutManager  
**Access:** `onlyEngine`

```solidity
// Disable a pool (immediately blocks payouts for this pool)
setPoolEnabled(PoolType.LOTTERY, false)

// Re-enable
setPoolEnabled(PoolType.LOTTERY, true)
```

Emits: `PoolEnabled(PoolType, bool)`

---

## 12. PayoutManager — Adjust Limits at Runtime

**Contract:** PayoutManager  
**Access:** `onlyOwner`

### Max recipients per batch

```solidity
setMaxRecipientsPerTx(100)  // lower from 200 default
```

### Max pool balance cap

```solidity
// Set a cap (post-payout balance cannot exceed this)
setMaxPoolBalance(10000000e18)

// Disable cap
setMaxPoolBalance(0)
```

### Re-configure pool limits

Call `setPoolConfig(...)` again with new values (engine-only). All limits are overwritten and take effect immediately.

---

## 13. PayoutManager — Engine Rotation

**Contract:** PayoutManager  
**Access:** Step 1 = `onlyOwner`, Step 2 = new engine signs

```
Step 1 — Owner proposes:
proposeEngine(0xNEW_ENGINE_ADDRESS)

Step 2 — New engine accepts:
acceptEngine()
```

Emits: `EngineProposed(old, new)` → `EngineUpdated(old, new)`

> **Critical:** After rotating the engine in PayoutManager, you likely need to rotate the engine in the Token and GameRouter contracts as well to keep them in sync.

---

## 14. PayoutManager — Emergency Withdraw

**Contract:** PayoutManager  
**Access:** `onlyOwner`  
**Pool:** RESERVE pool only

```solidity
emergencyWithdraw(0xRECIPIENT, 500000e18)
```

Emits: `EmergencyWithdraw(to, amount, timestamp)`

> This bypasses all pool limits and cooldowns. Only works on the RESERVE pool. The reserve wallet must be set and have sufficient balance.

---

## 15. GameRouter — Register / Remove a Game

**Contract:** GameRouter  
**Access:** `onlyOwner`

### Register a game contract

```solidity
setGame(keccak256("COIN_FLIP"), 0xGAME_CONTRACT_ADDRESS)
```

Emits: `GameSet(gameId, address)`

### Remove a game (deactivate)

```solidity
removeGame(keccak256("COIN_FLIP"))
```

Emits: `GameRemoved(gameId)`

> After removal, any `execute()` call with that gameId will revert with "Game not set".

---

## 16. GameRouter — Engine Rotation

**Contract:** GameRouter  
**Access:** `onlyOwner` for both methods

### Direct swap (emergency)

```solidity
setEngine(0xNEW_ENGINE)
```

### 2-step rotation (recommended)

```
Step 1 — Owner proposes:
proposeEngine(0xNEW_ENGINE)

Step 2 — New engine accepts:
acceptEngine()
```

Emits: `EngineUpdated(old, new)`

---

## 17. Quick Reference — Incident Response

### Suspected exploit — stop everything NOW

| Step | Contract | Call |
|------|----------|------|
| 1 | Token | `setEmergencyMode(true)` — freezes all user transfers |
| 2 | Token | `setEnginePaused(true)` — stops engine payouts |
| 3 | PayoutManager | `setGlobalPaused(true)` — stops all pool payouts |

### Suspicious game contract — isolate one game

| Step | Contract | Call |
|------|----------|------|
| 1 | GameRouter | `removeGame(gameId)` — deactivate the game |
| 2 | PayoutManager | `setPoolEnabled(poolType, false)` — disable its pool |

### Drain detected on a pool — stop that pool

| Step | Contract | Call |
|------|----------|------|
| 1 | PayoutManager | `setPoolEnabled(poolType, false)` |
| 2 | Token | `setPayoutsPaused(true)` (if cross-pool) |

### Compromised engine key — rotate immediately

| Step | Contract | Call |
|------|----------|------|
| 1 | Token | `setEnginePaused(true)` — block the old engine |
| 2 | Token | `proposeEngine(newAddr)` → new engine calls `acceptEngine()` |
| 3 | PayoutManager | `proposeEngine(newAddr)` → new engine calls `acceptEngine()` |
| 4 | GameRouter | `proposeEngine(newAddr)` → new engine calls `acceptEngine()` |
| 5 | Token | `setEnginePaused(false)` — resume with new engine |

### Recover funds from reserve

| Step | Contract | Call |
|------|----------|------|
| 1 | PayoutManager | `emergencyWithdraw(safeWallet, amount)` |

---

## 18. System Health Check

Run these daily (or on-demand) to verify the system is operating normally.

### Token State

```solidity
token.engine()                // current engine address
token.enginePaused()          // should be false
token.payoutsPaused()         // should be false
token.emergencyMode()         // should be false
token.feesEnabled()           // should be true (unless maintenance)
token.maxPayoutPerTx()        // current per-tx cap
token.dailyPayoutLimit()      // current daily cap (0 = disabled)
token.dailyPayoutUsed()       // tokens paid out today
token.lastPayoutDay()         // epoch day of last payout
token.opsWallet()             // current OPS wallet
token.pendingEngine()         // should be address(0) unless rotation in progress
token.pendingOpsWallet()      // should be address(0) unless rotation in progress
```

### PayoutManager State

```solidity
payoutManager.engine()                    // current engine address
payoutManager.pendingEngine()             // should be address(0)
payoutManager.globalPaused()              // should be false
payoutManager.maxRecipientsPerTx()        // current batch limit
payoutManager.maxPoolBalance()            // current cap (0 = disabled)
payoutManager.dailyPayoutTotal()          // tokens paid out today
payoutManager.lastDailyReset()            // timestamp of last daily reset

// Per-pool checks (repeat for JACKPOT, BANKROLL, RESERVE)
payoutManager.getPoolBalance(PoolType.LOTTERY)
payoutManager.poolConfig(PoolType.LOTTERY)     // wallet, limits, enabled, initialized
payoutManager.getPoolUsage(PoolType.LOTTERY)   // block/minute usage, cooldown
```

### GameRouter State

```solidity
gameRouter.engine()           // current engine address
gameRouter.pendingEngine()    // should be address(0)
gameRouter.game(gameId)       // check registered game addresses
```

### Quick Sanity Checks

| Check | Expected | Action if Wrong |
|-------|----------|-----------------|
| `enginePaused == false` | Normal operation | Call `setEnginePaused(false)` |
| `globalPaused == false` | Normal operation | Call `setGlobalPaused(false)` |
| `emergencyMode == false` | Normal operation | Call `setEmergencyMode(false)` |
| Pool balance > 0 | Pools are funded | Top up pool wallets |
| `dailyPayoutUsed < dailyPayoutLimit` | Under daily cap | Wait for reset or raise limit |
| `pendingEngine == address(0)` | No rotation pending | Complete or cancel rotation |

---

## 19. Pre-Deployment Checklist

Complete all steps before going live on mainnet.

### Token

- [ ] Deploy with correct `initialOwner` and `opsWallet`
- [ ] Verify `engine` is set to the correct address
- [ ] Set `maxPayoutPerTx` to desired value
- [ ] Set `dailyPayoutLimit` to desired value
- [ ] Call `setLP()` for the DEX pair address
- [ ] Confirm `feesEnabled == true`
- [ ] Confirm `enginePaused == false`
- [ ] Confirm `payoutsPaused == false`
- [ ] Confirm `emergencyMode == false`
- [ ] Transfer tokens to all system wallets
- [ ] Transfer tokens to all reserve wallets

### PayoutManager

- [ ] Deploy with correct `initialOwner`, `engine`, and `token` address
- [ ] Call `setPoolWallet()` for each pool type (LOTTERY, JACKPOT, BANKROLL, RESERVE)
- [ ] Call `setPoolConfig()` for each pool type with appropriate limits
- [ ] Call `setPoolEnabled(poolType, true)` for each pool
- [ ] Verify `globalPaused == false`
- [ ] Set `maxPoolBalance` if desired (or leave at 0 to disable)

### GameRouter

- [ ] Deploy with correct `initialOwner` and `engine`
- [ ] Register all game contracts via `setGame()`
- [ ] Verify engine address matches Token and PayoutManager

### Integration Tests (Testnet)

- [ ] Execute a single `payout()` — confirm tokens arrive
- [ ] Execute a `batchPayout()` — confirm all recipients receive tokens
- [ ] Call `setPayoutsPaused(true)` — confirm payouts revert
- [ ] Call `setPayoutsPaused(false)` — confirm payouts resume
- [ ] Call `setGlobalPaused(true)` — confirm PayoutManager payouts revert
- [ ] Call `emergencyWithdraw()` — confirm reserve tokens are recovered
- [ ] Test `proposeEngine()` → `acceptEngine()` — confirm engine rotates
- [ ] Test `proposeOpsWallet()` → `acceptOpsWallet()` — confirm OPS rotates
- [ ] Call `removeGame(gameId)` — confirm `execute()` reverts for that game
- [ ] Verify events are emitted for all operations

---

## 20. Post-Incident Recovery

After stopping the system (Section 17), follow this procedure to safely resume operations.

### Step-by-Step Recovery

| Step | Action | Details |
|------|--------|---------|
| 1 | **Identify root cause** | Review transaction logs, events, and off-chain engine logs |
| 2 | **Fix the issue** | Rotate compromised key, patch game contract, or adjust limits |
| 3 | **Verify fix on testnet** | If a game contract was replaced, test on fork or testnet first |
| 4 | **Re-enable pools** | `setPoolEnabled(poolType, true)` — one pool at a time |
| 5 | **Resume PayoutManager** | `setGlobalPaused(false)` |
| 6 | **Resume engine payouts** | `setEnginePaused(false)` and/or `setPayoutsPaused(false)` |
| 7 | **Disable emergency mode** | `setEmergencyMode(false)` — user transfers resume |
| 8 | **Monitor** | Watch `Payout` events, pool balances, and daily usage for 1 hour |

### Recovery Order Matters

Resume in this order to avoid premature exposure:

1. Fix the root cause first — never resume without understanding what happened
2. Re-enable pools before un-pausing the engine — so limits are active when payouts start
3. Disable emergency mode last — user trading should resume only after engine payouts are confirmed working
4. Monitor daily payout totals — a spike after recovery may indicate queued requests flooding in

### Post-Recovery Checklist

- [ ] Root cause documented
- [ ] Compromised keys rotated (if applicable)
- [ ] Pool balances verified (no unexpected drain)
- [ ] All pools re-enabled
- [ ] Engine un-paused
- [ ] Emergency mode off
- [ ] First payout executed successfully
- [ ] Monitoring confirmed normal for 1 hour

---

## 21. Safe Defaults

Recommended starting values for production. Adjust based on pool size and game volume.

### Token Limits

| Parameter | Recommended Default | Notes |
|-----------|-------------------|-------|
| `maxPayoutPerTx` | 100,000 tokens (`100000e18`) | Prevents single large drain |
| `dailyPayoutLimit` | 5,000,000 tokens (`5000000e18`) | Caps total daily outflow |

### PayoutManager — Per-Pool Configuration

| Parameter | Recommended | Notes |
|-----------|-------------|-------|
| `payoutLimitPerBlock` | 50,000 tokens (`50000e18`) | Max tokens movable in one block |
| `payoutLimitPerMinute` | 200,000 tokens (`200000e18`) | Rate limit per minute |
| `cooldownSeconds` | `30` | 30 seconds between payouts per pool |
| `maxValuePerMinuteBps` | `500` (5%) | Max 5% of pool balance per minute |
| `maxSinglePayoutBps` | `1000` (10%) | Max 10% of pool balance per payout |
| `minReserveBps` | `2000` (20%) | At least 20% must remain in pool |
| `drainsOnPayout` | `false` | Only set `true` for pools that should drain (e.g. jackpot) |
| `maxRecipientsPerTx` | `200` | Batch size cap (gas safety) |

### Example setPoolConfig Call

```solidity
setPoolConfig(
    PoolType.LOTTERY,
    50000e18,       // payoutLimitPerBlock
    200000e18,      // payoutLimitPerMinute
    30,             // cooldownSeconds
    500,            // maxValuePerMinuteBps (5%)
    1000,           // maxSinglePayoutBps (10%)
    2000,           // minReserveBps (20%)
    false           // drainsOnPayout
)
```

### Pool-Specific Overrides

| Pool | drainsOnPayout | minReserveBps | Notes |
|------|---------------|---------------|-------|
| LOTTERY | `false` | `2000` (20%) | Steady payouts, preserve pool |
| JACKPOT | `true` | `0` | Can drain on big win |
| BANKROLL | `false` | `3000` (30%) | Higher reserve for house edge |
| RESERVE | `false` | `5000` (50%) | Emergency fund — protect aggressively |

---

## Contract Summary

| Contract | Key Controls | Owner Functions | Engine Functions |
|----------|-------------|-----------------|------------------|
| **BUBBAS Token** | Payouts, fees, transfers, engine, OPS wallet | 10 setter functions | `systemPayout()` |
| **PayoutManager** | Per-pool limits, batch payouts, daily caps | 5 setter functions + emergency withdraw | `payout()`, `batchPayout()`, pool config |
| **GameRouter** | Game registry, execution dispatch | `setGame`, `removeGame`, engine rotation | `execute()` |
