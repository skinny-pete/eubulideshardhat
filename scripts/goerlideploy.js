const hre = require("hardhat");

async function main() {
    const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";



    const EubulidesCore = await hre.ethers.getContractFactory("EubulidesCore");
    const eubulidesCore = await EubulidesCore.deploy();

    await eubulidesCore.deployed();

    console.log("EubulidesCore deployed to:", eubulidesCore.address);

    const addPoolTx = await eubulidesCore.addPool(USDC_ADDRESS, WETH_ADDRESS, 500)



    // Wait for the transaction to be mined
    const receipt = await addPoolTx.wait();

    // Find the PoolAdded event in the transaction receipt
    const poolAddedEvent = receipt.events.find(event => event.event === 'PoolAdded');

    // Access the address from the event
    if (poolAddedEvent) {
        const poolAddress = poolAddedEvent.args[0];
        console.log("Pool Address:", poolAddress);
    }




}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
