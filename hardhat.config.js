import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
dotenv.config();

const key = process.env.DEPLOYER_PRIVATE_KEY;

export default {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },

  networks: {
    hardhat: {},

    cronos: {
      url: process.env.CRONOS_RPC_URL || "https://evm.cronos.org",
      chainId: 25,
      accounts: key ? [key.startsWith("0x") ? key : `0x${key}`] : [],
    },
  },

  etherscan: {
    apiKey: {
      cronos: process.env.CRONOSCAN_API_KEY || "no-api-key-needed",
    },
    customChains: [
      {
        network: "cronos",
        chainId: 25,
        urls: {
          apiURL: "https://api.cronoscan.com/api",
          browserURL: "https://cronoscan.com",
        },
      },
    ],
  },

  paths: {
    sources:   "./contracts",
    scripts:   "./scripts",
    artifacts: "./artifacts",
    cache:     "./cache",
  },
};
