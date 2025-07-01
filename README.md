# 🌐 NovaCoin (NOVA)

**NovaCoin** is a decentralized BEP-20 token deployed on the BNB Smart Chain, designed to fuel a growing ecosystem of DeFi utilities, community engagement, and fair distribution. Built for scalability and transparency, NovaCoin brings Web3 access to the masses.

---

## 🔗 Smart Contract

- **Name:** NovaCoin  
- **Symbol:** NOVA  
- **Decimals:** 18  
- **Total Supply:** 100,000,000 NOVA  
- **Contract Address:** [`0x2cB9DC3F6D12ECcA6Ea4d7621c70BFBCA46b5ee7`](https://bscscan.com/token/0x2cB9DC3F6D12ECcA6Ea4d7621c70BFBCA46b5ee7)  
- **Blockchain:** BNB Smart Chain (BEP-20)

---

## 🚀 Features

- ✅ **Verified Contract** on BscScan  
- 🪙 **Buyable via PancakeSwap**  
- 💸 **Low Fee Transactions**  
- 🔐 **Community-Led Project**  
- ⚙️ **ThirdWeb Integration Support**

---

## 📦 Integration Example (Thirdweb React)

```javascript
import { BuyWidget } from "thirdweb/react";

export default function App() {
  return (
    <BuyWidget
      clientId="afe7440e41b16785bc626219d5279930"
      chain="binance"
      tokenAddress="0x2cB9DC3F6D12ECcA6Ea4d7621c70BFBCA46b5ee7"
      recipient="YOUR_WALLET_ADDRESS"
      theme="light"
    />
  );
}
