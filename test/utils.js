const { network, ethers } = require("hardhat");

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

module.exports = {
  getUSDC,
  wrapEth,
};
