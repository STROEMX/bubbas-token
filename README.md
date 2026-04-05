# BUBBAS Token ($BUBBAS)

> **Contract Version:** v2.0.0  
> **Last Updated:** 2026-03-25

This repository contains the smart contract system for Bubbas ($BUBBAS) — a GameFi settlement and enforcement layer on BSC.

The Bubbas ecosystem has been in continuous public operation since 2023, with the current contract system deployed in 2026 as its next-generation settlement, distribution, and game routing layer.

---

## Contract Architecture

The system consists of three contracts:

| Contract | Purpose |
|----------|---------|
| **BUBBAS** | ERC20 token with RFI reflections, fee distribution, and engine-controlled payouts |
| **PayoutManager** | Per-pool payout routing with rate limits, cooldowns, and safety caps |
| **GameRouter** | Modular game dispatch router with engine-only execution |

All contracts are non-upgradeable. Operational parameters are adjustable at runtime without redeployment.

---

## Core Principles

### Fixed Supply
Total supply is permanently capped at 1,000,000,000 tokens. No minting functions exist.

### Non-Custodial Design
Users always retain full control of their funds. No function allows confiscation, freezing, or forced removal of user balances.

### Open Source & Auditable
The full contract source is published and verifiable on-chain.

### No Hidden Backdoors
The contract contains no functions for arbitrary token creation, user blacklisting, or forced balance modification.

---

## Protocol Engine

BUBBAS integrates with a dedicated protocol engine that performs deterministic settlement and reward distribution.

The engine:

- Cannot mint tokens
- Cannot access liquidity pools
- Cannot withdraw user funds
- Can only execute bounded system payouts under predefined limits

All engine actions are transparent and visible on-chain.

### Engine Safety Controls

- **2-step rotation** — engine address changes require proposal + acceptance from the new address
- **Engine pause** — owner can instantly halt all engine payouts
- **Payouts pause** — independent toggle to stop payouts without affecting the engine itself
- **Max payout per tx** — configurable hard cap on any single payout (default: 1M tokens)
- **Daily payout limit** — configurable cap on total daily outflow
- **Emergency mode** — freezes all non-system transfers (nuclear option for critical incidents)

---

## Transaction Fees & Distribution

External transfers incur a dynamic fee based on transaction size (linear curve: 1% → 0.1%).

Collected fees are distributed as follows:

| Category     | Share |
|--------------|-------|
| Reflections  | 20%   |
| Sink / Burn  | 30%   |
| Marketing    | 10%   |
| Development  | 10%   |
| Lottery      | 18%   |
| Jackpot      | 12%   |

Internal platform operations and system wallets are excluded from fees.

Fees can be globally disabled and re-enabled by the owner.

---

## PayoutManager

The PayoutManager routes engine payouts through per-pool safety controls.

### Pool Types

| Pool | Purpose |
|------|---------|
| LOTTERY | Regular game rewards |
| JACKPOT | Large win payouts (can drain to zero) |
| BANKROLL | House edge / operational pool |
| RESERVE | Emergency fund (protected) |

### Per-Pool Controls

Each pool has independently configurable:

- **Per-block limit** — max tokens movable in a single block
- **Per-minute limit** — rate limit per minute (absolute and BPS-based)
- **Cooldown** — minimum seconds between payouts
- **Max single payout** — BPS cap relative to pool balance
- **Min reserve** — BPS floor that must remain after payout
- **Drain flag** — whether the pool can be fully emptied (e.g. jackpot wins)

### Batch Payouts

`batchPayout()` supports multiple recipients in a single transaction. All limits are validated against the batch total — batch payouts cannot bypass safety gates.

### Emergency Withdraw

Owner can withdraw from the RESERVE pool only, bypassing all limits. For emergency fund recovery.

---

## GameRouter

The GameRouter provides modular game dispatch for the hybrid GameFi architecture.

- **Game registration** — owner registers game contracts by ID
- **Game removal** — owner can deactivate any game instantly
- **Engine-only execution** — only the engine can call `execute()`
- **Reentrancy protection** — `nonReentrant` modifier on all execution
- **Calldata limit** — 4096 byte hard cap on execution data

---

## Administrative Controls

### Token (BUBBAS)

| Function | Access | Purpose |
|----------|--------|---------|
| `setMaxPayoutPerTx` | Owner | Adjust per-transaction payout cap |
| `setDailyPayoutLimit` | Owner | Adjust daily payout cap |
| `setEnginePaused` | Owner | Pause/resume engine |
| `setPayoutsPaused` | Owner | Pause/resume payouts |
| `setEmergencyMode` | Owner | Freeze all non-system transfers |
| `setFeesEnabled` | Owner | Enable/disable transaction fees |
| `proposeEngine` / `acceptEngine` | Owner + new engine | 2-step engine rotation |
| `proposeOpsWallet` / `acceptOpsWallet` | Owner + new wallet | 2-step OPS wallet rotation |
| `setLP` / `unsetLP` | Owner | Register/unregister LP pairs |

### PayoutManager

| Function | Access | Purpose |
|----------|--------|---------|
| `setGlobalPaused` | Owner | Pause all payouts across all pools |
| `setMaxRecipientsPerTx` | Owner | Adjust batch size limit |
| `setMaxPoolBalance` | Owner | Set post-payout balance cap |
| `proposeEngine` / `acceptEngine` | Owner + new engine | 2-step engine rotation |
| `setPoolWallet` | Engine | Set pool wallet address |
| `setPoolConfig` | Engine | Configure pool limits |
| `setPoolEnabled` | Engine | Enable/disable individual pools |
| `emergencyWithdraw` | Owner | Withdraw from RESERVE pool |

### GameRouter

| Function | Access | Purpose |
|----------|--------|---------|
| `setGame` | Owner | Register a game contract |
| `removeGame` | Owner | Deactivate a game contract |
| `setEngine` | Owner | Direct engine swap (emergency) |
| `proposeEngine` / `acceptEngine` | Owner + new engine | 2-step engine rotation |

These controls:

- Do not allow minting
- Do not allow balance confiscation
- Do not allow user blacklisting
- Do not allow unilateral fund extraction or supply modification

All administrative actions emit events and are publicly visible on-chain.

---

## 🛡️ Security & Risk Disclosure

Automated security scanners may flag this contract due to its controlled settlement architecture.

These flags reflect administrative capabilities required for protocol operation and do not indicate malicious behavior.

Key facts:

- Ownership has never been abused  
- No unauthorized fund movements  
- No hidden mint functions  
- No honeypot logic  

Users are encouraged to review the contract source and transaction history.

---

## 📜 History & Transparency

### Bubbas (Token Contract)

- Deployed: 2026  
- Fixed supply since deployment  
- No mint function  
- Open-source and verifiable  

### Project Legacy (Paco dApp)

- Originally launched: 2022  
- 3+ years of ecosystem development  
- No major security incidents  
- Continuous platform operation  

Bubbas represents the next-generation settlement layer built on the experience and operational history of Paco.

---

## ⚠️ Disclaimer

$BUBBAS is a utility token used within the Bubbas GameFi ecosystem. It is not an investment contract, yield product, or profit-sharing instrument.

Participation involves market risk. Users should conduct independent research.

---

## 📬 Contact & Verification

Official resources:

- Website: https://bubbas.fun  
- Telegram: https://t.me/Bubbaschat  

---

## 🛒 Where to Trade

$BUBBAS is available on the following platforms:

- Trading Interface: [Dexview (BSC)](https://www.dexview.com/bsc/0x31db1c32ea112e9e6d83c3fe8509e513754f06fc)
- DEX: [PancakeSwap (BSC)](https://pancakeswap.finance/swap?outputCurrency=0x31db1C32Ea112e9E6d83C3fe8509e513754F06Fc)
- Aggregator: [Dexscreener](https://dexscreener.com/bsc/0xa6f779195e4326d709ce895cc9c41a45301522a2)

---

Always verify contract addresses before trading.

## 🔍 Independent Verification

All contract functions, permissions, and historical transactions can be independently verified on-chain using public blockchain explorers and analytics platforms.

Detailed technical documentation is available at:  
https://bubbas-fun.gitbook.io/bubbas-docs/advanced-tokenomics-and-transparency
