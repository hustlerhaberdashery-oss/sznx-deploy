# SZNX Deploy

Hardhat/Foundry deployment and liquidity-seeding scripts for the SZNX token on Cronos mainnet.

## ⚠️ Source/bytecode notice

`contracts/SZNToken.sol` in this repo is an **earlier/reference token design** —
it does not match the bytecode currently deployed at the live V3 address below.
It mints a fixed 1,000,000,000 supply entirely in its constructor with a 2%
transfer burn and no external `mint()` function.

The **actual deployed V3 token** was deployed externally (outside this repo)
and behaves differently, confirmed directly on-chain:
- Starting total supply: **0**
- Minted via an owner-gated `mint(address,uint256)` call to **1,000,000 SZNX**
  (tx `0xa2c955fb52f57f2f7f5921d8957ffc31ae34aa9823c73f64b9a15f9b6fb74a98`)
- No burn-on-transfer behavior observed in any on-chain transaction to date

`scripts/`, `script/`, `SZNPool.sol`, `SZNRouter.sol`, and `SZNRegistry.sol`
in this repo are the real infrastructure used to deploy the pool/router
wired to the live V3 token (see `scripts/deploy_sznx_v3_infra.js` and
`scripts/seed_sznx_v3_pool.js`) — only `SZNToken.sol` itself is the mismatched
reference file. The verified source for the live V3 token's exact deployed
bytecode has not yet been added to this repo.

## Contract

- **SZNX V3 Token:** `0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e`
- **Chain:** Cronos (chain ID 25)
- **SZNX/USDC.e Pair (VVS V2):** `0x41c3223D5ceA61f083fF033EF502c17A20E41Fc2`
- **Total Supply:** 1,000,000 SZNX (confirmed on-chain)

## Layout

- `contracts/` — Solidity source (`SZNToken`, `SZNPool`, `SZNRouter`, `SZNRegistry`, `IERC20`)
- `scripts/` — deployment and operational scripts (Hardhat, run with `npx hardhat run scripts/<name>.js --network cronos`)
- `script/` — Foundry scripts
- `src/` — interfaces
