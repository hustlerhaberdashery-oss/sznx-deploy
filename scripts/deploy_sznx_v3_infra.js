/**
 * Deploy SZNPool V3 + SZNRouter V3 — wired to the externally-deployed SZNX V3
 * token (0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e), the one being submitted
 * for VVS Finance whitelisting. This does NOT deploy a new token — V3 already
 * exists on-chain (owner 0x3c86d185..., not Soldier, deployed outside this repo).
 *
 * This script ONLY deploys infra (Pool + Router) and authorizes the router on
 * the pool. It does not seed liquidity — SZNX V3 currently has 0 total supply
 * on-chain, so there is nothing to seed with yet. Run seed_sznx_v3_pool.js
 * AFTER the V3 owner wallet has minted supply and sent some to the deployer
 * wallet used here (SOLDIER, same as V2).
 *
 * Run: npx hardhat run scripts/deploy_sznx_v3_infra.js --network cronos
 *
 * Required env (szn-deploy/.env):
 *   DEPLOYER_PRIVATE_KEY  — Soldier's working key (same one that deployed V2)
 *   SZN_REGISTRY          — unchanged member registry (0x794835e7...)
 *   USDT_ADDRESS           — MockUSDC (0x4AffE1628fB8AF85d51f5eea8b4E3Ba8C806b5Bd),
 *                            Soldier-owned & freely mintable — zero real-fund risk
 *   USDC_ADDRESS           — real Cronos USDC (0xc21223...), "stable bridge" slot only
 */
import hre from "hardhat";

const SZNX_V3 = "0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e";

async function main() {
  const REGISTRY = process.env.SZN_REGISTRY;
  const USDT_ADDR = process.env.USDT_ADDRESS; // MockUSDC
  const USDC_ADDR = process.env.USDC_ADDRESS; // real Cronos USDC

  if (!REGISTRY || !USDT_ADDR || !USDC_ADDR) {
    throw new Error("SZN_REGISTRY, USDT_ADDRESS, USDC_ADDRESS must be set in .env");
  }

  const [deployer] = await hre.ethers.getSigners();
  console.log("\n══════════════════════════════════════════════════");
  console.log("  SZNX V3 — POOL + ROUTER INFRA DEPLOY");
  console.log("══════════════════════════════════════════════════");
  console.log("  Deployer :", deployer.address);
  console.log("  SZNX V3  :", SZNX_V3, "(external token, not deployed here)");

  // Sanity: confirm this really is the V3 token before spending gas on it.
  const erc20 = await hre.ethers.getContractAt(
    ["function symbol() view returns (string)", "function totalSupply() view returns (uint256)"],
    SZNX_V3
  );
  const sym = await erc20.symbol();
  const supply = await erc20.totalSupply();
  console.log("  on-chain symbol:", sym, "| totalSupply:", hre.ethers.formatUnits(supply, 18));
  if (sym !== "SZNX") throw new Error(`Expected symbol SZNX, got ${sym} — wrong address?`);

  // 1. Deploy SZNPool(SZNX V3, MockUSDC)
  console.log("\n  [1/3] Deploying SZNPool V3 (SZNX V3 / MockUSDC)...");
  const SZNPool = await hre.ethers.getContractFactory("SZNPool");
  const pool = await SZNPool.deploy(SZNX_V3, USDT_ADDR);
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("        ✓ SZNPool V3:", poolAddr);

  // 2. Deploy SZNRouter(SZNX V3, realUSDC, MockUSDC, Registry, Pool)
  console.log("\n  [2/3] Deploying SZNRouter V3...");
  const SZNRouter = await hre.ethers.getContractFactory("SZNRouter");
  const router = await SZNRouter.deploy(SZNX_V3, USDC_ADDR, USDT_ADDR, REGISTRY, poolAddr);
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("        ✓ SZNRouter V3:", routerAddr);

  // 3. Authorize router on pool
  console.log("\n  [3/3] Authorizing router on pool...");
  await (await pool.authorizeRouter(routerAddr)).wait(2);
  console.log("        ✓ Router authorized");

  console.log("\n══════════════════════════════════════════════════");
  console.log("  INFRA DEPLOYED — NOT YET SEEDED");
  console.log("══════════════════════════════════════════════════");
  console.log("  SZNX V3 Token  :", SZNX_V3);
  console.log("  SZNPool V3     :", poolAddr);
  console.log("  SZNRouter V3   :", routerAddr);
  console.log("\n  Next: V3 owner (0x3c86d185...) mints supply and sends some");
  console.log("  to", deployer.address, "(this deployer), then run:");
  console.log("  SZN_POOL=" + poolAddr, "SZN_ROUTER=" + routerAddr,
               "npx hardhat run scripts/seed_sznx_v3_pool.js --network cronos\n");
}

main().catch(e => { console.error(e); process.exit(1); });
