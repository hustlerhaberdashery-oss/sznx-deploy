require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const key = process.env.DEPLOYER_PRIVATE_KEY;

module.exports = {
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

  paths: {
    sources:   "./contracts",
    scripts:   "./scripts",
    artifacts: "./artifacts",
    cache:     "./cache",
  },
};
