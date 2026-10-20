import hre from "hardhat";

const POOL  = "0xe2461b2Fd7a97c3947FE395Ebf2483Cf8B0027AF";
const VAULT = "0xc780ad42D79561291Df0010217c1c3D5713a957B";

const pool = await hre.ethers.getContractAt([
  "function reserveSZNX() view returns (uint256)",
  "function reserveUSDT() view returns (uint256)",
  "function totalShares() view returns (uint256)",
], POOL);

const vault = await hre.ethers.getContractAt([
  "function lockedShares() view returns (uint256)",
  "function yearsRemaining() view returns (uint256)",
  "function lockExpiry() view returns (uint256)",
  "function isSealed() view returns (bool)",
], VAULT);

const [rSZNX, rWCRO, totalShares] = await Promise.all([
  pool.reserveSZNX(), pool.reserveUSDT(), pool.totalShares()
]);
const [locked, years, expiry, sealed] = await Promise.all([
  vault.lockedShares(), vault.yearsRemaining(), vault.lockExpiry(), vault.isSealed()
]);

const price = Number(rWCRO) / Number(rSZNX);

console.log("══ POOL ═══════════════════");
console.log("reserveSZNX:", hre.ethers.formatUnits(rSZNX, 18));
console.log("reserveWCRO:", hre.ethers.formatUnits(rWCRO, 18));
console.log("totalShares:", hre.ethers.formatUnits(totalShares, 18));
console.log("SZNX price: ", price.toFixed(6), "WCRO");
console.log("══ VAULT ══════════════════");
console.log("isSealed:   ", sealed);
console.log("lockedShares:", hre.ethers.formatUnits(locked, 18));
console.log("yearsLeft:  ", years.toString());
console.log("unlocks:     Year", new Date(Number(expiry)*1000).getFullYear());
