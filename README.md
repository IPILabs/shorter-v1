<img width="179px" height="59px" align="right" alt="Shorter Logo" src="https://raw.githubusercontent.com/IPILabs/shorter-v1/master/assets/shorter-logo.png" title="Shorter Logo"/>

# Shorter Finance v1

Shorter Finance is a truly 100% decentralized infrastructure from IPI Labs. It comprises venues for token lending, derivatives trading and foolproof liquidation, bringing margin trading and physical delivery to the DeFi landscape with the ethos of open-source.

Some of Shorter’s prominent features:

- Full-fledged token pools
- Direct lending pattern
- Flexible position holding duration
- Constant liquidity driven by AMM
- Protect traders away from dramatic spikes
- Physical delivery of cross-chain assets
- Transparent position lifecycle management
- Negative trading slippage reduction
- Autonomous on-chain debt collection and liquidation

Refer to [docs.shorter.finance](https://docs.shorter.finance) to learn more exhaustive details.

For higher level integration, check this repo: [shorter-v1-periphery](https://github.com/IPILabs/shorter-v1-periphery).

## Shorter’s Core Contracts

- ShorterBone
- PoolGuardian
- Committee
- IPISTR Token
- Pool
  - PoolGarner
  - PoolScatter
- Trading Hub
- Auction Hall
  - Tanto
  - Katana
- Vault
  - Naginata
- DexCenter
- Farming
  - Pool Rewards
  - Governance Rewards
  - Trading Rewards
  - Voting Rewards
- Treasury

### Prerequisites

Before running any command, you can run a single command to resolve all dependency issues:

```bash
$ yarn
```

## Build

```bash
$ yarn build
```

## Test

Run all the tests:

```bash
$ yarn test
```

### Clean

Delete the smart contract artifacts, the coverage reports and the Hardhat cache:

```bash
$ yarn clean
```
