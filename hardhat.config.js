/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
require("hardhat-tracer");
/** @type import('hardhat/config').HardhatUserConfig */

const INFURA_API_KEY = "your_infura_api_key";
const PRIVATE_KEY = "12e903555a035a8c414a39ec613e9815c3c17ae16e5b5c4ea5b3ff729539ee80";


module.exports = {
  solidity: {
    version: "0.7.5",
    settings: {
      optimizer: {
        enabled: true,
        runs: 400,
      },
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://mainnet.infura.io/v3/0f5c48489afe4ee383588b325a35b9da",
        blockNumber: 18392095,
      },
      mining: {
        mempool: {
          order: "fifo"
        }
      }
    },
    goerli: {
      url: "https://goerli.infura.io/v3/0f5c48489afe4ee383588b325a35b9da",
      accounts: [`0x${PRIVATE_KEY}`]
    }
  },
};

//18392067
