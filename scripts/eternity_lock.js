/**
 * SZN ETERNITY LOCK + SIGNAL BUY
 * 1. Deploy SZNEternityLock
 * 2. Seal 100 SZNX + 100 WCRO into vault (100-year lock)
 * 3. Execute Signal Buy: 10 CRO → SZNX (first green candle)
 */

import hre from "hardhat";

const SZNX    = "0x1d6C0448F3d9fE9B070eE9bfF3Ee0eebbfADEFF7";
const WCRO    = "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23";
const POOL    = "0xe2461b2Fd7a97c3947FE395Ebf2483Cf8B0027AF";
const ROUTER  = "0x16c6727775f759020106d361aFa26691b607b452";

const WCRO_ABI = [
  "function deposit() external payable",
  "function balanceOf(address) external view returns (uint256)",
  "function approve(address, uint256) external returns (bool)",
];
const ERC20_ABI = [
  "function approve(address, uint256) external returns (bool)",
  "function balanceOf(address) external view returns (uint256)",
];
const POOL_SWAP_ABI = [
  "function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut)",
];

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Executor:", deployer.address);
  console.log("CRO balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "\n");

  const wcro = new hre.ethers.Contract(WCRO, WCRO_ABI, deployer);
  const sznx = new hre.ethers.Contract(SZNX, ERC20_ABI, deployer);
  const pool = new hre.ethers.Contract(POOL, POOL_SWAP_ABI, deployer);

  // ── 1. Deploy SZNEternityLock ──────────────────────────────────────────────
  console.log("Deploying SZNEternityLock...");
  const Lock = await hre.ethers.getContractFactory("SZNEternityLock");
  const lock = await Lock.deploy(SZNX, WCRO, POOL, deployer.address);
  await lock.waitForDeployment();
  const lockAddr = await lock.getAddress();
  const expiry   = await lock.lockExpiry();
  const expiryDate = new Date(Number(expiry) * 1000).getFullYear();
  console.log("  SZNEternityLock:", lockAddr);
  console.log("  Lock expires:    Year", expiryDate, "\n");

  // ── 2. Wrap 110 CRO → WCRO (100 for lock, 10 for signal buy) ─────────────
  console.log("Wrapping 110 CRO → WCRO...");
  await (await wcro.deposit({ value: hre.ethers.parseEther("110") })).wait();
  console.log("  WCRO balance:", hre.ethers.formatEther(await wcro.balanceOf(deployer.address)));

  // ── 3. Set burn exemption for lock contract ───────────────────────────────
  console.log("Setting burn exemption for lock vault...");
  const tokenAdmin = await hre.ethers.getContractAt(
    ["function setBurnExempt(address account, bool exempt) external"],
    SZNX
  );
  await (await tokenAdmin.setBurnExempt(lockAddr, true)).wait();
  console.log("  Lock vault burn-exempt: true");

  // ── 4. Approve lock contract ───────────────────────────────────────────────
  const LOCK_SZNX = hre.ethers.parseUnits("100", 18);
  const LOCK_WCRO = hre.ethers.parseEther("100");
  console.log("Approving lock...");
  await (await sznx.approve(lockAddr, LOCK_SZNX)).wait();
  await (await wcro.approve(lockAddr, LOCK_WCRO)).wait();

  // ── 5. SEAL THE ESTATE ────────────────────────────────────────────────────
  console.log("Sealing estate — 100 SZNX + 100 WCRO locked for 100 years...");
  const sealTx = await lock.seal(LOCK_SZNX, LOCK_WCRO);
  const sealReceipt = await sealTx.wait();
  console.log("  Seal TX:", sealReceipt.hash);
  console.log("  Locked shares:", hre.ethers.formatUnits(await lock.lockedShares(), 18));

  // ── 6. SIGNAL BUY — first green candle (direct pool swap) ─────────────────
  console.log("\nExecuting Signal Buy — 10 WCRO → SZNX (direct pool)...");
  const BUY_WCRO = hre.ethers.parseEther("10");
  await (await wcro.approve(POOL, BUY_WCRO)).wait();
  const swapTx = await pool.swap(WCRO, SZNX, BUY_WCRO, 0, deployer.address);
  const swapReceipt = await swapTx.wait();
  console.log("  Swap TX:", swapReceipt.hash);
  console.log("  First green candle painted.");

  const sznxBal = await sznx.balanceOf(deployer.address);
  console.log("  SZNX received:", hre.ethers.formatUnits(sznxBal, 18));

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n════════════════════════════════════════════════");
  console.log("THE IMMUTABLE SEAL IS WRITTEN");
  console.log("════════════════════════════════════════════════");
  console.log("EternityLock vault:  ", lockAddr);
  console.log("Locked until:        Year", expiryDate);
  console.log("Seal TX:             ", sealReceipt.hash);
  console.log("Signal Buy TX:       ", swapReceipt.hash);
  console.log("DEX chart:            https://dexscreener.com/cronos/", POOL);
  console.log("Cronoscan vault:      https://cronoscan.com/address/", lockAddr);
  console.log("════════════════════════════════════════════════");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
