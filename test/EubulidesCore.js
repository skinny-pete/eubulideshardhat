const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { network, ethers } = require("hardhat");

const { getUSDC, wrapEth } = require("./utils.js");

const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

const ERC20_ABI = [
  "function transfer(address to, uint256 value) external returns (bool)",
  "function balanceOf(address who) external view returns (uint)",
];

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
      //Let's give it loads of ETH so we don't have to do any ratio maths here
      //   console.log("transferring WETH");
      //   await WETHToken.transfer(wrapperAddress, ethers.utils.parseEther("1608"));
      //   console.log("transferred weth");
      const wrapper = await ethers.getContractAt(
        "UniswapWrapper",
        wrapperAddress
      );

      //   await hre.network.provider.request({
      //     method: "hardhat_impersonateAccount",
      //     params: [eubulidesCore.address],
      //   });

      //   coreSigner = await ethers.getSigner(eubulidesCore.address);

      //   impersonatedWrapper = wrapper.connect(coreSigner);

      //   impersonatedWrapper.addLiquidityAroundCurrentPrice(initialUSDC);
      //   console.log("test amount0", initialUSDC);

      expect(await wrapper.currentLiquidity()).to.equal(0);

      //   const estimatedGas =
      //     await eubulidesCore.estimateGas.initialisePoolAtCurrentPrice(
      //       USDC_ADDRESS,
      //       WETH_ADDRESS,
      //       initialUSDC
      //     );

      //   console.log("estimated gas: ", estimatedGas);

      await eubulidesCore.initialisePoolAtCurrentPrice(
        USDC_ADDRESS,
        WETH_ADDRESS,
        initialUSDC
      );

      expect(await wrapper.currentLiquidity()).to.be.greaterThan(0);
    });
  });

  describe("User Deposits", async () => {});

  describe("User Withdrawals", async () => {});

  describe("User Positions", async () => {});
});
