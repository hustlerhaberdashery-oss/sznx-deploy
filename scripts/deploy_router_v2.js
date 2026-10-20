/**
 * Deploy SZNRouter V2 — Soldier-owned, wired to new SZNX/MockUSDC pool
 * Run: npx hardhat run scripts/deploy_router_v2.js --network cronos
 */
import hre from "hardhat";

async function main() {
  const SZNX      = process.env.SZN_TOKEN;     // 0x1d6C...
  const USDC_ADDR = process.env.USDT_ADDRESS;  // MockUSDC 0x4AffE...
  const POOL      = process.env.SZN_POOL;      // new pool 0x17e5...
  const REGISTRY  = process.env.SZN_REGISTRY;  // 0x7948...

  // Use real Cronos USDC as the USDC_ADDRESS param (for the "stable bridge" slot)
  const REAL_USDC = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59";

  if (!SZNX || !USDC_ADDR || !POOL || !REGISTRY) throw new Error("Missing env vars");

  const [deployer] = await hre.ethers.getSigners();
  console.log("\n═══════════════════════════════════════════════════");
  console.log("  SZNRouter V2 — SOVEREIGN TELLER REBOOT");
  console.log("═══════════════════════════════════════════════════");
  console.log("  Deployer :", deployer.address);
  console.log("  SZNX     :", SZNX);
  console.log("  MockUSDC :", USDC_ADDR, "(primary stable / USDT slot)");
  console.log("  Pool     :", POOL);
  console.log("  Registry :", REGISTRY);

  const SZNRouter = await hre.ethers.getContractFactory("SZNRouter");
  const router = await SZNRouter.deploy(SZNX, REAL_USDC, USDC_ADDR, REGISTRY, POOL);
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("\n  ✓ SZNRouter V2 :", routerAddr);

  // Also authorize the new router on the pool
  const poolAbi = ["function authorizeRouter(address) external"];
  const pool = new hre.ethers.Contract(POOL, poolAbi, deployer);
  console.log("  Authorizing new router on SZNPool...");
  await (await pool.authorizeRouter(routerAddr)).wait(2);
  console.log("  ✓ Router authorized on pool");

  console.log("\n═══════════════════════════════════════════════════");
  console.log("  SZNRouter V2 DEPLOYED + AUTHORIZED");
  console.log("═══════════════════════════════════════════════════");
  console.log("  SZNRouter V2 :", routerAddr);
  console.log("  Pool         :", POOL);
  console.log("  Cronoscan    : https://cronoscan.com/address/" + routerAddr);
  console.log("\n  UPDATE config.js SZNX_CONTRACTS.ROUTER →", routerAddr);
  console.log("  UPDATE AdmiralsBridge.jsx SZN_ROUTER    →", routerAddr, "\n");
}

main().catch(e => { console.error(e); process.exit(1); });
