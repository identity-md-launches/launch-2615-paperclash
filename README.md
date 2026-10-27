# Paperclash (PAPER)

Powered by imd.

A fixed-supply ERC-20 token for an IMD custom token launch on Ethereum (chain id 1).

| Field              | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| Solidity contract  | `PaperclashToken` (`src/PaperclashToken.sol`)                |
| Token name         | Paperclash                                                   |
| Token symbol       | PAPER                                                        |
| Decimals           | 18                                                           |
| Total supply       | 1,000,000,000 PAPER = `1000000000000000000000000000` minor units |
| Minting            | Once, the whole supply, to `msg.sender` in the constructor   |
| Constructor args   | None                                                         |
| Owner / admin      | None                                                         |
| Compiler           | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |

## What it does

`PaperclashToken` is OpenZeppelin's `ERC20` (v5.4.0, vendored under `lib/`) with the name, symbol
and supply fixed as constants. The constructor mints the entire supply to the deployer and nothing
else. There is:

- no `mint`, `owner`, `Ownable`, pause, blacklist, freeze, burn-from, tax, fee, reflection or
  transfer hook of any kind;
- no upgrade path, no proxy, no `delegatecall`, no `selfdestruct`;
- no external call in the constructor, so it deploys on an empty chain.

Every `transfer` and `transferFrom` moves exactly the amount requested, so the launch flows (factory
to MerkleDistributor, factory into the Uniswap v4 pool, factory to the requester, distributor to a
claimant, trader to and from the PoolManager) all arrive whole. The supply can never grow after
deployment; it cannot shrink either, since no burn function is exposed (sending to a dead address
is a holder's own business and leaves `totalSupply` unchanged).

`transferFrom` moves tokens only from the `from` account within an allowance the account itself
granted; the deployer has no special pull right over anyone's balance.

## Launch parameters

These are the launch's, decided by IMD and the requester's quote, and are restated here so the
deployment is reviewable. They are not read by the contract.

| Parameter                      | Value                                                        |
| ------------------------------ | ------------------------------------------------------------ |
| Chain                          | Ethereum, chain id 1                                         |
| Deployer of the token          | IMD ProjectFactory via `launchCustom`; it is `msg.sender` in the constructor and so receives the whole supply |
| Paired currency                | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee / tick spacing        | 12500 (1.25%) / 60                                           |
| Pool share (`poolBps`)         | 8000 (80% of supply seeds the pool)                          |
| Opening market cap             | 5,000 IMD for the whole supply (`initialMarketCapWei` = `5000000000000000000000`) |
| Swarm share                    | 10%, forwarded by the factory to the launch's MerkleDistributor |
| Remainder (10%)                | `0xee2aaa315cf7ed169f93148d30d24af9318dbb66` (`economics.remainderTo`) |
| Application contracts          | None                                                         |

The manifest (`launch.json`) is written by the manifest step after this work is accepted. For the
token section it will need: `contract` = `PaperclashToken`, `name` = `Paperclash`, `symbol` = `PAPER`,
`decimals` = 18, `constructorArgs` = `[]`, `totalSupply` = `1000000000000000000000000000`.

## Assumptions

- The brief asks for a plain fixed-supply token. No transfer rule beyond standard ERC-20 was
  requested, so none was added. "Powered by imd" is treated as the token's description and is
  exposed as the `DESCRIPTION` constant.
- The deployer at launch is the IMD factory, which pays the supply out. The token itself does not
  know or care who deploys it; whoever does holds the supply (`test_contractDeployerThroughCreate2HoldsSupply`).
- No value only the requester holds is needed: the contract has no owner, no oracle, no external
  address. Nothing in this project is a placeholder.
- Decimals are the ERC-20 default of 18, restated as the `DECIMALS` constant for the manifest.

## After launch

Nothing to configure. The token has no owner-settable storage and no setters. The factory
distributes the supply as part of the launch transaction; afterwards the token behaves like any
other ERC-20.

## Operational responsibilities

- **Requester**: receives the 10% remainder at `economics.remainderTo` and is responsible for the
  key controlling that address. There is no admin key for the token itself to protect or rotate.
- **IMD deployer / launch policy**: performs the launch through the factory, seeds the pool, and
  handles explorer verification of the deployed bytecode. This repository does not deploy, broadcast
  or hold keys.
- **Nobody**: there is no pause, upgrade or recovery power. A bug found after launch cannot be
  patched in place; a replacement token would be a new launch. That is the trade-off of a token with
  no trusted party.

## Security notes

- Built on OpenZeppelin `ERC20` v5.4.0, unmodified, vendored as ordinary files under
  `lib/openzeppelin-contracts/` (MIT).
- Checked against the eth-security checklist: no reentrancy surface (no external calls, no ETH
  handling; the contract has no `receive`/`fallback` and rejects ETH), no arithmetic beyond
  OpenZeppelin's checked balance accounting, no access control to misconfigure, no proxies, no
  signatures, no oracles.
- Slither-sensitive patterns avoided: no `selfdestruct`, no `delegatecall`, no `abi.encodePacked`,
  no assembly, no library calls (public or otherwise), no initializers.
- The test suite scans the runtime bytecode for reachable `DELEGATECALL`, `CALLCODE` and
  `SELFDESTRUCT` opcodes the same way the launch floor does.
- Tools run locally: `forge build`, `forge test` (31 tests, including fuzz tests with the verifier's
  seed `FOUNDRY_FUZZ_SEED=0x7263e244d1e4e8b000d6dcfa1dc1cc23980d36893c814317dc27b704c483bfa4`), and
  `forge fmt --check`. Slither and Mythril were not available on this machine and were not run.
- Tests passing is not an audit. The token holds no user funds itself, but any application built on
  it should receive an independent adversarial review before release.

## Layout

```
foundry.toml                  compiler pins and remappings (solc 0.8.26, bytecode_hash = "none")
src/PaperclashToken.sol       the token
script/DeployPaperclash.s.sol reviewable reference deployment; deploy() is tested directly
test/PaperclashToken.t.sol    unit, failure-path, launch-flow, admin-surface and fuzz tests
lib/forge-std/                forge-std v1.11.0 (MIT / Apache-2.0), vendored
lib/openzeppelin-contracts/   OpenZeppelin Contracts v5.4.0, only the ERC20 files, vendored
```

## Running the checks

```
forge build
FOUNDRY_FUZZ_SEED=0x7263e244d1e4e8b000d6dcfa1dc1cc23980d36893c814317dc27b704c483bfa4 forge test
forge fmt --check
```

The reference deploy script can be rehearsed on a local chain with
`forge script script/DeployPaperclash.s.sol --rpc-url <local> --broadcast`; the broadcasting signer
receives the whole supply. The production launch does not use this script.
