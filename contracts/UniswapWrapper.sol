// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "hardhat/console.sol";

interface IUniswapV3PoolTokens {
    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract UniswapWrapper is Ownable {
    address public uniswapPool;
    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;
    uint256 public tokenId;
    address constant nonFungiblePositionManagerAddress =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant swapRouterAddress =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint128 public currentLiquidity;

    int24 public tickLower;
    int24 public tickUpper;

    constructor(address _uniswapPool) Ownable() {
        uniswapPool = _uniswapPool;
        positionManager = INonfungiblePositionManager(
            nonFungiblePositionManagerAddress
        );
        swapRouter = ISwapRouter(swapRouterAddress);
    }

    uint256 public constant HISTORY_SIZE = 16; // Size of the moving history. Adjust as needed.

    struct YieldData {
        uint256 collected0;
        uint256 collected1;
        uint256 timestamp;
    }

    // An array to keep track of the collected yields using the YieldData struct.
    YieldData[HISTORY_SIZE] public yieldHistory;

    // A pointer to the current position in the yieldHistory array.
    uint256 public currentPosition = 0;

    // A counter to track the number of yield data entries added.
    uint256 public entriesAdded = 0;

    /**
     * @dev Add a collected yield data to the moving history.
     * @param _collected0 The amount of yield collected for token0.
     * @param _collected1 The amount of yield collected for token1.
     */
    function _addCollectedYield(
        uint256 _collected0,
        uint256 _collected1
    ) internal {
        YieldData memory newData = YieldData({
            collected0: _collected0,
            collected1: _collected1,
            timestamp: block.timestamp
        });

        if (entriesAdded < HISTORY_SIZE) {
            yieldHistory[entriesAdded] = newData;
            entriesAdded++;
        } else {
            yieldHistory[currentPosition] = newData;
            currentPosition = (currentPosition + 1) % HISTORY_SIZE;
        }
    }

    /**
     * @dev Get the last N collected yield data entries.
     * @return An array of the last N (or fewer if not enough data points) collected yield data entries.
     */
    function _getLastNCollectedYields()
        internal
        view
        returns (YieldData[] memory)
    {
        YieldData[] memory result = new YieldData[](entriesAdded);

        for (uint256 i = 0; i < entriesAdded; i++) {
            uint256 pos = (currentPosition + HISTORY_SIZE - entriesAdded + i) %
                HISTORY_SIZE;
            result[i] = yieldHistory[pos];
        }

        return result;
    }

    function DEV_getLastNCollectedYields()
        public
        view
        returns (YieldData[] memory)
    {
        return _getLastNCollectedYields();
    }

    // function collect() external onlyOwner {

    // }

    function getTickRange(
        address poolAddress
    ) internal view returns (int24 _tickLower, int24 _tickUpper) {
        (, int24 currentTick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();

        _tickLower = currentTick - 5;
        _tickUpper = currentTick + 5;

        return (_tickLower, _tickUpper);
    }

    function getTokens() public view returns (address token0, address token1) {
        return (
            IUniswapV3Pool(uniswapPool).token0(),
            IUniswapV3Pool(uniswapPool).token1()
        );
    }

    function getTokenDecimals(
        IUniswapV3PoolTokens pool
    ) public view returns (uint8 decimalsToken0, uint8 decimalsToken1) {
        address token0Address = pool.token0();
        address token1Address = pool.token1();

        decimalsToken0 = IERC20Decimals(token0Address).decimals();
        decimalsToken1 = IERC20Decimals(token1Address).decimals();

        return (decimalsToken0, decimalsToken1);
    }

    function getToken1Amount(
        uint160 sqrtPriceX96,
        uint256 token0Amount
    ) public view returns (uint256 token1Amount) {
        uint256 price = getScaledPrice(
            sqrtPriceX96,
            IUniswapV3PoolTokens(uniswapPool)
        );
        token1Amount = (token0Amount * 1e18) / price; // Assuming the result is to be in 18 decimals
    }

    function computeToken1Amount(
        uint256 x, // amount of token0
        uint160 sqrtPrice, // current sqrt price
        int24 tickLower, // tick corresponding to price_low
        int24 tickUpper // tick corresponding to price_high
    ) internal pure returns (uint256 y) {
        // Compute sqrt(price_low) and sqrt(price_high) from ticks
        uint160 sqrtPriceLow = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceHigh = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate Liquidity_x
        uint256 liquidityX = FullMath.mulDiv(
            x,
            FullMath.mulDiv(sqrtPrice, sqrtPriceHigh, 1 << 96),
            sqrtPriceHigh - sqrtPrice
        );

        // Calculate y
        y = FullMath.mulDiv(
            liquidityX,
            sqrtPrice - sqrtPriceLow,
            1 << 96 // This is used to adjust for the fixed point math used in sqrtPrice
        );

        return y;
    }

    // Function to calculate the price from sqrtPriceX96
    function getScaledPrice(
        uint160 sqrtPriceX96,
        IUniswapV3PoolTokens pool
    ) public view returns (uint256 price) {
        uint256 priceUnscaled = (uint256(sqrtPriceX96) * sqrtPriceX96) >> 96;

        // Get decimals for the tokens
        (uint8 decimalsToken0, uint8 decimalsToken1) = getTokenDecimals(pool);

        // Adjust the price based on token decimals
        if (decimalsToken0 > decimalsToken1) {
            price =
                priceUnscaled /
                (10 ** uint256(decimalsToken0 - decimalsToken1));
        } else if (decimalsToken0 < decimalsToken1) {
            price =
                priceUnscaled *
                (10 ** uint256(decimalsToken1 - decimalsToken0));
        } else {
            price = priceUnscaled;
        }

        return price;
    }

    function addLiquidityAroundCurrentPrice(
        uint256 amount0
    ) external onlyOwner {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapPool)
            .slot0();

        // uint256 amount1 = getToken1Amount(sqrtPriceX96, amount0);
        (int24 _tickLower, int24 _tickUpper) = getTickRange(uniswapPool);
        uint256 amount1 = computeToken1Amount(
            amount0,
            sqrtPriceX96,
            _tickLower,
            _tickUpper
        );

        _addLiquidity(amount0, amount1, _tickLower, _tickUpper);
    }

    function addLiquidity(
        //For initial position setup
        uint256 amountA,
        uint256 amountB,
        int24 _tickLower,
        int24 _tickUpper
    ) external onlyOwner {
        _addLiquidity(amountA, amountB, _tickLower, _tickUpper);
    }

    function _addLiquidity(
        uint256 amount0,
        uint256 amount1,
        int24 _tickLower,
        int24 _tickUpper
    ) internal returns (uint128 newLiquidity) {
        require(_tickLower < _tickUpper, "Ticks are set incorrectly");
        require(
            IERC20(IUniswapV3Pool(uniswapPool).token0()).balanceOf(
                address(this)
            ) >= amount0,
            "insufficient token0"
        );
        require(
            IERC20(IUniswapV3Pool(uniswapPool).token1()).balanceOf(
                address(this)
            ) >= amount1,
            "insufficient token1"
        );
        // Approve the position manager to spend the tokens
        require(
            IERC20(IUniswapV3Pool(uniswapPool).token0()).approve(
                nonFungiblePositionManagerAddress,
                amount0
            ),
            "wrapper approval token0 failed"
        );
        require(
            IERC20(IUniswapV3Pool(uniswapPool).token1()).approve(
                nonFungiblePositionManagerAddress,
                amount1
            ),
            "wrapper approval token1 failed"
        );

        // (int24 calcTickLower, int24 calcTickHigher) = getTickRange(uniswapPool);

        // (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapPool)
        //     .slot0();

        // uint amount1 = getToken1Amount(sqrtPriceX96, amountA);

        INonfungiblePositionManager.MintParams
            memory mintParams = INonfungiblePositionManager.MintParams({
                token0: IUniswapV3Pool(uniswapPool).token0(),
                token1: IUniswapV3Pool(uniswapPool).token1(),
                fee: IUniswapV3Pool(uniswapPool).fee(),
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            });

        (uint256 newTokenId, uint128 liquidity, , ) = positionManager.mint(
            mintParams
        );

        tokenId = newTokenId;
        currentLiquidity = liquidity;

        tickLower = _tickLower;
        tickUpper = _tickUpper;

        return liquidity;
    }

    function collectFees() external onlyOwner returns (uint, uint) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
            .CollectParams({
                tokenId: tokenId,
                recipient: address(this), // Collect fees to this contract, change as desired
                amount0Max: type(uint128).max, // Collect all available fees
                amount1Max: type(uint128).max // Collect all available fees
            });

        (uint256 collectedAmount0, uint256 collectedAmount1) = positionManager
            .collect(params);

        _addCollectedYield(collectedAmount0, collectedAmount1); //Add to list of yield checkpointsd
        return (collectedAmount0, collectedAmount1);
    }

    function increaseLiquidity(
        uint256 amount0,
        uint256 amount1
    ) public onlyOwner {
        IERC20(IUniswapV3Pool(uniswapPool).token0()).approve(
            nonFungiblePositionManagerAddress,
            amount0
        );
        IERC20(IUniswapV3Pool(uniswapPool).token1()).approve(
            nonFungiblePositionManagerAddress,
            amount1
        );

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParams = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1 hours
                });

        (uint128 liquidity, , ) = positionManager.increaseLiquidity(
            increaseLiquidityParams
        );

        currentLiquidity = liquidity;
    }

    function positionLiquidity() internal view returns (uint128) {
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(
            tokenId
        );

        return liquidity;
    }

    function redeployLiquidity(
        int24 newTickLower,
        int24 newTickUpper
    ) external onlyOwner returns (bool success) {
        require(newTickLower < newTickUpper, "Ticks are set incorrectly");

        // 1. Remove liquidity from the current position
        (
            uint256 collectedAmount0,
            uint256 collectedAmount1
        ) = _removeLiquidity();

        // 2. Calculate desired amounts
        (
            uint256 desiredAmount0,
            uint256 desiredAmount1
        ) = _calculateDesiredAmounts(
                newTickLower,
                newTickUpper,
                collectedAmount0,
                collectedAmount1
            );

        // 3. Swap tokens if necessary
        _swapTokens(
            desiredAmount0,
            desiredAmount1,
            collectedAmount0,
            collectedAmount1
        );

        // 4. Add liquidity to the new tick range
        (uint256 newTokenId, uint128 liquidity) = _addLiquidityToNewRange(
            newTickLower,
            newTickUpper,
            desiredAmount0,
            desiredAmount1
        );

        // Update the new tokenId
        tokenId = newTokenId;
        currentLiquidity = liquidity;

        return true;
    }

    function _calculateDesiredAmounts(
        int24 newTickLower,
        int24 newTickUpper,
        uint256 collectedAmount0,
        uint256 collectedAmount1
    ) internal pure returns (uint256 desiredAmount0, uint256 desiredAmount1) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(newTickLower);
        uint160 avgSqrtPriceX96 = (sqrtPriceLowerX96 +
            TickMath.getSqrtRatioAtTick(newTickUpper)) / 2;

        uint256 R = FullMath.mulDiv(uint256(avgSqrtPriceX96), 1e12, 1 << 96);

        desiredAmount0 = FullMath.mulDiv(
            collectedAmount0 + FullMath.mulDiv(collectedAmount1, R, 1e12),
            1e12,
            1e12 + R
        );
        desiredAmount1 = FullMath.mulDiv(
            collectedAmount1 + FullMath.mulDiv(collectedAmount0, 1e12, R),
            1e12,
            R + 1e12
        );

        return (desiredAmount0, desiredAmount1);
    }

    function _swapTokens(
        uint256 desiredAmount0,
        uint256 desiredAmount1,
        uint256 collectedAmount0,
        uint256 collectedAmount1
    ) internal {
        uint256 amount0ToSwap = (collectedAmount0 > desiredAmount0)
            ? collectedAmount0 - desiredAmount0
            : 0;
        uint256 amount1ToSwap = (collectedAmount1 > desiredAmount1)
            ? collectedAmount1 - desiredAmount1
            : 0;

        if (amount0ToSwap > 0 || amount1ToSwap > 0) {
            address token0 = IUniswapV3Pool(uniswapPool).token0();
            address token1 = IUniswapV3Pool(uniswapPool).token1();

            if (amount0ToSwap > 0) {
                IERC20(token0).approve(swapRouterAddress, amount0ToSwap);
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: token0,
                        tokenOut: token1,
                        fee: IUniswapV3Pool(uniswapPool).fee(),
                        recipient: address(this),
                        deadline: block.timestamp + 15 minutes,
                        amountIn: amount0ToSwap,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                swapRouter.exactInputSingle(params);
            } else if (amount1ToSwap > 0) {
                IERC20(token1).approve(swapRouterAddress, amount1ToSwap);
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: token1,
                        tokenOut: token0,
                        fee: IUniswapV3Pool(uniswapPool).fee(),
                        recipient: address(this),
                        deadline: block.timestamp + 15 minutes,
                        amountIn: amount1ToSwap,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                swapRouter.exactInputSingle(params);
            }
        }
    }

    function _addLiquidityToNewRange(
        int24 newTickLower,
        int24 newTickUpper,
        uint256 desiredAmount0,
        uint256 desiredAmount1
    ) internal returns (uint256 newTokenId, uint128 liquidity) {
        INonfungiblePositionManager.MintParams
            memory mintParams = INonfungiblePositionManager.MintParams({
                token0: IUniswapV3Pool(uniswapPool).token0(),
                token1: IUniswapV3Pool(uniswapPool).token1(),
                fee: IUniswapV3Pool(uniswapPool).fee(),
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                amount0Desired: desiredAmount0,
                amount1Desired: desiredAmount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            });

        (newTokenId, liquidity, , ) = positionManager.mint(mintParams);
        return (newTokenId, liquidity);
    }

    function _removeLiquidity() internal returns (uint256, uint256) {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory decreaseParams = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: positionLiquidity(), // removing all liquidity
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1 hours
                });

        positionManager.decreaseLiquidity(decreaseParams);

        INonfungiblePositionManager.CollectParams
            memory collectParams = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (uint256 collectedAmount0, uint256 collectedAmount1) = positionManager
            .collect(collectParams);

        return (collectedAmount0, collectedAmount1);
    }
}
