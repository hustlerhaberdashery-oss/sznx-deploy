# SZNX Deploy

Hardhat/Foundry deployment and liquidity-seeding scripts for the SZNX token on Cronos mainnet.

## Contract

- **SZNX V3 Token:** `0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e`
- **Chain:** Cronos (chain ID 25)
- **SZNX/USDC.e Pair (VVS V2):** `0x41c3223D5ceA61f083fF033EF502c17A20E41Fc2`

## Layout

- `contracts/` — Solidity source (`SZNToken`, `SZNPool`, `SZNRouter`, `SZNRegistry`, `IERC20`)
- `scripts/` — deployment and operational scripts (Hardhat, run with `npx hardhat run scripts/<name>.js --network cronos`)
- `script/` — Foundry scripts
- `src/` — interfaces
