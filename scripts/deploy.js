/**
 * SZN Sovereign Deployment Script
 * Chain: Cronos Mainnet (chainId: 25)
 *
 * Deploy sequence:
 *   1. SZNToken
 *   2. SZNRegistry(sznToken)
 *   3. SZNPool(sznToken, usdt)
 *   4. SZNRouter(sznToken, usdc, usdt, registry, pool)
 *   5. setBurnExempt(pool)   — pool skips 2% burn on SZNX transfers
 *   6. setBurnExempt(router) — router skips 2% burn on SZNX transfers
 *   7. pool.authorizeRouter(router)
 *   8. registry.authorizeRouter(router)
 *
 * Liquidity seeding (Phase 1 GENESIS SEED) is NOT done here.
 * Run seed.js separately after verifying all addresses.
 */

import hre from "hardhat";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Deployer:", deployer.address);
  console.log("Balance: ", hre.ethers.formatEther(balance), "CRO\n");

  const MIN_CRO = hre.ethers.parseEther("5");
  if (balance < MIN_CRO) {
    throw new Error(`Insufficient CRO: have ${hre.ethers.formatEther(balance)}, need >= 5 CRO for deployment gas`);
  }

  const USDT_ADDRESS = process.env.USDT_ADDRESS;
  const USDC_ADDRESS = process.env.USDC_ADDRESS;

  if (!USDT_ADDRESS || !USDC_ADDRESS) {
    throw new Error("USDT_ADDRESS and USDC_ADDRESS must be set in .env");
  }

  // ── 1. SZNToken ────────────────────────────────────────────────────────────
  console.log("Deploying SZNToken...");
  const SZNToken = await hre.ethers.getContractFactory("SZNToken");
  const token = await SZNToken.deploy();
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();
  console.log("  SZNToken deployed:", tokenAddr);

  // ── 2. SZNRegistry ────────────────────────────────────────────────────────
  console.log("Deploying SZNRegistry...");
  const SZNRegistry = await hre.ethers.getContractFactory("SZNRegistry");
  const registry = await SZNRegistry.deploy(tokenAddr);
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log("  SZNRegistry deployed:", registryAddr);

  // ── 3. SZNPool ────────────────────────────────────────────────────────────
  console.log("Deploying SZNPool...");
  const SZNPool = await hre.ethers.getContractFactory("SZNPool");
  const pool = await SZNPool.deploy(tokenAddr, USDT_ADDRESS);
  await pool.waitForDeployment();
  const poolAddr = await pool.getAddress();
  console.log("  SZNPool deployed:", poolAddr);

  // ── 4. SZNRouter ──────────────────────────────────────────────────────────
  console.log("Deploying SZNRouter...");
  const SZNRouter = await hre.ethers.getContractFactory("SZNRouter");
  const router = await SZNRouter.deploy(tokenAddr, USDC_ADDRESS, USDT_ADDRESS, registryAddr, poolAddr);
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("  SZNRouter deployed:", routerAddr);

  // ── 5-6. Burn exemptions ──────────────────────────────────────────────────
  console.log("\nConfiguring burn exemptions...");
  await (await token.setBurnExempt(poolAddr,   true)).wait();
  console.log("  Pool burn-exempt: true");
  await (await token.setBurnExempt(routerAddr, true)).wait();
  console.log("  Router burn-exempt: true");

  // ── 7. Authorize router in pool ───────────────────────────────────────────
  console.log("Authorizing router in pool...");
  await (await pool.authorizeRouter(routerAddr)).wait();
  console.log("  Pool router authorized");

  // ── 8. Authorize router in registry ──────────────────────────────────────
  console.log("Authorizing router in registry...");
  await (await registry.authorizeRouter(routerAddr)).wait();
  console.log("  Registry router authorized");

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n════════════════════════════════════════");
  console.log("DEPLOYMENT COMPLETE — save these addresses");
  console.log("════════════════════════════════════════");
  console.log("SZNToken:    ", tokenAddr);
  console.log("SZNRegistry: ", registryAddr);
  console.log("SZNPool:     ", poolAddr);
  console.log("SZNRouter:   ", routerAddr);
  console.log("════════════════════════════════════════");
  console.log("\nNext: fill .env with these addresses, then run seed.js for Phase 1 GENESIS SEED.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
