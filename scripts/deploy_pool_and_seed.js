/**
 * SOVEREIGN POOL REBOOT + GENESIS SEED
 * Deploys a fresh SZNPool(SZNX, MockUSDC) then seeds 10 SZNX / 10 USDC.
 * Run: npx hardhat run scripts/deploy_pool_and_seed.js --network cronos
 */
import hre from "hardhat";

async function main() {
  const SZNX_ADDR = process.env.SZN_TOKEN;
  const USDT_ADDR = process.env.USDT_ADDRESS; // MockUSDC — 0x4AffE...

  if (!SZNX_ADDR || !USDT_ADDR) throw new Error("SZN_TOKEN and USDT_ADDRESS must be set");

  const [deployer] = await hre.ethers.getSigners();
  console.log("\n══════════════════════════════════════════════════════");
  console.log("  SOVEREIGN POOL REBOOT + GENESIS SEED");
  console.log("══════════════════════════════════════════════════════");
  console.log("  Deployer :", deployer.address);
  console.log("  SZNX     :", SZNX_ADDR);
  console.log("  MockUSDC :", USDT_ADDR);

  // ── 1. Deploy fresh SZNPool ──────────────────────────────────────────
  console.log("\n  [1/4] Deploying SZNPool(SZNX, MockUSDC)...");
  const SZNPool = await hre.ethers.getContractFactory("SZNPool");
  const pool = await SZNPool.deploy(SZNX_ADDR, USDT_ADDR);
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("        ✓ SZNPool:", poolAddr);

  // ── 2. Approve MaxUint256 for both tokens ───────────────────────────
  const MAX = hre.ethers.MaxUint256;
  const SZNX_SEED = hre.ethers.parseUnits("10", 18); // 10 SZNX
  const USDT_SEED = hre.ethers.parseUnits("10",  6); // 10 MockUSDC

  const sznx = await hre.ethers.getContractAt("SZNToken", SZNX_ADDR);
  const usdt = await hre.ethers.getContractAt("contracts/SZNPool.sol:IERC20", USDT_ADDR);

  console.log("  [2/4] Approving SZNX...");
  await (await sznx.approve(poolAddr, MAX)).wait();
  console.log("        ✓ SZNX approved");

  console.log("  [3/4] Approving MockUSDC...");
  await (await usdt.approve(poolAddr, MAX)).wait();
  console.log("        ✓ MockUSDC approved");

  // ── 3. GENESIS SEED ─────────────────────────────────────────────────
  console.log("  [4/4] GENESIS SEED — addLiquidity(10 SZNX, 10 USDC)...");
  const tx = await pool.addLiquidity(SZNX_SEED, USDT_SEED, 0, 0, false, { gasLimit: 500_000 });
  console.log("        Tx:", tx.hash);
  const receipt = await tx.wait(2);
  if (receipt.status !== 1) throw new Error("addLiquidity reverted");

  // ── 4. Verify ────────────────────────────────────────────────────────
  const resX  = await pool.reserveSZNX();
  const resU  = await pool.reserveUSDT();
  const spot  = await pool.spotPrice();
  const shares = await pool.totalShares();

  console.log("\n══════════════════════════════════════════════════════");
  console.log("  GENESIS SEED COMPLETE — YIELD TANK FULL");
  console.log("══════════════════════════════════════════════════════");
  console.log("  SZNPool      :", poolAddr);
  console.log("  Block        :", receipt.blockNumber);
  console.log("  reserveSZNX  :", hre.ethers.formatUnits(resX, 18), "SZNX");
  console.log("  reserveUSDC  :", hre.ethers.formatUnits(resU,  6), "USDC");
  console.log("  Spot Price   : $", hre.ethers.formatUnits(spot, 6), "/ SZNX");
  console.log("  LP Shares    :", hre.ethers.formatUnits(shares, 18));
  console.log("  Cronoscan    : https://cronoscan.com/address/" + poolAddr);
  console.log("  Seed Tx      : https://cronoscan.com/tx/" + tx.hash);
  console.log("\n  UPDATE config.js SZNX_CONTRACTS.POOL →", poolAddr, "\n");
}

main().catch(e => { console.error(e); process.exit(1); });
