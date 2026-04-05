require("@nomicfoundation/hardhat-toolbox");

// Load environment variables
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x" + "0".repeat(64);
const INFURA_KEY = process.env.INFURA_KEY || "";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun", // Required for transient storage (EIP-1153)
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    // Zama Protocol Sepolia testnet
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      accounts: [PRIVATE_KEY],
      chainId: 11155111,
    },
    // Zama Protocol devnet (if available)
    zamaDevnet: {
      url: process.env.ZAMA_DEVNET_URL || "http://localhost:8545",
      accounts: [PRIVATE_KEY],
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};
