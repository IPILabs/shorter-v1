<img width="179px" height="59px" align="right" alt="Shorter Logo" src="https://raw.githubusercontent.com/IPILabs/shorter-v1/master/assets/shorter-logo.png" title="Shorter Logo"/>

# Shorter Finance v1

Shorter Finance is a 100% on-chain auto-broker protocol from IPI Labs, bringing margin trading and physical delivery to the DeFi landscape with the ethos of open source.

Some of Shorter’s prominent features:

- Transparent single-sided token loaning & farming
- Customizable derivatives & margin trading
- Constant liquidity driven by AMM
- Visible position lifecycle management
- 100% on-chain liquidation & debt coverage
- Physical delivery of cross-platform assets
- Massive trading slippage reduction

Refer to [docs.shorter.finance](https://docs.shorter.finance) to learn more exhaustive details.

For higher level integration, check this repo: [shorter-v1-periphery](https://github.com/IPILabs/shorter-v1-periphery).

## Shorter’s Anatomy

- Pools: It initially paves the way for altcoin holders for unstable tokens’ deposits and profit. The controllable shift of these assets grants the trading capacities to this whole protocol.
- Trading Hub: The core ingredient serves users as a gateway over the logic between positions and underlying assets.
- Position: Managed by Trading Hub and Auction Hall. Its lifecycle shifts in obedience to the prescribed rigorous rules before.
- Auction Hall: A venue built on contractual logic supporting debt bidding and recovering activities.
- Committee: Similar to committees in real but even more decentralized.
- Farming: This can be of substantial assistance to help users care more about their earnings by interacting with smart contracts or getting involved in activities.
- strPool: The staking proof token distributed by pools, maintaining the pool-related data structures as well.
- Vault: It gives far more opportunities for arbitrage rulers to bid on Legacy assets through a set of open interfaces.
- Treasury: This is a catch-all for overall protocol revenue.

### Prerequisites

Before running any command, you can run a single command to resolve all dependency issues:

```bash
$ yarn
```

## Build & Compile

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
