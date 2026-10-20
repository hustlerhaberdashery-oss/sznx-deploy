/**
 * Self-mint SZNX V3 supply to the token's own owner wallet
 * (0x3c86d185de4b276eba0b21d8485887cbb104cbe5 — confirmed on-chain owner()).
 *
 * Confirmed on-chain before this script was written:
 *   - mint(address,uint256) exists, selector 0x40c10f19
 *   - gated by OpenZeppelin Ownable (reverts OwnableUnauthorizedAccount for
 *     anyone else; simulated call from the owner succeeds)
 *
 * SECURITY: reads the owner's private key ONLY from the OWNER_PRIVATE_KEY
 * env var, set in your own shell, in a command you type yourself — never
 * pasted into any chat. This script never prints the key.
 *
 * Run:
 *   OWNER_PRIVATE_KEY=0x... MINT_AMOUNT=1000000 \
 *     node scripts/mint_sznx_v3_supply.js
 *
 *   MINT_AMOUNT is in whole SZNX (18 decimals handled for you). Pick a
 *   number that covers both your VVS seed liquidity and whatever
 *   circulating supply you want live.
 */
import { JsonRpcProvider, Wallet, Contract, parseUnits, formatUnits } from "ethers";

const SZNX_V3 = "0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e";
const RPC = "https://cronos-evm-rpc.publicnode.com";
const CHAIN_ID = 25;

async function main() {
  const key = process.env.OWNER_PRIVATE_KEY;
  const amountStr = process.env.MINT_AMOUNT;
  if (!key) throw new Error("OWNER_PRIVATE_KEY env var not set — see comment at top of this file.");
  if (!amountStr) throw new Error("MINT_AMOUNT env var not set (whole SZNX units).");

  const provider = new JsonRpcProvider(RPC, CHAIN_ID, { staticNetwork: true });
  const wallet = new Wallet(key, provider);

  console.log("==========================================================");
  console.log("  SZNX V3 — OWNER SELF-MINT");
  console.log("==========================================================");
  console.log("  Signer  :", wallet.address);

  const abi = [
    "function owner() view returns (address)",
    "function mint(address to, uint256 amount) external",
    "function balanceOf(address) view returns (uint256)",
  ];
  const token = new Contract(SZNX_V3, abi, wallet);

  const onChainOwner = await token.owner();
  if (onChainOwner.toLowerCase() !== wallet.address.toLowerCase()) {
    throw new Error(`Signer (${wallet.address}) is not the on-chain owner (${onChainOwner}) — wrong key.`);
  }

  const amount = parseUnits(amountStr, 18);
  const before = await token.balanceOf(wallet.address);
  console.log("  Balance before:", formatUnits(before, 18), "SZNX");

  console.log(`  Minting ${amountStr} SZNX to self...`);
  const tx = await token.mint(wallet.address, amount);
  console.log("  Tx sent:", tx.hash);
  const receipt = await tx.wait(2);
  if (receipt.status !== 1) throw new Error("mint tx reverted");

  const after = await token.balanceOf(wallet.address);
  console.log("\n  ✓ MINT COMPLETE");
  console.log("  Balance after:", formatUnits(after, 18), "SZNX");
  console.log("  Cronoscan:", "https://cronoscan.com/tx/" + tx.hash);
  console.log("==========================================================\n");
}

main().catch((e) => { console.error("FAILED:", e.message || e); process.exit(1); });
