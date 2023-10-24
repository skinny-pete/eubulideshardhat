const { ethers } = require("hardhat");

const { getUSDC, wrapEth } = require("../test/utils.js");

// Assuming you have a list of token addresses and the SwapRouter address

const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const FEE = 500; // 0.05% fee tier in Uniswap V3

const SWAP_ROUTER_ADDRESS = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
const SwapRouterABI = [
  "function exactInput((bytes path, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum) params) external payable returns (uint256 amountOut)",
];

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
];

async function simulateSwaps(numSwaps = 16) {
  const [signer] = await ethers.getSigners();
  const router = new ethers.Contract(
    SWAP_ROUTER_ADDRESS,
    SwapRouterABI,
    signer
  );

  const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);

  // Set the fixed path for USDC-ETH with 0.05% fee
  const path = ethers.utils.hexConcat([
    USDC_ADDRESS,
    ethers.utils.hexZeroPad(ethers.utils.hexlify(FEE), 3),
    WETH_ADDRESS,
  ]);

  console.log("path:", path);

  for (let i = 0; i < 10; i++) {
    // Simulating 100 swaps for this example
    // Randomly select an amount to swap (e.g., between 1 and 1000 USDC)
    const amountIn = ethers.utils.parseUnits(
      (1 + Math.random() * 999).toFixed(6),
      6
    );

    // Fund the account with the required amount
    await getUSDC(amountIn, signer.address);
    await usdc.approve(SWAP_ROUTER_ADDRESS, amountIn);

    // Execute the swap with a reasonable slippage
    const amountOutMinimum = amountIn.mul(95).div(100); // 5% slippage for this example
    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes from now
    await router.exactInput({
      path,
      recipient: signer.address,
      deadline,
      amountIn,
      amountOutMinimum,
    });
  }
}

simulateSwaps()
  .then(() => console.log("Finished simulating swaps!"))
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  });
