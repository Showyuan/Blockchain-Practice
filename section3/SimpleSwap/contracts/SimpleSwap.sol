// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    using SafeMath for uint;

    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint256 private _totalSupply;

    // Implement core logic here
    constructor(address tokenA, address tokenB) ERC20("SimpleSwap", "SimpleSwap"){
        require(Address.isContract(tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(Address.isContract(tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(tokenA != tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");

        (token0, token1) = uint160(tokenA) < uint160(tokenB)? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut){ 
        
        // check input value
        require(tokenIn == address(token0) || tokenIn == address(token1), "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == address(token0) || tokenOut == address(token1), "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // calculate amountOut
        uint256 k = uint(reserve0).mul(reserve1) - 1;
        if (tokenIn == address(token0)) {
            amountOut = reserve1 - (k / (uint(reserve0).add(amountIn)) + 1);
            // update reserve0 & reserve1
            reserve0 += uint112(amountIn);
            reserve1 -= uint112(amountOut);
        } else {
            amountOut = reserve0 - (k / (uint(reserve1).add(amountIn)) + 1);
            // update reserve0 & reserve1
            reserve0 -= uint112(amountOut);
            reserve1 += uint112(amountIn);
        }

        // transfer from msg.sender tokenIn to pool
        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        // transfer tokenOut from pool to msg.sender
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        ){ 
            // check input value
            require(amountAIn > 0, 'SimpleSwap: INSUFFICIENT_INPUT_AMOUNT');
            require(amountBIn > 0, 'SimpleSwap: INSUFFICIENT_INPUT_AMOUNT');

            // calculate amountA & amountB
            if (reserve0 == 0 && reserve1 == 0) {
                (amountA, amountB) = (amountAIn, amountBIn);
            } else {
                uint amountBOptimal = _quote(amountAIn, reserve0, reserve1);
                if (amountBOptimal <= amountBIn) {
                    require(amountBOptimal >= 0, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
                    (amountA, amountB) = (amountAIn, amountBOptimal);
                } else {
                    uint amountAOptimal = _quote(amountBIn, reserve1, reserve0);
                    assert(amountAOptimal <= amountAIn);
                    require(amountAOptimal >= 0, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
                    (amountA, amountB) = (amountAOptimal, amountBIn);
                }
            }

            // safeTransferFrom 
            _safeTransferFrom(token0, msg.sender, address(this), amountA);
            _safeTransferFrom(token1, msg.sender, address(this), amountB);
            
            // mint LP Token
            uint balance0 = IERC20(token0).balanceOf(address(this));
            uint balance1 = IERC20(token1).balanceOf(address(this));
            uint amount0 = balance0.sub(reserve0);
            uint amount1 = balance1.sub(reserve1);
            _totalSupply = totalSupply();
            if (_totalSupply == 0) {
                liquidity = Math.sqrt(amount0.mul(amount1));
            } else {
                liquidity = Math.min(amount0.mul(_totalSupply) / reserve0, amount1.mul(_totalSupply) / reserve1);
            }
            require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
            _mint(msg.sender, liquidity);

            // update reserve0 & reserve1
            reserve0 = uint112(balance0);
            reserve1 = uint112(balance1);

            // emit event
            emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
        }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB){
        // transfer liquidity to contract
        IERC20(address(this)).transferFrom(msg.sender, address(this), liquidity);

        // burn liquidity
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        _totalSupply = totalSupply();
        amountA = liquidity.mul(balance0) / (_totalSupply);
        amountB = liquidity.mul(balance1) / (_totalSupply);
        require(amountA > 0 && amountB > 0, 'SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        IERC20(address(token0)).transfer(msg.sender,amountA);
        IERC20(address(token1)).transfer(msg.sender,amountB);

        // update reserve0 & reserve1
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
        emit Transfer(address(this), address(0), liquidity);
    }

    /// @notice Get the reserves of the pool
    /// @return reserveA The reserve of tokenA
    /// @return reserveB The reserve of tokenB
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB){
        reserveA = reserve0;
        reserveB = reserve1;
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view returns (address tokenA){ 
        tokenA = token0;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view returns (address tokenB){ 
        tokenB = token1;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)"))), to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SimpleSwap: TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, address from, address to, uint value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256(bytes('transferFrom(address,address,uint256)'))), from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SimpleSwap: TRANSFER_FAILED');
        emit Transfer(from, to, value);
    }

    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'SimpleSwap: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'SimpleSwap: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }
}