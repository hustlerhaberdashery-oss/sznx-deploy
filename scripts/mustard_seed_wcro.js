/**
 * MUSTARD SEED PROTOCOL — WCRO Edition
 * No USDT needed. Uses native CRO wrapped to WCRO.
 *
 * Steps:
 *   1. Deploy new SZNPool(SZNX, WCRO)
 *   2. Update SZNRouter to point at new pool
 *   3. Set burn exemptions for new pool
 *   4. Wrap 20 CRO → WCRO
 *   5. Approve SZNX + WCRO for pool
 *   6. Seed: 20 SZNX + 20 WCRO → opens at 1 WCRO per SZNX
 */

import hre from "hardhat";

const WCRO_ADDRESS  = "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23";
const SZNX_ADDRESS  = "0x1d6C0448F3d9fE9B070eE9bfF3Ee0eebbfADEFF7";
const ROUTER_ADDRESS = "0x16c6727775f759020106d361aFa26691b607b452";
const TOKEN_ADDRESS  = SZNX_ADDRESS;

const WCRO_ABI = [
  "function deposit() external payable",
  "function balanceOf(address) external view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)",
];

const SEED_CRO  = hre.ethers.parseEther("20");    // 20 CRO → 20 WCRO
const SEED_SZNX = hre.ethers.parseUnits("20", 18); // 20 SZNX → price: 1 WCRO/SZNX

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const bal = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Deployer:", deployer.address);
  console.log("CRO balance:", hre.ethers.formatEther(bal), "\n");

  // ── 1. Deploy new SZNPool with SZNX/WCRO ──────────────────────────────────
  console.log("Deploying SZNPool (SZNX/WCRO)...");
  const SZNPool = await hre.ethers.getContractFactory("SZNPool");
  const pool = await SZNPool.deploy(SZNX_ADDRESS, WCRO_ADDRESS);
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("  New SZNPool:", poolAddr);

  // ── 2. Update router to point at new pool ─────────────────────────────────
  console.log("Updating SZNRouter to new pool...");
  const router = await hre.ethers.getContractAt(
    ["function setPool(address newPool) external"],
    ROUTER_ADDRESS
  );
  await (await router.setPool(poolAddr)).wait();
  console.log("  Router → new pool");

  // ── 3. Burn exemptions for new pool ───────────────────────────────────────
  console.log("Setting burn exemption for new pool...");
  const token = await hre.ethers.getContractAt(
    ["function setBurnExempt(address account, bool exempt) external"],
    TOKEN_ADDRESS
  );
  await (await token.setBurnExempt(poolAddr, true)).wait();
  console.log("  Pool burn-exempt: true");

  // ── 4. Authorize new pool's router ────────────────────────────────────────
  console.log("Authorizing router in new pool...");
  await (await pool.authorizeRouter(ROUTER_ADDRESS)).wait();
  console.log("  Router authorized");

  // ── 5. Wrap CRO → WCRO ────────────────────────────────────────────────────
  console.log("\nWrapping 20 CRO → WCRO...");
  const wcro = new hre.ethers.Contract(WCRO_ADDRESS, WCRO_ABI, deployer);
  await (await wcro.deposit({ value: SEED_CRO })).wait();
  const wcroBal = await wcro.balanceOf(deployer.address);
  console.log("  WCRO balance:", hre.ethers.formatEther(wcroBal));

  // ── 6. Approvals ──────────────────────────────────────────────────────────
  console.log("Approving SZNX and WCRO for pool...");
  const sznx = await hre.ethers.getContractAt(
    ["function approve(address spender, uint256 amount) external returns (bool)"],
    SZNX_ADDRESS
  );
  await (await sznx.approve(poolAddr, SEED_SZNX)).wait();
  await (await wcro.approve(poolAddr, SEED_CRO)).wait();
  console.log("  Approvals done");

  // ── 7. GENESIS SEED ───────────────────────────────────────────────────────
  console.log("\nExecuting MUSTARD SEED — 20 SZNX + 20 WCRO...");
  const tx = await pool.addLiquidity(SEED_SZNX, SEED_CRO, 0, 0, false);
  const receipt = await tx.wait();
  console.log("  TX:", receipt.hash);

  const reserveSZNX = await pool.reserveSZNX();
  const reserveUSDT = await pool.reserveUSDT();

  console.log("\n════════════════════════════════════════════");
  console.log("MUSTARD SEED COMPLETE — ADMIRAL'S BRIDGE OPEN");
  console.log("════════════════════════════════════════════");
  console.log("SZNPool (SZNX/WCRO):", poolAddr);
  console.log("Reserve SZNX:", hre.ethers.formatUnits(reserveSZNX, 18));
  console.log("Reserve WCRO:", hre.ethers.formatUnits(reserveUSDT, 18));
  console.log("Price: 1 SZNX = 1 WCRO");
  console.log(`Cronoscan: https://cronoscan.com/address/${poolAddr}`);
  console.log("════════════════════════════════════════════");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
