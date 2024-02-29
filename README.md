```markdown
# AlfaTrust Smart Contract

## Overview
AlfaTrust is a smart contract developed for the Ethereum blockchain, designed to facilitate secure
and trustable transactions between parties. It utilizes ERC20 tokens (USDT and USDC) and incorporates
features such as deal creation, arbitration, and refunds, ensuring a high level of trust and transparency
for peer-to-peer financial agreements.

## Features
- **Secure Transactions**: Utilizes OpenZeppelin's ReentrancyGuard and SafeERC20 for secure token transfers.
- **Arbitration Support**: Incorporates an arbitration mechanism for dispute resolution.
- **Refund Mechanism**: Provides a structured refund process, enhancing trust between parties.
- **Immutable Settings**: Utilizes immutable variables for critical contract settings such as token addresses and arbiter identity.

## Prerequisites
- Solidity ^0.8.24
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)

## Installation
To use AlfaTrust in your project, first install the OpenZeppelin contracts via npm:

npm install @openzeppelin/contracts
```
## Quick Start
To deploy AlfaTrust, you need the addresses of USDT and USDC tokens on your network, and an address for the arbiter. Deploy it using your favorite development framework like Truffle or Hardhat.

```javascript
import "./AlfaTrust.sol";
const AlfaTrust = artifacts.require("AlfaTrust");

module.exports = function(deployer) {
    const usdtAddress = '...'; // USDT Token address
    const usdcAddress = '...'; // USDC Token address
    const arbiterAddress = '...'; // Arbiter's address

    deployer.deploy(AlfaTrust, usdtAddress, usdcAddress, arbiterAddress);
};
```

## Usage
### Approve Token Transfer
First, you need to approve the AlfaTrust contract to handle your tokens. This can be done through a direct interaction with the USDT or USDC token contract using a web3 provider (like MetaMask, ethers.js, or web3.js).

### Creating a Deal
To create a new deal, call the `createDeal` function with the token type, seller's address, and amount:

```solidity
contract.createDeal(AlfaTrust.Token.usdt, sellerAddress, amount);
```

### Completing a Deal
Once a deal is created and both parties are satisfied, the buyer can complete the deal, releasing funds to the seller and the arbiter's fee:

```solidity
contract.completeDeal(dealId);
```

### Handling Disputes and Refunds
In case of a dispute, the arbiter can approve refunds to either the buyer or the seller. Once approved, the corresponding party can claim their refund:

```solidity
// Arbiter approves refund to buyer
contract.approveRefundForBuyer(dealId);

// Buyer claims the refund
contract.refund(dealId);
```

## License
This project is proprietary and confidential. Unauthorized use, modification, or distribution is strictly prohibited.

## Contact
For any inquiries, please contact [contact@alfabuy.org](mailto:contact@alfabuy.org).
