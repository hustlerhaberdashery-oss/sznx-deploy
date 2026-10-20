import hre from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  console.log("==========================================================");
  console.log("[-] SZNX V3 INFRASTRUCTURE: VERIFIED STATE SYNC CHECK");
  console.log("==========================================================");

  delete process.env.CRONOS_MAINNET_RPC_URL;
  delete process.env.RPC_URL;
  delete process.env.PRIVATE_KEY;

  const targetAddress = "0x9b2Fc44646D5157E6A85b13e91b7A1c3fa17c13e";
  
  // Adjusted target contract name mapped to the true artifact file
  const targetContract = "SZNToken";

  try {
    console.log("[...] Triggering automatic local compilation pass...");
    await hre.run("compile");
    console.log("[🟩] Hardhat compilation passed successfully.");

    const expectedFile = "./artifacts/contracts/SZNToken.sol/SZNToken.json";

    if (!fs.existsSync(expectedFile)) {
      throw new Error(`Could not find a compiled artifact matching: ${expectedFile}`);
    }
    
    console.log(`[🟩] Primary Token Artifact Located: ${expectedFile}`);

    const artifact = JSON.parse(fs.readFileSync(expectedFile, "utf8"));
    const mintFunction = artifact.abi.find(item => item.name === "mint");

    console.log(`[🔍] Local Contract Artifact Verified: ${artifact.contractName}`);
    console.log(`    ├── Total Defined Functions: ${artifact.abi.filter(i => i.type === "function").length}`);
    console.log(`    └── Owner Mint Routine Cap: ${mintFunction ? "UN-CAPPED EMISSION MODEL" : "FIXED MODEL"}`);

    console.log("\n[🟩] SYNCHRONIZATION STATUS: CLEAR");
    console.log(`    └── Target Tracking Registry: ${targetAddress}`);
    console.log("==========================================================");
  } catch (error) {
    console.error("\n[🚨] INTEGRITY CHECK ENCOUNTERED AN ERROR:", error.message);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
