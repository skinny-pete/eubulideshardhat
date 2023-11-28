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
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "hardhat/console.sol";

interface IUniswapV3PoolTokens {
    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

//A lot of this functionality, everything related to computing amounts should be moved to library at some point

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

    // uint token0Decimals;
    // uint token1Decimals;

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
        int24 tickLower;
        int24 tickUpper;
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
            tickLower: tickLower,
            tickUpper: tickUpper,
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

    function calculateLiquidity(
        uint256 amount0,
        uint256 amount1,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns (uint128 liquidity) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapPool)
            .slot0();

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            amount0,
            amount1
        );
        return liquidity;
    }

    function calculateAmounts(
        uint128 liquidity
    ) public view returns (uint amount0, uint amount1) {
        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(uniswapPool)
            .slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity
        );
    }

    // Calculate yield based on liquidity tokens and a specified period
    function _calculateQuote(
        uint256 liquidityTokens,
        uint256 periods
    ) internal view returns (uint256 yieldForToken0, uint256 yieldForToken1) {
        uint256 totalYield0 = 0;
        uint256 totalYield1 = 0;

        for (
            uint256 i = yieldHistory.length - periods;
            i < yieldHistory.length;
            i++
        ) {
            totalYield0 += yieldHistory[i].collected0;
            totalYield1 += yieldHistory[i].collected1;
        }

        yieldForToken0 =
            (liquidityTokens * totalYield0 * 10 ** 18) /
            (currentLiquidity);
        yieldForToken1 =
            (liquidityTokens * totalYield1 * 10 ** 18) /
            (currentLiquidity);

        console.log("calculate quote", yieldForToken0, yieldForToken1);

        return (yieldForToken0, yieldForToken1);
    }

    function quote(
        uint256 amount0,
        uint256 amount1,
        // int24 _tickLower,
        // int24 _tickUpper,
        uint256 periods
    ) public view returns (uint256 quote0, uint256 quote1) {
        // First, calculate the liquidity that would be received for the provided token amounts

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        uint128 liquidity = calculateLiquidity(
            amount0,
            amount1,
            currentTick - 5,
            currentTick + 5
        );

        // Then, use this liquidity to calculate the yield quote for each token
        (quote0, quote1) = _calculateQuote(liquidity, periods);

        return (quote0, quote1);
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

    function getYieldHistory(
        uint i
    ) public view returns (uint256, uint256, int24, int24, uint256) {
        YieldData memory out = yieldHistory[i];
        return (
            out.collected0,
            out.collected1,
            out.tickLower,
            out.tickUpper,
            out.timestamp
        );
    }

    // function collect() external onlyOwner {

    // }

    function getTickRange(
        address poolAddress
    ) internal view returns (int24 _tickLower, int24 _tickUpper) {
        (, int24 currentTick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();

        _tickLower = currentTick - 105;
        _tickUpper = currentTick + 35;

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
        int24 _tickLower, // tick corresponding to price_low
        int24 _tickUpper // tick corresponding to price_high
    ) public pure returns (uint256 y) {
        // Compute sqrt(price_low) and sqrt(price_high) from ticks
        uint160 sqrtPriceLow = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtPriceHigh = TickMath.getSqrtRatioAtTick(_tickUpper);

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
        console.log("liquidity returned is ", liquidity);

        tickLower = _tickLower;
        tickUpper = _tickUpper;

        return liquidity;
    }

    function collectFees() external onlyOwner returns (uint, uint) {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (uint256 collectedAmount0, uint256 collectedAmount1) = positionManager
            .collect(params);

        _addCollectedYield(collectedAmount0, collectedAmount1); //Add to list of yield checkpoints
        console.log("collecting fees", collectedAmount0, collectedAmount1);
        console.log(currentPosition, entriesAdded);
        return (collectedAmount0, collectedAmount1);
    }

    function increaseLiquidity(
        uint256 amount0,
        uint256 amount1
    ) public onlyOwner returns (uint) {
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

        currentLiquidity = positionLiquidity();
        // uint userLiq = liquidity - currentLiquidity;
        // console.log("userLiqstuff", currentLiquidity, liquidity, userLiq);

        return liquidity;
    }

    function positionLiquidity() internal view returns (uint128) {
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(
            tokenId
        );

        return liquidity;
    }

    // function redeployLiquidity(
    //     int24 newTickLower,
    //     int24 newTickUpper
    // ) external onlyOwner returns (bool success) {
    //     require(newTickLower < newTickUpper, "Ticks are set incorrectly");

    //     // 1. Remove liquidity from the current position
    //     (
    //         uint256 collectedAmount0,
    //         uint256 collectedAmount1
    //     ) = _removeLiquidity();

    //     // 2. Calculate desired amounts
    //     (
    //         uint256 desiredAmount0,
    //         uint256 desiredAmount1
    //     ) = _calculateDesiredAmounts(
    //             newTickLower,
    //             newTickUpper,
    //             collectedAmount0,
    //             collectedAmount1
    //         );

    //     // 3. Swap tokens if necessary
    //     _swapTokens(
    //         desiredAmount0,
    //         desiredAmount1,
    //         collectedAmount0,
    //         collectedAmount1
    //     );

    //     // 4. Add liquidity to the new tick range
    //     (uint256 newTokenId, uint128 liquidity) = _addLiquidityToNewRange(
    //         newTickLower,
    //         newTickUpper,
    //         desiredAmount0,
    //         desiredAmount1
    //     );

    //     // Update the new tokenId
    //     tokenId = newTokenId;
    //     currentLiquidity = liquidity;

    //     return true;
    // }

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

    function withdraw(uint128 amount) external onlyOwner returns (uint, uint) {
        return _removeLiquidity(amount);
    }

    // function _addLiquidityToNewRange(
    //     int24 newTickLower,
    //     int24 newTickUpper,
    //     uint256 desiredAmount0,
    //     uint256 desiredAmount1
    // ) internal returns (uint256 newTokenId, uint128 liquidity) {
    //     INonfungiblePositionManager.MintParams
    //         memory mintParams = INonfungiblePositionManager.MintParams({
    //             token0: IUniswapV3Pool(uniswapPool).token0(),
    //             token1: IUniswapV3Pool(uniswapPool).token1(),
    //             fee: IUniswapV3Pool(uniswapPool).fee(),
    //             tickLower: newTickLower,
    //             tickUpper: newTickUpper,
    //             amount0Desired: desiredAmount0,
    //             amount1Desired: desiredAmount1,
    //             amount0Min: 0,
    //             amount1Min: 0,
    //             recipient: address(this),
    //             deadline: block.timestamp + 1 hours
    //         });

    //     (newTokenId, liquidity, , ) = positionManager.mint(mintParams);
    //     return (newTokenId, liquidity);
    // }

    function _removeLiquidity(
        uint128 amount
    ) internal returns (uint256, uint256) {
        console.log("_removeLiquidity()", amount);
        console.log("currentLiq", currentLiquidity);
        console.log("positionLiquidity()", positionLiquidity());
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory decreaseParams = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: amount,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1 hours
                });

        (uint amount0, uint amount1) = positionManager.decreaseLiquidity(
            decreaseParams
        );

        // INonfungiblePositionManager.CollectParams
        //     memory collectParams = INonfungiblePositionManager.CollectParams({
        //         tokenId: tokenId,
        //         recipient: address(this),
        //         amount0Max: type(uint128).max,
        //         amount1Max: type(uint128).max
        //     });

        // (uint256 collectedAmount0, uint256 collectedAmount1) = positionManager
        //     .collect(collectParams);

        IUniswapV3Pool pool = IUniswapV3Pool(uniswapPool);
        console.log("withdrawing ", amount0, amount1);
        IERC20(pool.token0()).transfer(msg.sender, amount0);
        IERC20(pool.token1()).transfer(msg.sender, amount1);

        return (amount0, amount1);
    }
}
