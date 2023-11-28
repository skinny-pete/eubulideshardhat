const hre = require("hardhat");

async function main() {
  const abi = ["function quoteSingle(address token0,address token1,uint amount0,uint duration) public view returns (uint amount1, uint quote0, uint quote1)"]
  const address = "0x0ce2eE94FC8f5710cC92eC201Dc65Be94a1e2Bc9"
  const core = await hre.ethers.getContractAt(abi, address)

  const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

  const [signer] = await ethers.getSigners()

  const gasPrice = await signer.getGasPrice()
  console.log("gas price is ", gasPrice)

  const vals = await core.quoteSingle(USDC_ADDRESS, WETH_ADDRESS, ethers.utils.parseUnits("1000", 6), 3)


}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
