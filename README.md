# BUBBAS Token ($BUBBAS)

This repository contains the canonical ERC20 token contract for Bubbas ($BUBBAS), designed as a long-term GameFi settlement and enforcement layer.

The Bubbas ecosystem has been in continuous public operation since 2023, with the current token contract deployed in 2026 as its next-generation settlement and distribution layer.

---

## 📌 Core Principles

### Fixed Supply
Total supply is permanently capped at 1,000,000,000 tokens. No minting functions exist.

### Non-Custodial Design
Users always retain full control of their funds. No function allows confiscation, freezing, or forced removal of user balances.

### Open Source & Auditable
The full contract source is published and verifiable on-chain.

### No Hidden Backdoors
The contract contains no functions for emergency drains, liquidity removal, or arbitrary token creation.

---

## ⚙️ Protocol Engine

BUBBAS integrates with a dedicated protocol engine that performs deterministic settlement and reward distribution.

The engine:

- Cannot mint tokens  
- Cannot access liquidity pools  
- Cannot withdraw user funds  
- Can only execute bounded system payouts under predefined limits  

All engine actions are transparent and visible on-chain.

---

## 💰 Transaction Fees & Distribution

External transfers may incur a dynamic transaction fee based on transaction size.

Collected fees are distributed as follows:

| Category     | Share |
|--------------|-------|
| Reflections  | 20%   |
| Sink / Burn  | 30%   |
| Marketing    | 10%   |
| Development  | 10%   |
| Lottery      | 18%   |
| Jackpot      | 12%   |

Internal platform operations are excluded from fees.

---

## 🔐 Administrative Controls

The contract includes limited administrative controls required for protocol operation:

- Engine rotation (two-step process)  
- Emergency engine pause  
- LP registration  
- Fee enable/disable  

These controls:

- Do not allow minting  
- Do not allow balance confiscation  
- Do not allow trading restrictions  
- Do not allow user blacklisting  

All administrative actions are publicly visible.

No administrative function allows unilateral fund extraction or supply modification.

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
