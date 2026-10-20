/**
 * VVS LISTING + SZN YIELD REACTOR
 *
 * Step 1: Add SZNX/WCRO liquidity to VVS Finance → SZNX appears on Cronos DEX
 * Step 2: Deploy SZNChef with 1,000,000 SZNX reward pool → degen APY
 * Step 3: Set reward rate (degenerate mode: 50 SZNX/block ≈ massive APY at low TVL)
 */

import hre from "hardhat";

const SZNX    = "0x1d6C0448F3d9fE9B070eE9bfF3Ee0eebbfADEFF7";
const WCRO    = "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23";

// VVS Finance — Uniswap V2 style on Cronos
const VVS_ROUTER  = "0x145863Eb42Cf62847A6Ca784e6416C1682b1b2Ae";
const VVS_FACTORY = "0x3B44B2a187a7b3824131F8db5a74194D0a42Fc15";

// Reward: 50 SZNX per block | Cronos ~6s blocks = ~14,400 blocks/day
// Daily emission: 720,000 SZNX | At $1/SZNX on thin TVL = DEGENERATE APY
const SZNX_PER_BLOCK = hre.ethers.parseUnits("50", 18);
const REACTOR_FUND   = hre.ethers.parseUnits("1000000", 18); // 1M SZNX reward pool

const ERC20_ABI = [
  "function approve(address, uint256) external returns (bool)",
  "function balanceOf(address) external view returns (uint256)",
];
const WCRO_ABI = [...ERC20_ABI, "function deposit() external payable"];
const VVS_ROUTER_ABI = [
  "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256, uint256, uint256)",
  "function factory() external view returns (address)",
];
const VVS_FACTORY_ABI = [
  "function getPair(address, address) external view returns (address)",
];

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Executor:", deployer.address);
  console.log("CRO balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "\n");

  const wcro       = new hre.ethers.Contract(WCRO,       WCRO_ABI,       deployer);
  const sznx       = new hre.ethers.Contract(SZNX,       ERC20_ABI,      deployer);
  const vvsRouter  = new hre.ethers.Contract(VVS_ROUTER, VVS_ROUTER_ABI, deployer);
  const vvsFactory = new hre.ethers.Contract(VVS_FACTORY, VVS_FACTORY_ABI, deployer);

  // ── STEP 1: VVS LISTING ───────────────────────────────────────────────────
  console.log("── STEP 1: VVS LISTING ──────────────────────────────");

  // Use 50 SZNX + 50 WCRO — matches ~1:1 ratio for easy discovery
  const VVS_SZNX = hre.ethers.parseUnits("50", 18);
  const VVS_WCRO = hre.ethers.parseEther("50");

  // Wrap 50 more CRO if needed
  const wcroBal = await wcro.balanceOf(deployer.address);
  if (wcroBal < VVS_WCRO) {
    const needed = VVS_WCRO - wcroBal;
    console.log("Wrapping", hre.ethers.formatEther(needed), "CRO...");
    await (await wcro.deposit({ value: needed })).wait();
  }

  console.log("Approving SZNX + WCRO for VVS Router...");
  await (await sznx.approve(VVS_ROUTER, VVS_SZNX)).wait();
  await (await wcro.approve(VVS_ROUTER, VVS_WCRO)).wait();

  console.log("Adding liquidity to VVS SZNX/WCRO pool...");
  const deadline = Math.floor(Date.now() / 1000) + 600;
  const [amtA, amtB, lpMinted] = await vvsRouter.addLiquidity.staticCall(
    SZNX, WCRO, VVS_SZNX, VVS_WCRO, 0, 0, deployer.address, deadline
  );

  const tx1 = await vvsRouter.addLiquidity(
    SZNX, WCRO, VVS_SZNX, VVS_WCRO, 0, 0, deployer.address, deadline
  );
  const r1 = await tx1.wait();
  console.log("  VVS listing TX:", r1.hash);

  // Get VVS LP token address
  const vvsLpAddr = await vvsFactory.getPair(SZNX, WCRO);
  console.log("  VVS LP Token:", vvsLpAddr);
  const vvsLp = new hre.ethers.Contract(vvsLpAddr, ERC20_ABI, deployer);
  const lpBal = await vvsLp.balanceOf(deployer.address);
  console.log("  LP tokens received:", hre.ethers.formatUnits(lpBal, 18));

  // ── STEP 2: DEPLOY SZN CHEF ───────────────────────────────────────────────
  console.log("\n── STEP 2: SZN CHEF DEPLOYMENT ─────────────────────");
  const Chef = await hre.ethers.getContractFactory("SZNChef");
  const chef = await Chef.deploy(SZNX, vvsLpAddr, SZNX_PER_BLOCK);
  await chef.waitForDeployment();
  const chefAddr = await chef.getAddress();
  console.log("  SZNChef deployed:", chefAddr);

  // ── STEP 3: FUND THE REACTOR ──────────────────────────────────────────────
  console.log("\n── STEP 3: FUNDING REACTOR ──────────────────────────");
  await (await sznx.approve(chefAddr, REACTOR_FUND)).wait();
  await (await chef.fundReactor(REACTOR_FUND)).wait();
  const reactorBal = await chef.reactorBalance();
  console.log("  Reactor funded:", hre.ethers.formatUnits(reactorBal, 18), "SZNX");

  // APY estimate
  const blocksPerDay = 14400n;
  const dailyEmission = SZNX_PER_BLOCK * blocksPerDay;
  console.log("  Daily emission:", hre.ethers.formatUnits(dailyEmission, 18), "SZNX/day");
  console.log("  Rate:", hre.ethers.formatUnits(SZNX_PER_BLOCK, 18), "SZNX/block");

  console.log("\n════════════════════════════════════════════════════════");
  console.log("VVS LISTED + YIELD REACTOR ARMED");
  console.log("════════════════════════════════════════════════════════");
  console.log("VVS LP Token:   ", vvsLpAddr);
  console.log("SZNChef:        ", chefAddr);
  console.log("Reactor balance: 1,000,000 SZNX");
  console.log("Rate:            50 SZNX/block (~720,000/day)");
  console.log("VVS pool:        https://vvs.finance/swap?inputCurrency=CRO&outputCurrency=" + SZNX);
  console.log("VVS farm guide:  Stake VVS LP at SZNChef to earn SZNX");
  console.log("Cronoscan Chef:  https://cronoscan.com/address/" + chefAddr);
  console.log("════════════════════════════════════════════════════════");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
