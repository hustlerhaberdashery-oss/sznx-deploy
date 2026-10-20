/**
 * MUSTARD SEED PROTOCOL — Genesis Liquidity
 *
 * Ratio: 1:1 SZNX/USDT → opens market at $1.00/SZNX
 * Amount is intentionally small — ratio is what sets price.
 * Add liquidity later without changing the price.
 *
 * Prerequisites:
 *   - deploy.js must have run successfully
 *   - Set SZN_TOKEN, SZN_POOL, USDT_ADDRESS in .env
 *   - Deployer wallet must hold >= SZNX_SEED SZNX and >= USDT_SEED USDT on Cronos
 */

import hre from "hardhat";

const SZNX_SEED = hre.ethers.parseUnits("10", 18);  // 10 SZNX  — ratio sets $1.00 price
const USDT_SEED = hre.ethers.parseUnits("10",  6);  // 10 USDT

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Seeder:", deployer.address);

  const tokenAddr = process.env.SZN_TOKEN;
  const poolAddr  = process.env.SZN_POOL;
  const usdtAddr  = process.env.USDT_ADDRESS;

  if (!tokenAddr || !poolAddr || !usdtAddr) {
    throw new Error("SZN_TOKEN, SZN_POOL, and USDT_ADDRESS must be set in .env");
  }

  const token = await hre.ethers.getContractAt("SZNToken", tokenAddr);
  const pool  = await hre.ethers.getContractAt("SZNPool",  poolAddr);
  const usdt  = await hre.ethers.getContractAt("contracts/SZNPool.sol:IERC20", usdtAddr);

  // Balance check
  const sznxBal = await token.balanceOf(deployer.address);
  const usdtBal = await usdt.balanceOf(deployer.address);
  console.log("SZNX balance:", hre.ethers.formatUnits(sznxBal, 18));
  console.log("USDT balance:", hre.ethers.formatUnits(usdtBal, 6));

  if (sznxBal < SZNX_SEED) throw new Error("Insufficient SZNX balance");
  if (usdtBal < USDT_SEED) throw new Error("Insufficient USDT balance");

  // Approvals
  console.log("\nApproving SZNX...");
  await (await token.approve(poolAddr, SZNX_SEED)).wait();
  console.log("Approving USDT...");
  await (await usdt.approve(poolAddr, USDT_SEED)).wait();

  // Seed
  console.log("\nCalling addLiquidity (Phase 1 GENESIS SEED)...");
  const tx = await pool.addLiquidity(SZNX_SEED, USDT_SEED, 0, 0, false);
  const receipt = await tx.wait();
  console.log("  TX hash:", receipt.hash);

  // Verify
  const reserveSZNX = await pool.reserveSZNX();
  const reserveUSDT = await pool.reserveUSDT();
  const spot        = await pool.spotPrice();

  console.log("\n════════════════════════════════════════");
  console.log("GENESIS SEED COMPLETE");
  console.log("════════════════════════════════════════");
  console.log("reserveSZNX: ", hre.ethers.formatUnits(reserveSZNX, 18), "SZNX");
  console.log("reserveUSDT: ", hre.ethers.formatUnits(reserveUSDT, 6),  "USDT");
  console.log("Spot price:  $", hre.ethers.formatUnits(spot, 6), "/ SZNX");
  console.log("════════════════════════════════════════");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
