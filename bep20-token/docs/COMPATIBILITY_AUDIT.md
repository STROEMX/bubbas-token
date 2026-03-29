# BUBBAS v1 → v2 Compatibility Audit Report

**Date:** 2026-03-29  
**Auditor:** GitHub Copilot  
**Scope:** Full functional compatibility audit between OLD (main branch, commit `e05f0b8`) and NEW (bubbas-v2, commit `091de46`) token contracts, plus backend integration analysis.

---

## 1. Function Signature Compatibility

### BubbasToken.sol — Shared Functions (identical signatures)

| Function | Selector | v1 | v2 | Compatible |
|----------|----------|----|----|------------|
| `totalSupply()` | `0x18160ddd` | ✅ | ✅ | ✅ |
| `balanceOf(address)` | `0x70a08231` | ✅ | ✅ | ✅ |
| `transfer(address,uint256)` | `0xa9059cbb` | ✅ | ✅ | ✅ |
| `approve(address,uint256)` | `0x095ea7b3` | ✅ | ✅ | ✅ (ERC20) |
| `transferFrom(address,address,uint256)` | `0x23b872dd` | ✅ | ✅ | ✅ (ERC20) |
| `allowance(address,address)` | `0xdd62ed3e` | ✅ | ✅ | ✅ (ERC20) |
| `name()` | `0x06fdde03` | ✅ | ✅ | ✅ |
| `symbol()` | `0x95d89b41` | ✅ | ✅ | ✅ |
| `decimals()` | `0x313ce567` | ✅ | ✅ | ✅ |
| `owner()` | `0x8da5cb5b` | ✅ | ✅ | ✅ |
| `proposeEngine(address)` | — | ✅ | ✅ | ✅ |
| `acceptEngine()` | — | ✅ | ✅ | ✅ |
| `setMaxPayoutPerTx(uint256)` | — | ✅ | ✅ | ✅ |
| `setEnginePaused(bool)` | — | ✅ | ✅ | ✅ |
| `setFeesEnabled(bool)` | — | ✅ | ✅ | ✅ |
| `setLP(address)` | — | ✅ | ✅ | ✅ |
| `systemPayout(address,address,uint256)` | — | ✅ | ✅ | ⚠️ See §5 |
| `constructor(address,address)` | — | ✅ | ✅ | ✅ |

### v2-Only Functions (NEW — not in v1)

| Function | Purpose | Breaking? |
|----------|---------|-----------|
| `setEmergencyMode(bool)` | Owner pauses all non-system transfers | No (additive) |
| `setDailyPayoutLimit(uint256)` | Sets daily payout cap | No (additive) |
| `setPayoutsPaused(bool)` | Pauses engine payouts | No (additive) |
| `proposeOpsWallet(address)` | 2-step OPS wallet rotation | No (additive) |
| `acceptOpsWallet()` | Completes OPS wallet rotation | No (additive) |
| `unsetLP(address)` | Removes LP exclusion | No (additive) |

### v1-Only Functions (REMOVED in v2)

| Function/Field | Purpose | Impact |
|----------------|---------|--------|
| `systemAlias(bytes32)` | Maps string keys to wallet addresses | **REMOVED** — backend never calls this |

### Storage Variable Changes

| Variable | v1 | v2 | Breaking? |
|----------|----|----|-----------|
| `OPS_WALLET` | `immutable` address | **Removed** | ⚠️ See §3 |
| `opsWallet` | — | `public` mutable address | Replacement for `OPS_WALLET` |
| `pendingOpsWallet` | — | `public` address | NEW |
| `emergencyMode` | — | `public bool` | NEW |
| `payoutsPaused` | — | `public bool` | NEW |
| `dailyPayoutLimit` | — | `public uint256` | NEW |
| `dailyPayoutUsed` | — | `public uint256` | NEW |
| `lastPayoutDay` | — | `public uint256` | NEW |
| `systemAlias` | `mapping(bytes32 => address)` | **Removed** | Non-breaking (unused by backend) |

---

## 2. ABI Compatibility

### Backend ABIs Used (files examined)

| File | ABI Used | Functions Called | v2 Compatible? |
|------|----------|-----------------|----------------|
| `abis/index.ts` — `ERC20_ABI` | Standard ERC20 | `transfer`, `balanceOf`, `decimals`, `symbol`, `allowance`, `Transfer` event | ✅ |
| `abis/index.ts` — `BUBBAS_ABI` | Minimal | `transfer(to,amount)`, `balanceOf(account)` | ✅ |
| `utils/contract.ts` — `tokenABI` | Full ERC20 (legacy) | `Approval`, `OwnershipTransferred`, `Transfer` events, `allowance`, `approve`, `balanceOf`, `decimals`, `decreaseAllowance`, `increaseAllowance`, `mint`, `name`, `owner`, `renounceOwnership`, `symbol`, `totalSupply`, `transfer`, `transferFrom`, `transferOwnership` | ⚠️ `mint`, `increaseAllowance`, `decreaseAllowance` do NOT exist on BUBBAS — but backend only uses `transfer`/`balanceOf` for BUBBAS interactions. Safe if these functions are never called on the BUBBAS contract address. |
| `deposit/event.service.ts` — `CONTRACT_ABI` | Standard ERC20 | `Transfer` event (watching), `balanceOf`, `approve`, `transfer` | ✅ |
| `deposit/event2.service.ts` — `ERC20_ABI` | Minimal | `Transfer` event, `balanceOf`, `decimals`, `transfer` | ✅ |
| `deposit/event.poll.ts` — `ERC20_ABI` | Minimal | `Transfer` event, `transfer` | ✅ |

**VERDICT:** All ABIs used by the backend to interact with the BUBBAS token call only standard ERC20 functions (`transfer`, `balanceOf`, `Transfer` event). These are **fully compatible** between v1 and v2.

---

## 3. OPS Wallet Address Change

### v1: `address public immutable OPS_WALLET`
### v2: `address public opsWallet` (mutable, 2-step rotation)

**Impact Analysis:**

The v1 contract exposed `OPS_WALLET` as a public immutable. The v2 contract exposes `opsWallet` as a public mutable.

- The **getter function name changes** from `OPS_WALLET()` to `opsWallet()`.
- No backend code calls `OPS_WALLET()` or `opsWallet()` on-chain. The OPS wallet address is configured via environment variables (`HOLDER_PUBLIC_KEY`, `PRIVATE_KEY`), not read from the contract.
- **Not a breaking change** for the current backend integration.

---

## 4. Event Compatibility

### Events in v1

| Event | Signature |
|-------|-----------|
| `Transfer(address indexed, address indexed, uint256)` | Standard ERC20 |
| `Approval(address indexed, address indexed, uint256)` | Standard ERC20 |
| `TaxApplied(address indexed from, uint256 amount, uint16 bps)` | Custom |
| `EngineUpdated(address indexed oldEngine, address indexed newEngine)` | Custom |
| `EngineProposed(address indexed oldEngine, address indexed newEngine)` | Custom |

### Events in v2 (superset of v1)

All v1 events are preserved. Additional events:

| Event | NEW in v2 |
|-------|-----------|
| `OpsWalletProposed(address indexed, address indexed)` | ✅ |
| `OpsWalletUpdated(address indexed, address indexed)` | ✅ |
| `EmergencyModeSet(bool)` | ✅ |
| `EnginePaused(bool)` | ✅ |
| `MaxPayoutUpdated(uint256)` | ✅ |
| `FeesEnabledSet(bool)` | ✅ |
| `DailyPayoutLimitUpdated(uint256)` | ✅ |
| `PayoutsPaused(bool)` | ✅ |
| `LPSet(address indexed)` | ✅ |
| `LPUnset(address indexed)` | ✅ |

**Backend event listening:** The backend watches only `Transfer` events (in `event.service.ts`, `event2.service.ts`, `event.poll.ts`, `native-event.service.ts`). The `Transfer` event signature is identical. **Fully compatible.**

---

## 5. systemPayout() Behavioral Changes

This is the **most critical** compatibility difference.

### v1 Implementation
```solidity
function systemPayout(address from, address to, uint256 amount)
    external onlyEngine engineActive
{
    require(amount <= maxPayoutPerTx, "Payout too large");
    require(isSystemWallet[from], "Not system");
    require(!isSystemWallet[to], "No system-to-system");

    uint256 rate = _getRate();
    uint256 rAmt = amount * rate;

    // ❌ BUG: Modifies _rTotal based on exclusion status (incorrect RFI accounting)
    if (isExcludedFromRewards[from] && !isExcludedFromRewards[to]) {
        _rTotal -= rAmt;
    }
    if (!isExcludedFromRewards[from] && isExcludedFromRewards[to]) {
        _rTotal += rAmt;
    }

    _rOwned[from] -= rAmt;
    if (isExcludedFromRewards[from]) _tOwned[from] -= amount;
    _rOwned[to] += rAmt;
    if (isExcludedFromRewards[to]) _tOwned[to] += amount;
}
```

### v2 Implementation
```solidity
function systemPayout(address from, address to, uint256 amount)
    external onlyEngine engineActive payoutsActive   // ← NEW modifier
{
    require(amount <= maxPayoutPerTx, "Payout too large");
    require(isSystemWallet[from], "Not system");
    require(!isSystemWallet[to], "No system-to-system");

    // ← NEW: daily payout cap
    uint256 today = block.timestamp / 1 days;
    if (today != lastPayoutDay) { lastPayoutDay = today; dailyPayoutUsed = 0; }
    if (dailyPayoutLimit > 0) {
        require(dailyPayoutUsed + amount <= dailyPayoutLimit, "Daily payout limit");
    }
    dailyPayoutUsed += amount;

    uint256 rate = _getRate();
    uint256 rAmt = amount * rate;

    // ✅ FIX: synchronize _rOwned before mutation (prevents stale rOwned)
    if (isExcludedFromRewards[from]) { _rOwned[from] = _tOwned[from] * rate; }
    if (isExcludedFromRewards[to])   { _rOwned[to] = _tOwned[to] * rate; }

    // ✅ FIX: No longer modifies _rTotal (was a bug in v1)
    _rOwned[from] -= rAmt;
    if (isExcludedFromRewards[from]) _tOwned[from] -= amount;
    _rOwned[to] += rAmt;
    if (isExcludedFromRewards[to]) _tOwned[to] += amount;
}
```

### Key Differences

| Aspect | v1 | v2 | Impact |
|--------|----|----|--------|
| `payoutsActive` modifier | ❌ | ✅ NEW | Payouts can be paused independently of engine. Backend engine must call when `payoutsPaused == false`. |
| Daily payout cap | ❌ | ✅ NEW | If `dailyPayoutLimit > 0`, payouts exceeding daily limit will **revert**. Must be configured or left at 0 (disabled). |
| `_rTotal` mutation | ❌ BUG (modified `_rTotal`) | ✅ FIXED (no `_rTotal` change) | **Correct behavior.** System wallets are excluded from rewards, so `_rTotal` should not change during system payouts. v2 is more accurate. |
| `_rOwned` sync | ❌ No sync | ✅ Pre-sync before mutation | Prevents stale `_rOwned` values that could cause accounting drift over time. |

**Backend impact:** The backend calls `systemPayout` via the admin wallet (engine). It does NOT call it directly from the backend — it uses `transfer()` for withdrawals. The PayoutManager contract calls `systemPayout` on behalf of the engine. As long as `payoutsPaused` is `false` and `dailyPayoutLimit` is `0` (or sufficiently high), all existing flows work unchanged.

---

## 6. _update() (Transfer Core) Changes

### v1
```solidity
function _update(address from, address to, uint256 amount) internal override {
    if (from == address(0)) return;
    require(to != address(0), "Burn disabled");
    require(from != SINK_WALLET, "Sink locked");
    require(!isSystemWallet[from], "System locked");  // ← BLOCKS all system wallets
    ...
}
```

### v2
```solidity
function _update(address from, address to, uint256 amount) internal override {
    if (from == address(0)) return;
    require(to != address(0), "Burn disabled");
    require(from != SINK_WALLET, "Sink locked");
    if (emergencyMode) {
        require(isSystemWallet[from] || from == engine, "Transfers paused");  // ← NEW
    }
    require(!isSystemWallet[from] || from == engine, "System locked");  // ← CHANGED
    ...
}
```

### Key Differences

| Aspect | v1 | v2 | Impact |
|--------|----|----|--------|
| System wallet transfers | All system wallets blocked from `transfer()` | Engine wallet can `transfer()` | Engine can now use standard `transfer()` in addition to `systemPayout()` |
| Emergency mode | ❌ | ✅ Only system/engine can transfer | Non-system users are blocked during emergency mode |

**Backend impact:** The backend uses `transfer()` from the admin/OPS wallet (not the engine wallet). Since the OPS wallet is not a system wallet, `transfer()` from OPS works identically in both versions. **Compatible**, unless `emergencyMode` is activated (which would block all non-system transfers including user withdrawals).

---

## 7. _tokenTransfer() & _takeSystemFee() Changes

### v1 `_tokenTransfer`
```solidity
// No _rOwned sync after _tOwned update
_rOwned[from] -= rAmount;
_rOwned[to]   += rTransfer;
if (isExcludedFromRewards[from]) { _tOwned[from] -= tAmount; }
if (isExcludedFromRewards[to])   { _tOwned[to] += tTransfer; }
```

### v2 `_tokenTransfer`
```solidity
// ✅ Balance check for excluded senders
if (isExcludedFromRewards[from]) {
    require(_tOwned[from] >= tAmount, "Not enough balance");
}

_rOwned[from] -= rAmount;
_rOwned[to]   += rTransfer;
if (isExcludedFromRewards[from]) { _tOwned[from] -= tAmount; }
if (isExcludedFromRewards[to])   { _tOwned[to] += tTransfer; }

// ✅ FIX: synchronize _rOwned after _tOwned update
if (isExcludedFromRewards[from]) { _rOwned[from] = _tOwned[from] * rate; }
if (isExcludedFromRewards[to])   { _rOwned[to] = _tOwned[to] * rate; }
```

### v1 `_takeSystemFee`
```solidity
function _takeSystemFee(address from, address to, uint256 tAmount) private {
    // ❌ Calls _getRate() again inside (extra gas, potential rate drift)
    uint256 rate = _getRate();
    ...
}
```

### v2 `_takeSystemFee`
```solidity
function _takeSystemFee(address from, address to, uint256 tAmount, uint256 rate) private {
    // ✅ Rate passed from caller (consistent, and saves gas)
    ...
}
```

**Impact:** These are internal improvements. The external API is unchanged. `transfer()` behaves the same for callers. v2 is more correct and gas-efficient.

---

## 8. _getRate() Changes

### v1
```solidity
function _getRate() private view returns (uint256) {
    return _rTotal / _tTotal;
}
```

### v2
```solidity
function _getCurrentSupply() private view returns (uint256 rSupply, uint256 tSupply) {
    rSupply = _rTotal;
    tSupply = _tTotal;
    for (uint256 i = 0; i < _excluded.length; i++) {
        if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) {
            return (_rTotal, _tTotal);
        }
        rSupply -= _rOwned[_excluded[i]];
        tSupply -= _tOwned[_excluded[i]];
    }
    if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
}

function _getRate() private view returns (uint256) {
    (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
    return rSupply / tSupply;
}
```

**Impact:** v2 uses the **standard RFI pattern** where excluded wallets are subtracted from supply before computing the rate. This means:

- Reflections are distributed only among **non-excluded** holders (correct RFI behavior).
- v1's simple `_rTotal / _tTotal` diluted reflections across excluded wallets too.
- `balanceOf()` for non-excluded holders will return **slightly different** values under v2 vs v1 for the same on-chain state, because the rate calculation differs.
- For backend purposes (which only reads `balanceOf()` and watches `Transfer` events), this is **transparent** — the contract handles it internally.

---

## 9. New Contracts: GameRouter & PayoutManager

### GameRouter.sol (entirely new)

| Function | Access | Purpose |
|----------|--------|---------|
| `setGame(bytes32,address)` | Owner | Register a game contract |
| `removeGame(bytes32)` | Owner | Deregister a game |
| `setEngine(address)` | Owner | Direct engine set |
| `proposeEngine(address)` | Owner | 2-step engine rotation |
| `acceptEngine()` | Pending engine | Accept proposal |
| `execute(bytes32,bytes)` | Engine only | Route game call |

**Backend impact:** The backend does NOT currently call GameRouter. No existing code references `GameRouter`, `setGame`, `removeGame`, or `execute`. This is a purely **additive** contract. Future game logic can be routed through it.

### PayoutManager.sol (entirely new)

| Function | Access | Purpose |
|----------|--------|---------|
| `proposeEngine(address)` | Owner | 2-step engine rotation |
| `acceptEngine()` | Pending engine | Accept proposal |
| `setGlobalPaused(bool)` | Owner | Global pause |
| `setMaxRecipientsPerTx(uint256)` | Owner | Batch limit |
| `setMaxPoolBalance(uint256)` | Owner | Pool balance cap |
| `setPoolWallet(PoolType,address)` | Engine | Link pool to wallet |
| `setPoolConfig(...)` | Engine | Configure pool limits |
| `setPoolEnabled(PoolType,bool)` | Engine | Enable/disable pool |
| `payout(PoolType,address,uint256)` | Engine | Single payout |
| `batchPayout(PoolType,address[],uint256[])` | Engine | Batch payout |
| `getPoolBalance(PoolType)` | View | Query pool balance |
| `getPoolUsage(PoolType)` | View | Query rate limit state |
| `emergencyWithdraw(address,uint256)` | Owner | Reserve-only emergency drain |

**Backend impact:** The backend does NOT currently call PayoutManager. All BUBBAS withdrawals go through `transfer()` from the admin wallet. PayoutManager is designed for **future** pool-based payout routing (lottery, jackpot, bankroll, reserve). **No integration needed for launch.**

---

## 10. Environment Configuration & Address Migration

### Token Address
The BUBBAS contract address (`BUBBA_TOKEN_ADDRESS`) is a **new deployment** — it will be a different address on mainnet.

**Files requiring update:**

| File | Variable | Current Value |
|------|----------|---------------|
| `backend/.env.development` | `BUBBA_TOKEN_ADDRESS` | `0x31db1C32Ea112e9E6d83C3fe8509e513754F06Fc` |
| `backend/.env.docker` | `BUBBA_TOKEN_ADDRESS` | `0x31db1C32Ea112e9E6d83C3fe8509e513754F06Fc` |
| `backend/.env.example` | `BUBBA_TOKEN_ADDRESS` | placeholder |
| `frontend/src/components/Footer.tsx` | Hardcoded links (×4) | `0x31db1C32...` (DexView + PancakeSwap) |

### New Addresses Needed

| Address | Purpose | Source |
|---------|---------|--------|
| BUBBAS token | Main token contract | New deployment |
| GameRouter | Game routing (optional at launch) | New deployment |
| PayoutManager | Pool payouts (optional at launch) | New deployment |

### Wallet Addresses (unchanged)

All system wallet constants (`ENGINE_WALLET`, `MARKETING_WALLET`, `DEV_WALLET`, `LOTTERY_WALLET`, `JACKPOT_WALLET`, `SINK_WALLET`) and all cold reserve wallet constants are **identical** between v1 and v2. No wallet migration needed.

### PancakeSwap LP Pair
The PancakeSwap pair address (`0xa6f779195e4326d709ce895cc9c41a45301522a2`) hardcoded in `coin-price.service.ts` is specific to the **old** token address. A new LP pair will need to be created for the new token address, and this constant updated.

---

## Summary: Risk Matrix

| Category | Risk Level | Description |
|----------|------------|-------------|
| ERC20 ABI | 🟢 NONE | `transfer`, `balanceOf`, `approve`, `Transfer` event — all identical |
| Deposit watching | 🟢 NONE | Backend watches `Transfer` events — unchanged |
| Withdrawal flow | 🟢 NONE | Backend calls `transfer()` via admin wallet — unchanged |
| Cold sweep | 🟢 NONE | Uses `transfer()` / `balanceOf()` — unchanged |
| `systemPayout()` | 🟡 LOW | New `payoutsActive` modifier + daily cap. Safe if `payoutsPaused=false` and `dailyPayoutLimit=0` |
| Emergency mode | 🟡 LOW | New — if activated, blocks non-system transfers (including user withdrawals) |
| OPS_WALLET getter | 🟢 NONE | Backend reads from env vars, not from contract |
| Rate calculation | 🟢 NONE | Internal change, transparent to callers |
| RFI accounting | 🟢 NONE | v2 is more correct; transparent to external callers |
| Token address migration | 🔴 REQUIRED | New deployment = new address in all env files + frontend links |
| PancakeSwap LP pair | 🔴 REQUIRED | New pair needed for price oracle in `coin-price.service.ts` |
| GameRouter | 🟢 NONE | Additive, no backend integration needed at launch |
| PayoutManager | 🟢 NONE | Additive, no backend integration needed at launch |
| `systemAlias` removal | 🟢 NONE | Never called by backend |

---

## Action Items Before Mainnet Deploy

1. **Deploy v2 contracts** to BSC mainnet (BUBBAS + GameRouter + PayoutManager)
2. **Update `BUBBA_TOKEN_ADDRESS`** in all backend `.env` files with the new mainnet address
3. **Update frontend** hardcoded token address in `Footer.tsx` (4 occurrences)
4. **Create new PancakeSwap LP pair** and update `PAIR_ADDRESS` in `coin-price.service.ts`
5. **Verify** `payoutsPaused` defaults to `false` and `dailyPayoutLimit` defaults to `0` after deployment
6. **Do NOT enable** `emergencyMode` unless intentionally blocking all user transfers
7. **Configure PayoutManager pools** (optional — not needed for initial launch)
8. **Register games in GameRouter** (optional — not needed for initial launch)
