// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "./UniswapWrapper.sol";
import "../interfaces/IUniswapWrapper.sol";

import "hardhat/console.sol";

contract EubulidesCore is Ownable, ERC20, ERC20Burnable {
    event PoolAdded(
        address indexed poolAddress,
        address token0,
        address token1
    );

    mapping(address => mapping(address => UniswapWrapper)) public pools;

    mapping(address => userPosition) userPositions;

    struct userPosition {
        uint128 liquidity;
        uint256 yieldEarned;
        uint256 timeStarted;
        uint256 duration;
        uint256 quote0;
        uint256 quote1;
        address token0;
        address token1;
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
    ) public onlyOwner returns (address) {
        address poolAddress = IUniswapV3Factory(uniswapV3Factory).getPool(
            token0,
            token1,
            fee
        );
        pools[token0][token1] = new UniswapWrapper(poolAddress);

        emit PoolAdded(address(pools[token0][token1]), token0, token1);

        return address(pools[token0][token1]);
    }

    function initialisePoolAtCurrentPrice(
        address token0,
        address token1,
        uint256 amount0
    ) external onlyOwner {
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

        require(
            IERC20(token0).transferFrom(
                depositor,
                address(pools[token0][token1]),
                amount0
            )
        );
        require(
            IERC20(token1).transferFrom(
                depositor,
                address(pools[token0][token1]),
                amount1
            )
        );

        (uint quote0, uint quote1) = IUniswapWrapper(
            address(pools[token0][token1])
        ).quote(amount0, amount1, duration);

        // console.log(address(pools[token0][token1]));
        // console.log("core quotes ", quote0, quote1);

        uint128 liquidity = IUniswapWrapper(address(pools[token0][token1]))
            .increaseLiquidity(amount0, amount1);
        userPositions[depositor] = userPosition(
            liquidity,
            0,
            block.timestamp,
            duration,
            quote0,
            quote1,
            token0,
            token1
        );
    }

    function getPosition(
        address who
    )
        public
        view
        returns (uint, uint, uint, uint, uint, uint, address, address)
    {
        userPosition memory pos = userPositions[who];

        return (
            pos.liquidity,
            pos.yieldEarned,
            pos.timeStarted,
            pos.duration,
            pos.quote0,
            pos.quote1,
            pos.token0,
            pos.token1
        );
    }

    function compound() external onlyOwner {}

    function close() external onlyTickSetter {
        userPosition memory pos = userPositions[msg.sender];
        uint total0 = 0;
        uint total1 = 0;
        (uint amount0, uint amount1) = IUniswapWrapper(
            address(pools[pos.token0][pos.token1])
        ).calculateAmounts(pos.liquidity);
        if (block.timestamp >= pos.timeStarted + pos.duration) {
            total0 = amount0 + pos.quote0;
            total1 = amount1 + pos.quote1;
        } else {
            total0 = amount0;
            total1 = amount1;
        }
    }

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
