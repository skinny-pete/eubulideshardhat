// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UserDepositRouter {
    constructor() {}

    function getRatio() internal view returns (uint nom, uint denom) {}

    function deposit(
        address token,
        uint256 amount
    ) external returns (uint256 positionId) {}

    function coreDeposit(
        uint amount,
        address depositor
    ) internal returns (uint256 positionId) {}
}
