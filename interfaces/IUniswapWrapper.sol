// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

interface IUniswapWrapper {
    function uniswapPool() external view returns (address);

    function positionManager() external view returns (address);

    function swapRouter() external view returns (address);

    function tokenId() external view returns (uint256);

    function currentLiquidity() external view returns (uint128);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function getToken1Amount(
        uint160 sqrtPriceX96,
        uint256 token0Amount
    ) external pure returns (uint256 token1Amount);

    function getScaledPrice(
        uint160 sqrtPriceX96
    ) external pure returns (uint256 price);

    function addLiquidityAroundCurrentPrice(uint256 amount0) external;

    function addLiquidity(
        uint256 amountA,
        uint256 amountB,
        int24 _tickLower,
        int24 _tickUpper
    ) external;

    function increaseLiquidity(uint256 amount0, uint256 amount1) external;

    function redeployLiquidity(
        int24 newTickLower,
        int24 newTickUpper
    ) external returns (bool success);
}
