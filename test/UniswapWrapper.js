const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { network, ethers } = require("hardhat");

// const { hre } = require("hardhat");
const uniswapPoolAddress = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";

describe("UniswapWrapper", function () {
  async function buyUSDC() {}

  async function deployUniswapWrapperFixture() {
    const [owner] = await ethers.getSigners();

    const UniswapWrapper = await ethers.getContractFactory("UniswapWrapper");
    const uniswapWrapper = await UniswapWrapper.deploy(uniswapPoolAddress);

    return { uniswapWrapper, owner };
  }

  async function getUSDC(amount, addressTo) {
    const richGuyAddress = "0xcEe284F754E854890e311e3280b767F80797180d";
    const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const ERC20_ABI = [
      "function transfer(address who, uint amount) public",
      "function balanceOf(address) public view returns (uint)",
    ];

    // const addressTo = (await ethers.getSigner()).address;

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
    const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

    const WETH_ABI = [
      "function deposit() external payable",
      "function balanceOf(address owner) view returns (uint)",
      "function transfer(address to, uint256 value) external returns (bool)",
    ];

    const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, signer);
    const tx = await weth.deposit({ value: amountToWrap });
    await tx.wait();

    const transferTx = await weth.transfer(addressTo, amountToWrap);
    await transferTx.wait();
  }

  describe("Deployment", function () {
    it("Deploys in correct state", async () => {
      const { uniswapWrapper, owner } = await loadFixture(
        deployUniswapWrapperFixture
      );
      expect(await uniswapWrapper.uniswapPool()).to.equal(uniswapPoolAddress);
      expect((await uniswapWrapper.currentLiquidity()).toString()).to.equal(
        "0"
      );
    });
  });

  describe("Liquidity Management", function () {
    it("Allows initial deposit of liquidity", async () => {
      const { uniswapWrapper, owner } = await loadFixture(
        deployUniswapWrapperFixture
      );

      const amountUSDC = ethers.utils.parseUnits("1000", 6);
      const amountEth = ethers.utils.parseEther("1");

      await getUSDC(amountUSDC, uniswapWrapper.address);
      await wrapEth(amountEth, uniswapWrapper.address, owner);
      await uniswapWrapper.addLiquidity(amountUSDC, amountEth, 1000, 2000);

      const liquidity = await uniswapWrapper.currentLiquidity();
      expect(liquidity).to.be.greaterThan(amountUSDC);
    });

    it("Allows adding liquidity to existing position", async () => {
      const { uniswapWrapper, owner } = await loadFixture(
        deployUniswapWrapperFixture
      );
      //-------Make an initial position------------

      const amountUSDC = ethers.utils.parseUnits("1000", 6);
      const amountEth = ethers.utils.parseEther("1");

      await getUSDC(amountUSDC, uniswapWrapper.address);
      await wrapEth(amountEth, uniswapWrapper.address, owner);

      await uniswapWrapper.addLiquidity(amountUSDC, amountEth, 1000, 2000);
      const oldLiquidity = await uniswapWrapper.currentLiquidity();

      //get some more tokens, let's pentuple the size of our position
      const newAmountUSDC = amountUSDC.mul(5);
      const newAmountEth = amountEth.mul(5);
      await getUSDC(newAmountUSDC, uniswapWrapper.address);
      await wrapEth(newAmountEth, uniswapWrapper.address, owner);

      //---------Add liquidity in same tick range--------------------
      await uniswapWrapper.increaseLiquidity(newAmountUSDC, newAmountEth);

      const liquidity = await uniswapWrapper.currentLiquidity();

      expect(liquidity.div(oldLiquidity)).to.equal(5);
    });

    it("Allows redeployment of liquidity", async () => {
      const { uniswapWrapper, owner } = await loadFixture(
        deployUniswapWrapperFixture
      );
      //-------Make an initial position------------

      const amountUSDC = ethers.utils.parseUnits("10000", 6);
      const amountEth = ethers.utils.parseEther("5000");

      await getUSDC(amountUSDC, uniswapWrapper.address);
      await wrapEth(amountEth, uniswapWrapper.address, owner);
      await uniswapWrapper.addLiquidityAroundCurrentPrice(
        ethers.utils.parseUnits("100", 6)
      );

      tickLower = await uniswapWrapper.tickLower();
      tickUpper = await uniswapWrapper.tickUpper();

      await uniswapWrapper.redeployLiquidity(tickLower - 5, tickUpper - 5);
    });
  });
});
