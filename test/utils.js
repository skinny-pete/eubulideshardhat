const { network, ethers } = require("hardhat");
const { BigNumber } = require("ethers");

const FEE = 500; // 0.05% fee tier in Uniswap V3
const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

const path = ethers.utils.hexConcat([
  USDC_ADDRESS,
  ethers.utils.hexZeroPad(ethers.utils.hexlify(FEE), 3),
  WETH_ADDRESS,
]);

const SWAP_ROUTER_ADDRESS = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
const SwapRouterABI = [
  "function exactInput((bytes path, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum) params) external payable returns (uint256 amountOut)",
];

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address owner) view returns (uint)"
];

const WETH_ABI = [
  "function deposit() external payable",
  "function balanceOf(address owner) view returns (uint)",
  "function transfer(address to, uint256 value) external returns (bool)",
  "function approve(address spender, uint256 amount) external returns (bool)"
];

const UNISWAP_POOL_ADDRESS = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"

async function getUSDC(amount, addressTo) {
  const richGuyAddress = "0xcEe284F754E854890e311e3280b767F80797180d";
  const ERC20_ABI = [
    "function transfer(address who, uint amount) public",
    "function balanceOf(address) public view returns (uint)",
  ];


  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [richGuyAddress],
  });
  const signer = await ethers.getSigner(richGuyAddress);

  await network.provider.send("hardhat_setBalance", [
    signer.address,
    "0x10000000000000000",
  ]);

  const usdc = await ethers.getContractAt(ERC20_ABI, USDC_ADDRESS, signer);

  await usdc.transfer(addressTo, amount, {
    gasLimit: 1000000,
  });
}

async function wrapEth(amountToWrap, addressTo, signer) {


  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, signer);
  const tx = await weth.deposit({ value: amountToWrap });
  await tx.wait();

  const transferTx = await weth.transfer(addressTo, amountToWrap);
  await transferTx.wait();
}

async function simulateSwaps(numSwaps = 5) {
  const [signer] = await ethers.getSigners();
  const router = new ethers.Contract(SWAP_ROUTER_ADDRESS, SwapRouterABI, signer);
  const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, signer);

  const path0 = ethers.utils.hexConcat([USDC_ADDRESS, ethers.utils.hexZeroPad(ethers.utils.hexlify(FEE), 3), WETH_ADDRESS]);
  const path1 = ethers.utils.hexConcat([WETH_ADDRESS, ethers.utils.hexZeroPad(ethers.utils.hexlify(FEE), 3), USDC_ADDRESS]);

  let [total0, total1] = [BigNumber.from(0), BigNumber.from(0)]

  for (let i = 0; i < numSwaps; i++) {
    try {
      const path = Math.random() < 0.5 ? path0 : path1;
      let randomNumber = Math.floor(Math.random() * 10000) + 1; // Ensure non-zero
      let amountIn = ethers.utils.parseUnits(randomNumber.toString(), 6); // USDC has 6 decimals
      // console.log("amountIn USDC", amountIn)

      if (path === path0) {

        total0.add(BigNumber.from(amountIn))
        await getUSDC(amountIn, signer.address);
        await usdc.approve(SWAP_ROUTER_ADDRESS, amountIn);
      } else {
        // Convert amountIn (USDC) to equivalent WETH
        let amountInWETH = await getToken1AmountFromToken0(amountIn, 6, 18, UNISWAP_POOL_ADDRESS);
        total1.add(BigNumber.from(amountInWETH))
        if (amountInWETH.isZero()) {
          throw new Error("Converted WETH amount is zero.");
        }


        await wrapEth(amountInWETH, signer.address, signer);
        await weth.approve(SWAP_ROUTER_ADDRESS, amountInWETH);
        amountIn = amountInWETH; // Use the converted WETH amount for the swap
      }

      // Perform the swap
      const amountOutMinimum = 0; // Consider calculating a reasonable minimum
      const deadline = Math.floor(Date.now() / 1000) + 60 * 20;
      await router.exactInput({ path, recipient: signer.address, deadline, amountIn, amountOutMinimum });

      // Post-swap actions
      await network.provider.send('evm_mine');
    } catch (error) {
      console.error("Swap failed in iteration", i, "with error:", error.message);
      break; // Consider if you want to stop on first error or continue
    }
  }
  return total0, total1
}

async function getToken1AmountFromToken0(
  amountToken0,
  token0Decimals,
  token1Decimals,
  poolAddress
) {
  const sqrtPriceX96 = await getSqrtPrice(poolAddress);
  const price = sqrtPriceX96.pow(2).div(BigNumber.from(2).pow(192));

  const amountToken0Wei = BigNumber.from(amountToken0);

  // Calculate the amount of token1
  let amountToken1Wei = amountToken0Wei
    .mul(price)
    .div(BigNumber.from(10).pow(18 + token0Decimals - token1Decimals));

  return amountToken1Wei;
}




// async function getToken1AmountFromToken0(
//   amountToken0,
//   token0Decimals,
//   token1Decimals,
//   poolAddress
// ) {
//   const sqrtPriceX96 = await getSqrtPrice(poolAddress);

//   // Convert the amount of token0 to its smallest unit
//   const amountToken0Wei = BigNumber.from(amountToken0).mul(
//     BigNumber.from(10).pow(token0Decimals)
//   );

//   // Calculate the current price per token in terms of token1
//   const currentPrice = sqrtPriceX96
//     .mul(sqrtPriceX96)
//     .div(BigNumber.from(2).pow(96))
//     .mul(BigNumber.from(10).pow(token1Decimals - token0Decimals));

//   // Convert token0 to token1
//   let amountToken1Wei = amountToken0Wei
//     .mul(currentPrice)
//     .div(BigNumber.from(2).pow(96));

//   // Adjust for token1 decimals, if necessary
//   if (token0Decimals !== token1Decimals) {
//     amountToken1Wei = amountToken1Wei.div(BigNumber.from(10).pow(18 - token1Decimals));
//   }

//   return amountToken1Wei;
// }


async function slot0(poolAddress) {
  const abi = [
    "function slot0() public view returns (uint160 sqrtPriceX96,int24 tick,uint16 observationIndex,uint16 observationCardinality,uint16 observationCardinalityNext,uint8 feeProtocol,bool unlocked)",
  ];
  const pool = await ethers.getContractAt(abi, poolAddress);

  const res = await pool.slot0();
  return res;
  //   console.log(res);
}

async function getTick(poolAddress) {
  const s0 = await slot0(poolAddress);
  return s0.tick;
}

async function getSqrtPrice(poolAddress) {
  const s0 = await slot0(poolAddress);
  return s0.sqrtPriceX96;
}



module.exports = {
  getUSDC,
  wrapEth,
  simulateSwaps,
  getTick,
  getSqrtPrice,
  getToken1AmountFromToken0,
};
