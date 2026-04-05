# 🔐 PrivateFund — FHE Private Payroll Protocol

> Built on **Zama Protocol FHEVM v0.11** · Fully Homomorphic Encryption on-chain

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![FHEVM](https://img.shields.io/badge/FHEVM-v0.11-cyan)](https://docs.zama.org/protocol)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org)

---

## 📖 Overview

**PrivateFund** is a privacy-first payroll and fund management protocol for public blockchains. It leverages Zama's Fully Homomorphic Encryption (FHE) to ensure that **all financial amounts remain encrypted on-chain** — enabling compliance verification without ever revealing individual salary figures.

### The Problem

Public blockchains are transparent by default. Every salary payment, every balance, every transfer is visible to anyone. This prevents institutional adoption of on-chain payroll systems, as:

- Employees can see each other's salaries
- Competitors can analyze corporate spending
- Sensitive financial strategies are exposed

### The Solution

PrivateFund uses **FHEVM (Fully Homomorphic Encryption Virtual Machine)** to perform computations *directly on encrypted data*. Salaries are encrypted before leaving the client, stored as ciphertexts (`euint64`) on-chain, and never decrypted in the smart contract — only the authorized party can re-encrypt the result for their own viewing.

---

## 🏗 Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   PrivateFund System                      │
├────────────────┬───────────────────┬─────────────────────┤
│   CFO / Admin  │    Employee        │  Auditor/Regulator  │
│                │                    │                     │
│ Set budget cap │ View own balance   │ Verify compliance   │
│ Add employees  │ Request withdrawal │ Request decryption  │
│ Batch pay      │ View pay history   │ Audit trail         │
└────────────────┴───────────────────┴─────────────────────┘
                            │
              ┌─────────────▼─────────────┐
              │   PrivateFund.sol (FHEVM)  │
              │                            │
              │  euint64 balances[]        │  ← Encrypted
              │  euint64 totalPaid         │  ← Encrypted
              │  euint64 budgetCap         │  ← Encrypted
              │                            │
              │  FHE.add()                 │  ← FHE arithmetic
              │  FHE.select()              │  ← FHE branching
              │  FHE.le()                  │  ← FHE comparison
              │  FHE.sealoutput()          │  ← Re-encryption
              │                            │
              │  ACL: per-address access   │  ← Permission layer
              └────────────────────────────┘
                            │
              ┌─────────────▼─────────────┐
              │     Zama Gateway           │
              │   (Decryption Oracle)      │
              └────────────────────────────┘
```

---

## ✨ Key Features

### 1. Encrypted Salaries (`euint64`)
All salary amounts are stored as FHE ciphertexts. The smart contract adds, compares, and processes them without ever decrypting.

```solidity
// Salary addition — fully encrypted, no plaintext touched
encryptedBalances[employee] = FHE.add(
    encryptedBalances[employee], 
    amount  // euint64 ciphertext
);
```

### 2. Role-Based Access Control (ACL)
Each ciphertext carries fine-grained permissions:

| Ciphertext | CFO | Employee | Auditor | Regulator |
|---|---|---|---|---|
| `balance[alice]` | ✗ | Alice only | ✗ | ✓ (legal) |
| `balance[bob]` | ✗ | Bob only | ✗ | ✓ (legal) |
| `totalPaid` | ✓ | ✗ | ✓ | ✓ |
| `budgetCap` | ✓ | ✗ | ✓ | ✓ |
| `withinBudget` (bool) | ✓ | ✗ | ✓ | ✓ |

```solidity
FHE.allow(encryptedBalances[employee], employee);  // Employee only
FHE.allow(totalPaid, auditor);                     // Auditor can verify
FHE.allow(encryptedBalances[employee], regulator); // Legal access
```

### 3. Privacy-Preserving Compliance Check
The core innovation: auditors receive **only a boolean** — no amounts exposed.

```solidity
ebool withinBudget = FHE.le(encryptedTotalPaid, encryptedBudgetCap);
FHE.makePubliclyDecryptable(withinBudget); // Result is public, amounts are not
```

### 4. Branchless FHE Withdrawal (`FHE.select`)
Withdrawal logic that doesn't leak balance information:

```solidity
ebool hasSufficientFunds = FHE.ge(encryptedBalances[msg.sender], requestedAmount);

// No branch = no information leak
encryptedBalances[msg.sender] = FHE.select(
    hasSufficientFunds,
    FHE.sub(encryptedBalances[msg.sender], requestedAmount),
    encryptedBalances[msg.sender]  // unchanged if insufficient
);
```

### 5. MiCA Regulatory Compliance
Pre-authorized regulator access enables legal decryption without breaking user privacy for everyone else.

---

## 🗂 Project Structure

```
privatefund/
├── contracts/
│   └── PrivateFund.sol          # Core FHE smart contract
├── scripts/
│   └── deploy.js                # Deployment script
├── test/
│   └── PrivateFund.test.js      # Test suite
├── frontend/
│   └── index.html               # Single-file dApp (no framework needed)
├── hardhat.config.js
├── package.json
└── README.md
```

---

## 🚀 Quick Start

### Prerequisites

- Node.js >= 20
- MetaMask wallet
- Zama Protocol testnet account (get testnet tokens from faucet)

### 1. Install Dependencies

```bash
cd privatefund
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your keys:
# PRIVATE_KEY=0x...
# INFURA_KEY=...
# ETHERSCAN_API_KEY=...
```

### 3. Compile Contracts

```bash
npm run compile
```

### 4. Run Tests

```bash
npm test
```

### 5. Deploy to Sepolia Testnet

```bash
npm run deploy:sepolia
```

### 6. Launch Frontend

```bash
# Open frontend/index.html in browser, or serve locally:
npx serve frontend/
```

Update the contract address in `frontend/index.html` line ~450 after deployment.

---

## 🔬 How FHE Works in PrivateFund

### Encrypted Input Flow

```
Client Side:                    Contract Side:
──────────────                  ──────────────
1. CFO enters: 5000             Receives: encryptedInput (ciphertext)
2. SDK encrypts → 0xabc...      Calls: FHE.fromExternal(encInput, proof)
3. Sends ciphertext + proof     Returns: euint64 handle
                                 Executes: FHE.add(balance, amount)
```

### Re-encryption (Viewing Balance)

```
Employee requests balance:
1. Generates ephemeral keypair (pubKey, privKey)
2. Calls: getMyBalance(pubKey)
3. Contract: FHE.sealoutput(balance[me], pubKey) → sealed bytes
4. Employee: decrypt(sealed, privKey) → plaintext balance
5. Only employee's private key can decrypt — no one else
```

### Compliance Check

```
Auditor requests check:
1. Contract computes: FHE.le(totalPaid, budgetCap) → ebool handle
2. Gateway decrypts the boolean only
3. Auditor receives: true/false
4. Nobody sees: the actual amounts
```

---

## 🛡 Security Considerations

- **No admin backdoor**: Even the CFO cannot retrieve other employees' balances
- **Immutable ACL**: Once set, ACL permissions are enforced by the protocol
- **Proof verification**: All encrypted inputs require ZK proofs via FHEVM
- **Gateway security**: Decryption requests go through the Zama Gateway with threshold cryptography
- **MiCA readiness**: Regulatory decryption is pre-authorized, auditable, and limited in scope

---

## 📐 FHE Operations Used

| Operation | Usage | FHEVM Function |
|---|---|---|
| Addition | Salary accumulation | `FHE.add()` |
| Comparison | Compliance check | `FHE.le()`, `FHE.ge()` |
| Conditional | Withdrawal logic | `FHE.select()` |
| Re-encryption | Balance viewing | `FHE.sealoutput()` |
| Input handling | Encrypted payroll | `FHE.fromExternal()` |
| ACL permanent | Employee access | `FHE.allow()` |
| ACL public | Compliance result | `FHE.makePubliclyDecryptable()` |

---

## 🎯 Bounty Alignment

| Evaluation Criteria | How PrivateFund Addresses It |
|---|---|
| **Innovation** | Compliance verification without amount exposure — unique combination of FHE boolean result + ACL layering |
| **Compliance** | Explicit MiCA integration; regulator access pre-authorized with audit trail |
| **Real-world value** | Enterprise payroll is a $50B+ market with clear privacy needs |
| **Technical** | Uses 7 distinct FHEVM features correctly: add, le, ge, select, sealoutput, allow, makePubliclyDecryptable |
| **Product maturity** | 3 role panels, batch ops, withdrawal flow, compliance dashboard |
| **Usability** | Single-file frontend, no framework needed, clear documentation |

---

## 📹 Demo Video Script (2 min)

**[0:00–0:20]** Intro: "Blockchain is transparent. That means salaries are public. PrivateFund fixes this."

**[0:20–0:50]** CFO Panel: Show encrypting budget cap, adding employees, batch payroll submission. Highlight that amounts are encrypted before leaving the browser.

**[0:50–1:20]** Employee Panel: Click "Decrypt Balance" — show re-encryption in action. Only that employee's wallet can read the result.

**[1:20–1:45]** Auditor Panel: Run compliance check. Show that result is `true/false` only — exact amounts never revealed.

**[1:45–2:00]** Conclusion: "FHE makes privacy and compliance coexist on-chain. PrivateFund is production-ready today."

---

## 📄 License

MIT © 2025 PrivateFund Team

---

## 🔗 Resources

- [Zama Protocol Docs](https://docs.zama.org/protocol)
- [FHEVM Solidity Guide](https://docs.zama.org/protocol/solidity-guides)
- [Zama Discord](https://discord.com/invite/zama)
- [FHEVM GitHub](https://github.com/zama-ai/fhevm)
