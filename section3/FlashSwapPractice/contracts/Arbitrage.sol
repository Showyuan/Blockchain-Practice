// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { console } from "forge-std/console.sol";

// This is a pracitce contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address borrowPool;
        address targetSwapPool;
        address borrowToken;
        address debtToken;
        uint256 borrowAmount;
        uint256 debtAmount;
        uint256 debtAmountOut;
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        // 3. decode callback data
        CallbackData memory callbackdata = abi.decode(data, (CallbackData));

        // 4. swap WETH to USDC
        require(IERC20(callbackdata.borrowToken).transfer(
            callbackdata.targetSwapPool, callbackdata.debtAmount), "pay pool2 failed!");
        IUniswapV2Pair(callbackdata.targetSwapPool).swap(
            0, callbackdata.debtAmountOut, address(this), new bytes(0));
            
        // 5. repay USDC to lower price pool
        require(IERC20(callbackdata.debtToken).transfer(callbackdata.borrowPool, callbackdata.borrowAmount), "repay failed!");
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    // 先完成這個，再flashswap，執行，然後還款，Struct可以自定
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // 1. finish callbackData
        // 從 priceLowerPool 可以換到的USDC
        (uint112 _reserve0L, uint112 _reserve1L,) = IUniswapV2Pair(priceLowerPool).getReserves();
        uint256 lowerUSDC = _getAmountIn(
            borrowETH, _reserve1L, _reserve0L);
        // 從 priceHigherPool 可以換到的USDC
        (uint112 _reserve0H, uint112 _reserve1H,) = IUniswapV2Pair(priceHigherPool).getReserves();
        uint256 higherUSDC = _getAmountOut(
            borrowETH, _reserve0H, _reserve1H);

        CallbackData memory callbackData;
        callbackData.borrowPool = priceLowerPool;
        callbackData.targetSwapPool = priceHigherPool;                       // higher pool
        callbackData.borrowAmount = lowerUSDC;                               // 預計要還的 USDC
        callbackData.borrowToken = IUniswapV2Pair(priceLowerPool).token0();  // WETH
        callbackData.debtToken = IUniswapV2Pair(priceLowerPool).token1();    // USDC
        callbackData.debtAmount = borrowETH;                                 // 在 higher pool 的 amountIn
        callbackData.debtAmountOut = higherUSDC;                             // 在 higher pool 的 amountOut

        // 2. flash swap (borrow WETH from lower price pool)
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
