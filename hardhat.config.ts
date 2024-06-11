import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import { config as dotEnvConfig } from "dotenv";
import "hardhat-deploy";
import type { HardhatUserConfig } from "hardhat/config";
import type { NetworkUserConfig } from "hardhat/types";

dotEnvConfig();

// Run 'npx hardhat vars setup' to see the list of variables that need to be set

const mnemonic: string = process.env.MNEMONIC as string;

const chainIds = {
  bsc: 97,
};

function getChainConfig(chain: keyof typeof chainIds): NetworkUserConfig {
  const jsonRpcUrl: string = "https://bsc-dataseed1.binance.org";

  return {
    accounts: {
      count: 10,
      mnemonic,
    },
    chainId: chainIds[chain],
    url: jsonRpcUrl,
  };
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: {
      bsc: process.env.BSCSCAN_API_KEY as string,
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  networks: {
    bsc: getChainConfig("bsc"),
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    version: "0.8.20",
    settings: {
      metadata: {
        // Not including the metadata hash
        // https://github.com/paulrberg/hardhat-template/issues/31
        bytecodeHash: "none",
      },
      // Disable the optimizer when debugging
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
};

export default config;
