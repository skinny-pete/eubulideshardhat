const hre = require("hardhat");

const { getToken1AmountFromToken0, getUSDC, wrapEth, simulateSwaps } = require("../test/utils")

async function main() {
    const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

    const ERC20_ABI = ["function transfer(address who, uint amount) public", "function approve(address spender, uint amount) public"]

    const [signer] = await hre.ethers.getSigners()



    const EubulidesCore = await hre.ethers.getContractFactory("EubulidesCore");
    const eubulidesCore = await EubulidesCore.deploy();

    await eubulidesCore.deployed();

    console.log("EubulidesCore deployed to:", eubulidesCore.address);

    const addPoolTx = await eubulidesCore.addPool(USDC_ADDRESS, WETH_ADDRESS, 500)



    // Wait for the transaction to be mined
    const receipt = await addPoolTx.wait();

    // Find the PoolAdded event in the transaction receipt
    const poolAddedEvent = receipt.events.find(event => event.event === 'PoolAdded');


    const poolAddress = poolAddedEvent.args[0];
    console.log("Pool Address:", poolAddress);

    const wrapperAddress = await eubulidesCore.getPool(USDC_ADDRESS, WETH_ADDRESS)
    console.log("Wrapper address: ", wrapperAddress)

    const wrapper = await ethers.getContractAt("UniswapWrapper", wrapperAddress)

    const usdc = await ethers.getContractAt(ERC20_ABI, USDC_ADDRESS)
    const weth = await ethers.getContractAt(ERC20_ABI, WETH_ADDRESS)

    const amount0 = ethers.utils.parseUnits("1000", 6)
    const amount1 = await getToken1AmountFromToken0(amount0, 6, 18, poolAddress)
    console.log("am1 is ", amount1)
    // const amount1 = ethers.utils.parseEther("5")

    // await getUSDC(amount0, signer.address)
    // await wrapEth(amount1, signer.address, signer)

    // await usdc.transfer(wrapperAddress, amount0)
    // console.log("usdc transferred")
    // await weth.transfer(wrapperAddress, amount1)
    // console.log("weth transferred")

    // await eubulidesCore.initialisePoolAtCurrentPrice(USDC_ADDRESS, WETH_ADDRESS,
    //     amount0
    // );

    // console.log("pool initialised")

    // await simulateSwaps()
    // await eubulidesCore.collectFees(USDC_ADDRESS, WETH_ADDRESS)

    // await simulateSwaps()
    // await eubulidesCore.collectFees(USDC_ADDRESS, WETH_ADDRESS)
    // console.log("quoting")
    // const wrapquote = await wrapper.quote(amount0, amount1, 2)
    // console.log('wrapwuote: ', wrapquote)

    // const quote = await eubulidesCore.quoteSingle(USDC_ADDRESS, WETH_ADDRESS, amount0, 2)
    // console.log("quote: ", quote)







    console.log(amount1)
    // const amount1 = await getToken1AmountFromToken0(amount0, 6, 18, "0xb31f693f8baF131C515607fF22c9b7bbBb757a04")







}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
