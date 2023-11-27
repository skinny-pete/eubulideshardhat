const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { network, ethers } = require("hardhat");

const {
  getUSDC,
  wrapEth,
  getTick,
  getToken1AmountFromToken0,
} = require("./utils.js");

const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

const ERC20_ABI = [
  "function transfer(address to, uint256 value) external returns (bool)",
  "function balanceOf(address who) external view returns (uint)",
  "function approve(address spender, uint amount) external",
];

async function setupInitialLiquidity(owner) {
  const initialUSDC = ethers.utils.parseUnits("1000", 6);
  await getUSDC(initialUSDC, owner.address);
  await wrapEth(ethers.utils.parseEther("1000"), owner.address, owner);
  return initialUSDC;
}

describe("EubulidesCore", function () {
  async function deployEubulidesCoreFixture() {
    const [owner] = await ethers.getSigners();

    const EubulidesCore = await ethers.getContractFactory("EubulidesCore");
    const eubulidesCore = await EubulidesCore.deploy();

    USDCToken = await ethers.getContractAt(ERC20_ABI, USDC_ADDRESS, owner);
    WETHToken = await ethers.getContractAt(ERC20_ABI, WETH_ADDRESS, owner);

    return { eubulidesCore, owner, USDCToken, WETHToken };
  }

  describe("Deployment", async () => {
    it("Should deploy without errors", async () => {
      const { eubulidesCore, owner } = await loadFixture(
        deployEubulidesCoreFixture
      );
      expect(eubulidesCore.address).to.be.properAddress;
    });
  });

  describe("Initialisation", async () => {
    it("Allow owner to add a new V3 USDC-ETH wrapper", async () => {
      const { eubulidesCore, owner } = await loadFixture(
        deployEubulidesCoreFixture
      );

      await eubulidesCore.addPool(USDC_ADDRESS, WETH_ADDRESS, 500);
      expect(
        await eubulidesCore.pools(USDC_ADDRESS, WETH_ADDRESS)
      ).to.not.equal(ethers.constants.AddressZero);
    });

    it("Allow owner to add a new V3 USDC-ETH wrapper and deposit liquidity", async () => {
      const { eubulidesCore, owner, USDCToken, WETHToken } = await loadFixture(
        deployEubulidesCoreFixture
      );

      await eubulidesCore.addPool(USDC_ADDRESS, WETH_ADDRESS, 500);

      const initialUSDC = ethers.utils.parseUnits("1000", 6); //USDC annoyingly uses 6 decimals

      //Let's get some liquidity to add
      await getUSDC(initialUSDC, owner.address);
      await wrapEth(ethers.utils.parseEther("1000"), owner.address, owner);

      //Let's just send it straight to the appropriate UniswapWrapper for the purposes of this test

      const wrapperAddress = await eubulidesCore.pools(
        USDC_ADDRESS,
        WETH_ADDRESS
      );

      await wrapEth(ethers.utils.parseEther("1000"), wrapperAddress, owner);

      await USDCToken.transfer(wrapperAddress, initialUSDC);
      const wrapper = await ethers.getContractAt(
        "UniswapWrapper",
        wrapperAddress
      );

      expect(await wrapper.currentLiquidity()).to.equal(0);

      await eubulidesCore.initialisePoolAtCurrentPrice(
        USDC_ADDRESS,
        WETH_ADDRESS,
        initialUSDC
      );

      expect(await wrapper.currentLiquidity()).to.be.greaterThan(0);
    });
  });

  async function makePoolCurrentPrice(eubulidesCore) {
    return poolAddress;
  }

  describe("User Deposits", async () => {
    it("accepts dual-sided deposits in the correct ratio", async () => {
      const { eubulidesCore, owner, USDCToken, WETHToken } = await loadFixture(
        deployEubulidesCoreFixture
      );

      await eubulidesCore.addPool(USDC_ADDRESS, WETH_ADDRESS, 500);

      const initialUSDC = ethers.utils.parseUnits("1000", 6); //USDC annoyingly uses 6 decimals

      //Let's get some liquidity to add
      await getUSDC(initialUSDC, owner.address);
      await wrapEth(ethers.utils.parseEther("1000"), owner.address, owner);

      //Let's just send it straight to the appropriate UniswapWrapper for the purposes of this test

      const wrapperAddress = await eubulidesCore.pools(
        USDC_ADDRESS,
        WETH_ADDRESS
      );

      await wrapEth(ethers.utils.parseEther("1000"), wrapperAddress, owner);

      await USDCToken.transfer(wrapperAddress, initialUSDC);
      const wrapper = await ethers.getContractAt(
        "UniswapWrapper",
        wrapperAddress
      );

      await eubulidesCore.initialisePoolAtCurrentPrice(
        USDC_ADDRESS,
        WETH_ADDRESS,
        initialUSDC
      );

      const poolAddress = await wrapper.uniswapPool();

      const amount0 = ethers.utils.parseUnits("10", 6);
      const amount1 = await getToken1AmountFromToken0(
        amount0,
        6,
        18,
        poolAddress
      );

      console.log("js amounts: ", amount0, amount1)

      await getUSDC(amount0, owner.address);
      await wrapEth(amount1, owner.address, owner);

      await USDCToken.approve(eubulidesCore.address, amount0);
      await WETHToken.approve(eubulidesCore.address, amount1);

      const duration = 1000;

      await eubulidesCore.deposit(
        USDC_ADDRESS,
        WETH_ADDRESS,
        amount0,
        amount1,
        owner.address,
        duration
      );

      const position = await eubulidesCore.getPosition(owner.address);
      expect(position[3]).to.equal(duration);
    });

    // it("Acceots a")
  });

  describe("User Withdrawals", () => {
    it("Allows a user to close a position", async () => {
      const { eubulidesCore, owner, USDCToken, WETHToken } = await loadFixture(
        deployEubulidesCoreFixture
      );

      await eubulidesCore.addPool(USDC_ADDRESS, WETH_ADDRESS, 500);

      const initialUSDC = ethers.utils.parseUnits("1000", 6); //USDC annoyingly uses 6 decimals

      //Let's get some liquidity to add
      await getUSDC(initialUSDC, owner.address);
      await wrapEth(ethers.utils.parseEther("1000"), owner.address, owner);

      //Let's just send it straight to the appropriate UniswapWrapper for the purposes of this test

      const wrapperAddress = await eubulidesCore.pools(
        USDC_ADDRESS,
        WETH_ADDRESS
      );

      await wrapEth(ethers.utils.parseEther("1000"), wrapperAddress, owner);

      await USDCToken.transfer(wrapperAddress, initialUSDC);
      const wrapper = await ethers.getContractAt(
        "UniswapWrapper",
        wrapperAddress
      );

      await eubulidesCore.initialisePoolAtCurrentPrice(
        USDC_ADDRESS,
        WETH_ADDRESS,
        initialUSDC
      );

      const poolAddress = await wrapper.uniswapPool();

      const amount0 = ethers.utils.parseUnits("10", 6);
      const amount1 = await getToken1AmountFromToken0(
        amount0,
        6,
        18,
        poolAddress
      );

      console.log("js amounts: ", amount0, amount1)

      await getUSDC(amount0, owner.address);
      await wrapEth(amount1, owner.address, owner);

      await USDCToken.approve(eubulidesCore.address, amount0);
      await WETHToken.approve(eubulidesCore.address, amount1);

      const duration = 1000;

      await eubulidesCore.deposit(
        USDC_ADDRESS,
        WETH_ADDRESS,
        amount0,
        amount1,
        owner.address,
        duration
      );

      const position = await eubulidesCore.getPosition(owner.address);
      console.log(position)

      await eubulidesCore.close()
    })
  });

  describe("User Positions", async () => { });
});
