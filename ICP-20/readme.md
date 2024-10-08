# ICP-style Token Smart Contract

This README provides an overview and usage guide for the ICP-style token smart contract implemented in Motoko for the Internet Computer Protocol (ICP).

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Deployment](#deployment)
5. [Usage](#usage)
6. [Functions](#functions)
7. [Important Notes](#important-notes)

## Overview

This smart contract implements a custom token on the Internet Computer, following practices similar to those used for ICP tokens. It provides basic functionality for token management, including minting, transferring, and approving token spending.

## Features

- Token minting with a maximum supply limit
- Token transfers between principals
- Approval mechanism for delegated transfers
- Ownership management
- Customizable token name and symbol

## Prerequisites

- [DFINITY Canister SDK](https://sdk.dfinity.org/)
- Basic knowledge of Motoko and ICP development

## Deployment

1. Clone the repository containing the smart contract.
2. Open a terminal and navigate to the project directory.
3. Deploy the canister to the Internet Computer:

```bash
dfx deploy
```

## Usage

After deployment, you can interact with the smart contract using the `dfx` command-line tool or by building a front-end application that communicates with the canister.

## Functions

### Owner-only Functions

- `transferOwnership(newOwner: Principal)`: Transfer contract ownership to a new principal.
- `setName(newName: Text)`: Set the token name.
- `setSymbol(newSymbol: Text)`: Set the token symbol.
- `mint(to: Principal, value: Nat)`: Mint new tokens to a specified principal.

### Public Functions

- `balanceOf(who: Principal)`: Get the token balance of a principal.
- `transfer(to: Principal, value: Nat)`: Transfer tokens to another principal.
- `approve(spender: Principal, value: Nat)`: Approve a principal to spend a certain amount of tokens.
- `transferFrom(from: Principal, to: Principal, value: Nat)`: Transfer tokens on behalf of another principal.

### Query Functions

- `getName()`: Get the token name.
- `getSymbol()`: Get the token symbol.
- `getTotalSupply()`: Get the total supply of tokens.
- `getMaxSupply()`: Get the maximum supply of tokens.
- `getOwner()`: Get the current owner of the contract.

## Important Notes

1. **Token Precision**: This contract uses 8 implicit decimal places, similar to ICP. 1 whole token is represented as 100,000,000 units.

2. **Maximum Supply**: The maximum supply is set to 10 million tokens (10,000,000,00000000 units).

3. **Owner Principal**: Before deployment, replace the placeholder owner principal in the contract with the actual principal of the contract owner:

```motoko
private stable var owner : Principal = Principal.fromText("aaaaa-aa"); // Replace with actual owner principal
```

4. **Security**: This contract provides basic functionality but may need additional security measures for production use. Always conduct a thorough security audit before deploying to mainnet.

5. **Gas Fees**: Unlike Ethereum, ICP doesn't use gas fees in the same way. However, be aware of cycle costs for various operations when interacting with the contract.

6. **Upgrades**: Consider implementing upgrade functionality if you plan to modify the contract after deployment.

For more detailed information about developing on the Internet Computer, refer to the [DFINITY documentation](https://sdk.dfinity.org/docs/index.html).
