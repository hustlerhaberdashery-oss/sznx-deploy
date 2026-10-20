/**
 * Seed SZNPool V3 with real SZNX V3 + freshly-minted MockUSDC.
 *
 * Precondition (must happen BEFORE this script, outside this repo): the V3
 * token owner wallet (0x3c86d185de4b276eba0b21d8485887cbb104cbe5) must mint
 * supply and transfer at least SEED_SZNX worth to the deployer wallet below
 * (DEPLOYER_PRIVATE_KEY in .env). This script will check that balance and
 * refuse to proceed (no gas spent beyond the check) if it's insufficient —
 * it never attempts to mint or move V3 tokens itself, since this repo's
 * deployer key does not own that contract.
 *
 * MockUSDC (the other side of the pair) IS Soldier-owned and mintable here,
 * so that half is zero real-fund risk — this script mints it fresh.
 *
 * Run: SZN_POOL=<from deploy_sznx_v3_infra.js> npx hardhat run \
 *      scripts/seed_sznx_v3_pool.js --network cronos
 */
import hre from "hardhat";

const SZNX_V3 = "0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e";
const SEED_SZNX = "100"; // human units, matches V2's seed depth
const SEED_USDC = "100"; // human units — $1.00/SZNX spot, matching V2

async function main() {
  const POOL = process.env.SZN_POOL;
  const USDT_ADDR = process.env.USDT_ADDRESS; // MockUSDC
  if (!POOL || !USDT_ADDR) throw new Error("SZN_POOL and USDT_ADDRESS must be set");

  const [deployer] = await hre.ethers.getSigners();
  console.log("\n══════════════════════════════════════════════════");
  console.log("  SZNPool V3 — SEED CHECK");
  console.log("══════════════════════════════════════════════════");
  console.log("  Deployer :", deployer.address);
  console.log("  Pool     :", POOL);

  const sznx = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)",
     "function approve(address,uint256) returns (bool)"],
    SZNX_V3
  );

  const needed = hre.ethers.parseUnits(SEED_SZNX, 18);
  const have = await sznx.balanceOf(deployer.address);
  console.log("  SZNX V3 balance at deployer:", hre.ethers.formatUnits(have, 18));

  if (have < needed) {
    console.log("\n  ✗ STOP — deployer does not hold enough SZNX V3 to seed.");
    console.log("    Needed :", SEED_SZNX, "SZNX");
    console.log("    Have   :", hre.ethers.formatUnits(have, 18), "SZNX");
    console.log("\n    The V3 owner wallet (0x3c86d185de4b276eba0b21d8485887cbb104cbe5)");
    console.log("    must mint and transfer SZNX V3 to", deployer.address, "first.");
    console.log("    No transaction has been sent. Exiting.\n");
    process.exit(1);
  }

  console.log("\n  [1/4] Minting", SEED_USDC, "MockUSDC to deployer (Soldier owns MockUSDC)...");
  const usdc = await hre.ethers.getContractAt(
    ["function mint(address,uint256) external",
     "function approve(address,uint256) returns (bool)"],
    USDT_ADDR
  );
  await (await usdc.mint(deployer.address, hre.ethers.parseUnits(SEED_USDC, 6))).wait(2);
  console.log("        ✓ Minted");

  console.log("  [2/4] Approving SZNX V3 for pool...");
  await (await sznx.approve(POOL, hre.ethers.MaxUint256)).wait(2);
  console.log("        ✓ Approved");

  console.log("  [3/4] Approving MockUSDC for pool...");
  await (await usdc.approve(POOL, hre.ethers.MaxUint256)).wait(2);
  console.log("        ✓ Approved");

  console.log("  [4/4] Seeding —", SEED_SZNX, "SZNX V3 +", SEED_USDC, "MockUSDC...");
  const pool = await hre.ethers.getContractAt(
    ["function addLiquidity(uint256,uint256,uint256,uint256,bool) external",
     "function spotPrice() view returns (uint256)"],
    POOL
  );
  const tx = await pool.addLiquidity(
    hre.ethers.parseUnits(SEED_SZNX, 18),
    hre.ethers.parseUnits(SEED_USDC, 6),
    0, 0, false,
    { gasLimit: 500_000 }
  );
  console.log("        Tx:", tx.hash);
  const receipt = await tx.wait(2);
  if (receipt.status !== 1) throw new Error("addLiquidity reverted");

  const spot = await pool.spotPrice();
  console.log("\n══════════════════════════════════════════════════");
  console.log("  SEEDED — spot:", hre.ethers.formatUnits(spot, 6), "USDC/SZNX");
  console.log("  Cronoscan: https://cronoscan.com/tx/" + tx.hash);
  console.log("══════════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
