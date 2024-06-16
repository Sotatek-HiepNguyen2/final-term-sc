import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import { config as dotEnvConfig } from "dotenv";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import type { HardhatUserConfig } from "hardhat/config";
import type { NetworkUserConfig } from "hardhat/types";

dotEnvConfig();

const chainIds = {
  hardhat: 31337,
  bsc: 97,
};

function getChainConfig(chain: keyof typeof chainIds): NetworkUserConfig {
  const jsonRpcUrl: string = process.env.BSC_RPC_URL as string;

  if (chain === "hardhat") {
    return {
      chainId: chainIds.hardhat,
      accounts: {
        count: 10,
      },
    };
  }

  return {
    accounts: [process.env.PRIVATE_KEY as string],
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
    enabled: true,
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
        details: {
          yulDetails: {
            optimizerSteps: "u",
          },
        },
      },
      viaIR: true,
    },
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
};

export default config;
