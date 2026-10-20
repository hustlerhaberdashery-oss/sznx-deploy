/**
 * deploy_sznrouter_fix.js — Redeploy SZNRouter pointed at the REAL SZNX V2 token
 *
 * Root cause (confirmed live on Cronos 2026-10-10): the router at
 * 0xa803a8F43fCceaA37f4AC064aa8FE42e1a7af778 was never redeployed during the
 * V1→V2 relaunch — only repointed to the new pool via setPool(). Its
 * `sznToken` is an immutable set at ORIGINAL deploy time and still resolves
 * to the dead V1 token (0x1d6C0448...), not V2 (0xD1d619...). Pool V2 itself
 * is correctly wired (sznxToken=V2, usdtToken=MockUSDC) — only the router's
 * own immutable is wrong, and Solidity immutables have no setter, so this
 * can't be patched in place. A live simulated swap() call against the old
 * router for V2 SZNX reverts with "SZNRouter: unsupported pair" — that's
 * the exact bug that's made every swap attempt fail since the relaunch.
 *
 * This script deploys a FRESH SZNRouter with the correct immutables, points
 * it at the EXISTING Pool V2 (unchanged — still holds its real 100 SZNX /
 * 100 MockUSDC liquidity, nothing about the pool's balances is touched),
 * authorizes the new router on that pool, and sets it burn-exempt on SZNX
 * V2 (2% transfer burn otherwise applies to every swap leg).
 *
 * Costs real CRO gas from the Soldier wallet (DEPLOYER_PRIVATE_KEY in .env)
 * — a few cents on Cronos, but a real on-chain write. Run deliberately:
 *   npx hardhat run scripts/deploy_sznrouter_fix.js --network cronos
 *
 * After it finishes, update:
 *   - /Users/user1/FLIXX_ENGINE/constants/sovereign_chain.js  (CONTRACTS.SZNX_ROUTER)
 *   - /Users/user1/FLIXX_ENGINE/suzerain-sovereign-app/frontend/src/config.js (ROUTER)
 *   - any other SZNX_ROUTER reference printed by `grep -rn SZNX_ROUTER` once done
 * with the new address this script prints.
 */
import hre from "hardhat";

const SZNX_V2        = "0xD1d619096392279cF0aEF8760258054e160954a5";
const USDC_CRONOS     = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59"; // secondary stable (routing not yet active in the contract — fine to wire, inert until SZNRouter.swap() enables it)
const MOCK_USDC       = "0x4AffE1628fB8AF85d51f5eea8b4E3Ba8C806b5Bd"; // what Pool V2 actually pairs against (labeled "usdtToken" in SZNRouter/SZNPool source)
const SZN_REGISTRY    = "0x794835e7ae213dfE0Dd538F052a6920ab1Ecafa5";
const POOL_V2         = "0xb2B6C2a19Db3B5BEe62FD0FE7f68294D747C8F73";
const OLD_ROUTER_V2   = "0xa803a8F43fCceaA37f4AC064aa8FE42e1a7af778"; // left in place, untouched — just no longer authorized
const SOLDIER         = "0xea473685526A83dc1Ab3C82A812AE8429F56eF1c";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("\n══════════════════════════════════════════════════");
  console.log("  SZNROUTER FIX — redeploy pointed at real SZNX V2");
  console.log("══════════════════════════════════════════════════");
  console.log("  Deployer :", deployer.address);
  if (deployer.address.toLowerCase() !== SOLDIER.toLowerCase()) {
    throw new Error(`Expected Soldier ${SOLDIER}, got ${deployer.address} — check DEPLOYER_PRIVATE_KEY in .env`);
  }
  const cro = await hre.ethers.provider.getBalance(deployer.address);
  console.log("  CRO gas  :", hre.ethers.formatEther(cro));

  // ── Sanity check: confirm the bug still exists before spending gas ──────
  const oldRouterAbi = ["function sznToken() view returns (address)"];
  const oldRouter = new hre.ethers.Contract(OLD_ROUTER_V2, oldRouterAbi, deployer);
  const oldSznToken = await oldRouter.sznToken();
  console.log("\n  Old router's sznToken():", oldSznToken);
  if (oldSznToken.toLowerCase() === SZNX_V2.toLowerCase()) {
    console.log("  Already points at V2 — nothing to fix. Exiting.");
    return;
  }
  console.log("  Confirmed broken (points at V1) — proceeding.");

  // ── 1. Deploy the corrected router ───────────────────────────────────────
  console.log("\n  1. Deploying corrected SZNRouter...");
  const SZNRouter = await hre.ethers.getContractFactory("SZNRouter");
  const router = await SZNRouter.deploy(SZNX_V2, USDC_CRONOS, MOCK_USDC, SZN_REGISTRY, POOL_V2);
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("     New SZNRouter:", routerAddr);

  // ── 2. Authorize it on the existing pool (pool + liquidity untouched) ───
  console.log("\n  2. Authorizing new router on Pool V2...");
  const poolAbi = ["function authorizeRouter(address) external", "function owner() view returns (address)"];
  const pool = new hre.ethers.Contract(POOL_V2, poolAbi, deployer);
  await (await pool.authorizeRouter(routerAddr)).wait(2);
  console.log("     ✓ Authorized");

  // ── 3. Burn-exempt the new router on SZNX V2 (2% transfer burn) ─────────
  console.log("\n  3. Setting new router burn-exempt on SZNX V2...");
  const sznxAbi = ["function setBurnExempt(address,bool) external", "function owner() view returns (address)"];
  const sznx = new hre.ethers.Contract(SZNX_V2, sznxAbi, deployer);
  await (await sznx.setBurnExempt(routerAddr, true)).wait(2);
  console.log("     ✓ Burn-exempt");

  // ── 4. Confirm it actually works now ─────────────────────────────────────
  console.log("\n  4. Verifying a real quote resolves...");
  const quoteAbi = ["function getAmountOut(address,address,uint256) view returns (uint256,uint256,uint256,uint256)"];
  const check = new hre.ethers.Contract(routerAddr, quoteAbi, deployer);
  const [amountOut] = await check.getAmountOut(SZNX_V2, MOCK_USDC, hre.ethers.parseUnits("1", 18));
  console.log("     1 SZNX ->", hre.ethers.formatUnits(amountOut, 6), "MockUSDC (quote)");

  console.log("\n══════════════════════════════════════════════════");
  console.log("  COMPLETE — UPDATE THESE FILES WITH THE NEW ADDRESS:");
  console.log("══════════════════════════════════════════════════");
  console.log("  New SZNX_ROUTER :", routerAddr);
  console.log("  constants/sovereign_chain.js        -> CONTRACTS.SZNX_ROUTER");
  console.log("  suzerain-sovereign-app/frontend/src/config.js -> ROUTER");
  console.log("  Old router (now unauthorized, left in place):", OLD_ROUTER_V2);
  console.log("══════════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
