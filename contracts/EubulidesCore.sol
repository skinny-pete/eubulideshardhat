// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "./UniswapWrapper.sol";
import "../interfaces/IUniswapWrapper.sol";

import "hardhat/console.sol";

contract EubulidesCore is Ownable, ERC20, ERC20Burnable {
    mapping(address => mapping(address => UniswapWrapper)) public pools;

    mapping(address => userPosition) userPositions;

    struct userPosition {
        uint256 liquidity;
        uint256 yieldEarned;
        uint256 timeStarted;
        uint256 duration;
        uint256 quote;
    }

    address public constant uniswapV3Factory =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    constructor() Ownable() ERC20("Eubulides Share Token", "EST") {}

    modifier onlyDepositRouter() {
        _;
    }
    modifier onlyTickSetter() {
        require(msg.sender == owner());
        _;
    }

    function addPool(
        address token0,
        address token1,
        uint24 fee
    ) public onlyOwner {
        address poolAddress = IUniswapV3Factory(uniswapV3Factory).getPool(
            token0,
            token1,
            fee
        );
        pools[token0][token1] = new UniswapWrapper(poolAddress);
    }

    function initialisePoolAtCurrentPrice(
        address token0,
        address token1,
        uint256 amount0
    ) external onlyOwner {
        console.log("initialising with this amount0", amount0);
        pools[token0][token1].addLiquidityAroundCurrentPrice(amount0);
    }

    function getYield(uint256 positionId) external view returns (uint256) {}

    function deposit(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        address depositor,
        uint duration
    ) external {
        require(
            userPositions[depositor].liquidity == 0,
            "already has position"
        );

        require(
            pools[token0][token1].uniswapPool() != address(0),
            "pool not added"
        );

        require(IERC20(token0).transferFrom(depositor, address(this), amount0));
        require(IERC20(token1).transferFrom(depositor, address(this), amount1));

        uint256 liquidity = 0;
        uint256 quote = 0; //TODO

        userPositions[depositor] = userPosition(
            liquidity,
            0,
            block.timestamp,
            duration,
            quote
        );
    }

    function compound() external onlyOwner {}

    function close(uint256 positionId) external onlyTickSetter {}

    function rebalance(
        int24 newTickLower,
        int24 newTickUpper
    ) external onlyTickSetter {}

    function setTickRange(
        int24 newTickLower,
        int24 newTickUpper
    ) external onlyTickSetter returns (bool success) {}

    function updateTickSetter(
        address newTickSetter
    ) external onlyOwner returns (bool success) {}
}
