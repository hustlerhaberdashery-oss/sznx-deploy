/**
 * Deploy SZNX V2 — Soldier-owned, Router V2 + Pool burn-exempt at genesis
 * Run: npx hardhat run scripts/deploy_sznx_v2.js --network cronos
 */
import hre from "hardhat";

const ROUTER_V2 = "0xa803a8F43fCceaA37f4AC064aa8FE42e1a7af778";
const MOCK_USDC = "0x4AffE1628fB8AF85d51f5eea8b4E3Ba8C806b5Bd";
const SOLDIER   = "0xea473685526A83dc1Ab3C82A812AE8429F56eF1c";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("\n══════════════════════════════════════════════════");
  console.log("  SZNX V2 + SZNPool V2 — SOVEREIGN RELAUNCH");
  console.log("══════════════════════════════════════════════════");
  console.log("  Deployer :", deployer.address);

  // 1. Deploy SZNX V2
  console.log("\n  1. Deploying SZNToken V2...");
  const SZNToken = await hre.ethers.getContractFactory("SZNToken");
  const sznx = await SZNToken.deploy();
  await sznx.waitForDeployment();
  const sznxAddr = await sznx.getAddress();
  console.log("     SZNX V2 :", sznxAddr);

  // 2. Set burn-exempt immediately (Soldier owns)
  console.log("\n  2. Setting burn-exempt...");
  await (await sznx.setBurnExempt(ROUTER_V2, true)).wait(2);
  console.log("     ✓ Router V2 exempt");

  // 3. Deploy new SZNPool (SZNX V2 / MockUSDC)
  console.log("\n  3. Deploying SZNPool V2 (SZNX V2 / MockUSDC)...");
  const SZNPool = await hre.ethers.getContractFactory("SZNPool");
  const pool = await SZNPool.deploy(sznxAddr, MOCK_USDC);
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("     Pool V2 :", poolAddr);

  // 4. Set pool burn-exempt
  await (await sznx.setBurnExempt(poolAddr, true)).wait(2);
  console.log("     ✓ Pool V2 exempt");

  // 5. Authorize Router V2 on new pool
  await (await pool.authorizeRouter(ROUTER_V2)).wait(2);
  console.log("     ✓ Router V2 authorized on Pool V2");

  // 6. Seed pool — 100 SZNX + 100 MockUSDC (deeper liquidity, less impact on $1 trades)
  console.log("\n  4. Seeding pool — 100 SZNX + 100 USDC...");
  const SEED_SZNX = hre.ethers.parseUnits("100", 18);
  const SEED_USDC = hre.ethers.parseUnits("100", 6);

  const usdcAbi = ["function approve(address,uint256) returns (bool)", "function allowance(address,address) view returns (uint256)"];
  const usdc = new hre.ethers.Contract(MOCK_USDC, usdcAbi, deployer);

  await (await sznx.approve(poolAddr, hre.ethers.MaxUint256)).wait(2);
  await (await usdc.approve(poolAddr, hre.ethers.MaxUint256)).wait(2);
  const seedTx = await pool.addLiquidity(SEED_SZNX, SEED_USDC, 0, 0, false, { gasLimit: 500_000 });
  await seedTx.wait(2);

  const spot = await pool.spotPrice();
  console.log("     ✓ Seeded — spot:", hre.ethers.formatUnits(spot, 6), "USDC/SZNX");

  // 7. Update SZNRouter V2 to point to new pool
  console.log("\n  5. Wiring Router V2 → Pool V2...");
  const routerAbi = ["function setPool(address) external", "function pool() view returns (address)"];
  const router = new hre.ethers.Contract(ROUTER_V2, routerAbi, deployer);
  await (await router.setPool(poolAddr)).wait(2);
  console.log("     ✓ Router V2 pool updated");

  console.log("\n══════════════════════════════════════════════════");
  console.log("  COMPLETE — UPDATE config.js WITH THESE:");
  console.log("══════════════════════════════════════════════════");
  console.log("  SZNX_CONTRACTS.TOKEN  :", sznxAddr);
  console.log("  SZNX_CONTRACTS.POOL   :", poolAddr);
  console.log("  SZNX_CONTRACTS.ROUTER : 0xa803a8F43fCceaA37f4AC064aa8FE42e1a7af778 (unchanged)");
  console.log("  Spot price            : $1.00/SZNX");
  console.log("  Burn-exempt           : Router ✓ | Pool ✓");
  console.log("══════════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
