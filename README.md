# Shorter Finance

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

## Shorter’s Core Contracts

- PoolGuardian (`Provider`)
- Committee
- Pool
- Trading Hub (`Trader`)
- Auction Hall (`Ruler`)
  - Tanto
  - Katana
- Vault
  - Naginata
- Farming
  - Pool Rewards
  - Governance Rewards
  - Trading Rewards
  - Voting Rewards

### Pre Requisites

Before running any command, make sure to install dependencies:

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