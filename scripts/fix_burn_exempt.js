/**
 * fix_burn_exempt.js — Set Router V2 + Pool as SZNX burn-exempt
 * Uses hardhat signers (War Chest = index 0 in accounts array).
 * Run: npx hardhat run scripts/fix_burn_exempt.js --network cronos
 */
import hre from "hardhat";

const WAR_CHEST = "0xA8eE7348E0A3067f0959845EC52486641477f26d";
const SZNX      = "0x1d6C0448F3d9fE9B070eE9bfF3Ee0eebbfADEFF7";
const ROUTER_V2 = "0xa803a8F43fCceaA37f4AC064aa8FE42e1a7af778";
const POOL      = "0x17e563176934E9E7Fe5629e1e8A9e068e0579fB7";
const SOLDIER   = "0xea473685526A83dc1Ab3C82A812AE8429F56eF1c";

async function main() {
  const [warChest] = await hre.ethers.getSigners();
  if (warChest.address.toLowerCase() !== WAR_CHEST.toLowerCase())
    throw new Error(`Expected War Chest ${WAR_CHEST}, got ${warChest.address}\nSet DEPLOYER_PRIVATE_KEY to the War Chest key in .env before running.`);

  console.log("\n══════════════════════════════════════════════════");
  console.log("  SZNX BURN-EXEMPT FIX — Cronos Mainnet");
  console.log("══════════════════════════════════════════════════");
  console.log("  War Chest :", warChest.address);
  const cro = await hre.ethers.provider.getBalance(warChest.address);
  console.log("  CRO gas   :", hre.ethers.formatEther(cro));

  const ABI = [
    "function owner() view returns (address)",
    "function burnExempt(address) view returns (bool)",
    "function setBurnExempt(address account, bool exempt) external",
    "function transferOwnership(address newOwner) external",
  ];
  const token = new hre.ethers.Contract(SZNX, ABI, warChest);

  const owner = await token.owner();
  console.log("  SZNX owner:", owner);
  if (owner.toLowerCase() !== WAR_CHEST.toLowerCase())
    throw new Error("War Chest is not SZNX owner");

  const [routerExempt, poolExempt] = await Promise.all([
    token.burnExempt(ROUTER_V2), token.burnExempt(POOL)
  ]);
  console.log("  Router exempt (now):", routerExempt);
  console.log("  Pool exempt   (now):", poolExempt);

  console.log("\n  1. setBurnExempt(Router V2, true)...");
  if (!routerExempt) {
    const tx = await token.setBurnExempt(ROUTER_V2, true);
    console.log("     tx:", tx.hash);
    await tx.wait(2);
    console.log("     ✓ Router V2 exempt");
  } else {
    console.log("     already exempt — skip");
  }

  console.log("  2. setBurnExempt(Pool, true)...");
  if (!poolExempt) {
    const tx = await token.setBurnExempt(POOL, true);
    console.log("     tx:", tx.hash);
    await tx.wait(2);
    console.log("     ✓ Pool exempt");
  } else {
    console.log("     already exempt — skip");
  }

  console.log("  3. transferOwnership → Soldier...");
  const tx3 = await token.transferOwnership(SOLDIER);
  console.log("     tx:", tx3.hash);
  await tx3.wait(2);
  console.log("     ✓ Ownership → Soldier");

  const [re, pe, newOwner] = await Promise.all([
    token.burnExempt(ROUTER_V2), token.burnExempt(POOL), token.owner()
  ]);
  console.log("\n══════════════════════════════════════════════════");
  console.log("  COMPLETE");
  console.log("══════════════════════════════════════════════════");
  console.log("  Router V2 exempt :", re);
  console.log("  Pool exempt      :", pe);
  console.log("  SZNX owner       :", newOwner);
  console.log("  War Chest status : DECOMMISSIONED");
  console.log("══════════════════════════════════════════════════\n");
}

main().catch(e => { console.error(e); process.exit(1); });
