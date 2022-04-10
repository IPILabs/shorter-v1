// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/ISRC20.sol";
import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./libraries/Path.sol";
import "./interfaces/IUSDT.sol";
import "./interfaces/IDexCenter.sol";
import "./interfaces/uniswapv2/IUniswapV2Factory.sol";
import "./interfaces/uniswapv2/IUniswapV2Pair.sol";
import "./interfaces/uniswapv2/IUniswapV2Router02.sol";
import "./interfaces/uniswapv3/IUniswapV3Factory.sol";
import "./interfaces/uniswapv3/IUniswapV3Pool.sol";
import "./interfaces/uniswapv3/IV3SwapRouter.sol";
import "./criteria/Affinity.sol";
import "./util/BoringMath.sol";

contract DexCenter is Affinity, IDexCenter {
    using BoringMath for uint256;
    using SafeToken for ISRC20;
    using Path for bytes;

    mapping(address => bool) public override entitledSwapRouters;
    mapping(address => bool) public override isSwapRouterV3;

    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    function sellShort(SellShortParams memory params) external returns (uint256 usdAmount) {
        address[] memory _path = params.path.getRouter();
        ISRC20 tokenIn = ISRC20(_path[0]);
        ISRC20 tokenOut = ISRC20(_path[_path.length - 1]);

        uint256 tokenInBal = tokenIn.balanceOf(address(this));
        uint256 tokenOutBal = tokenOut.balanceOf(params.to);
        uint256 allowance = tokenIn.allowance(address(this), params.swapRouter);
        if (allowance < params.amountIn) {
            tokenIn.approve(params.swapRouter, params.amountIn);
        }

        if (params.isSwapRouterV3) {
            usdAmount = _exactInput(params.amountIn, params.amountOutMin, params.swapRouter, params.to, params.path);
        } else {
            usdAmount = _swapExactTokensForTokens(params.amountIn, params.amountOutMin, params.swapRouter, params.to, _path);
        }

        uint256 tokenInAft = tokenIn.balanceOf(address(this));
        uint256 tokenOutAft = tokenOut.balanceOf(params.to);

        if (tokenInAft.add(params.amountIn) != tokenInBal || tokenOutBal.add(usdAmount) != tokenOutAft) {
            revert("Dex: sellShort failed");
        }
    }

    function buyCover(BuyCoverParams memory params) external returns (uint256 amountIn) {
        address[] memory _path = params.path.getRouter();
        (ISRC20 tokenIn, ISRC20 tokenOut) = params.isSwapRouterV3 ? (ISRC20(_path[_path.length - 1]), ISRC20(_path[0])) : (ISRC20(_path[0]), ISRC20(_path[_path.length - 1]));
        uint256 tokenInBal = tokenIn.balanceOf(address(this));
        uint256 tokenOutBal = tokenOut.balanceOf(params.to);
        uint256 allowance = ISRC20(address(tokenIn)).allowance(address(this), params.swapRouter);
        if (allowance < params.amountInMax) {
            if (params.isTetherToken) {
                _allowTetherToken(address(tokenIn), params.swapRouter, params.amountInMax);
            } else {
                tokenIn.approve(params.swapRouter, params.amountInMax);
            }
        }

        if (params.isSwapRouterV3) {
            amountIn = _exactOutput(params.amountOut, params.amountInMax, params.swapRouter, params.to, params.path);
        } else {
            amountIn = _swapTokensForExactTokens(params.amountOut, params.amountInMax, params.swapRouter, params.to, _path);
        }

        uint256 tokenInAft = tokenIn.balanceOf(address(this));
        uint256 tokenOutAft = tokenOut.balanceOf(params.to);

        if (tokenInAft.add(amountIn) != tokenInBal || tokenOutBal.add(params.amountOut) != tokenOutAft) {
            revert("Dex: buyCover failed");
        }
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address swapRouter,
        address to,
        address[] memory path
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = IUniswapV2Router02(swapRouter).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp);
        amountOut = amounts[amounts.length - 1];
    }

    function _swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address swapRouter,
        address to,
        address[] memory path
    ) internal returns (uint256 amountIn) {
        uint256[] memory amounts = IUniswapV2Router02(swapRouter).swapTokensForExactTokens(amountOut, amountInMax, path, to, block.timestamp);
        amountIn = amounts[0];
    }

    function _exactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address swapRouter,
        address to,
        bytes memory path
    ) internal returns (uint256 amountOut) {
        amountOut = IV3SwapRouter(swapRouter).exactInput(IV3SwapRouter.ExactInputParams({path: path, recipient: to, amountIn: amountIn, amountOutMinimum: amountOutMin}));
    }

    function _exactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address swapRouter,
        address to,
        bytes memory path
    ) internal returns (uint256 amountIn) {
        amountIn = IV3SwapRouter(swapRouter).exactOutput(IV3SwapRouter.ExactOutputParams({path: path, recipient: to, amountOut: amountOut, amountInMaximum: amountInMax}));
    }

    function getV2Price(address swapRouter, address[] memory path) external view override returns (uint256 price) {
        IUniswapV2Factory swapFactory = IUniswapV2Factory(IUniswapV2Router02(swapRouter).factory());

        price = 1e18;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address pairAddr = swapFactory.getPair(path[i], path[i + 1]);
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddr).getReserves();
            address tokenIn = IUniswapV2Pair(pairAddr).token0();
            uint256 tokenInDecimals = uint256(ISRC20(path[i]).decimals());
            uint256 tokenOutDecimals = uint256(ISRC20(path[i + 1]).decimals());
            uint256 _price = tokenIn == path[i] ? uint256(reserve1).mul(10**(tokenInDecimals.add(18).sub(tokenOutDecimals))).div(uint256(reserve0)) : uint256(reserve0).mul(10**(tokenInDecimals.add(18).sub(tokenOutDecimals))).div(uint256(reserve1));
            price = price.mul(_price).div(1e18);
        }
    }

    function getV3Price(
        address swapRouter,
        address[] memory path,
        uint24[] memory fees
    ) external view override returns (uint256 price) {
        IUniswapV3Factory swapFactory = IUniswapV3Factory(IV3SwapRouter(swapRouter).factory());
        price = 1e18;
        for (uint256 i = 0; i < fees.length; i++) {
            address poolAddr = swapFactory.getPool(path[i], path[i + 1], fees[i]);
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddr).slot0();
            address token0 = IUniswapV3Pool(poolAddr).token0();
            uint256 token0Decimals = uint256(ISRC20(token0).decimals());
            uint256 token1Decimals = path[i] == token0 ? uint256(ISRC20(path[i + 1]).decimals()) : uint256(ISRC20(path[i]).decimals());
            uint256 token0Price;
            uint256 sqrtDecimals = uint256(18).add(token0Decimals).sub(token1Decimals).div(2);
            if (sqrtDecimals.mul(2) == uint256(18).add(token0Decimals).sub(token1Decimals)) {
                uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10**sqrtDecimals).div(2**96);
                token0Price = sqrtPrice.mul(sqrtPrice);
            } else {
                uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10**(sqrtDecimals + 1)).div(2**96);
                token0Price = sqrtPrice.mul(sqrtPrice).div(10);
            }
            if (token0 == path[i]) {
                price = price.mul(token0Price).div(1e18);
            } else {
                price = price.mul(uint256(1e36).div(token0Price)).div(1e18);
            }
        }
    }

    function addEntitledSwapRouter(address[] memory newSwapRouters) external isKeeper {
        for (uint256 i = 0; i < newSwapRouters.length; i++) {
            entitledSwapRouters[newSwapRouters[i]] = true;
        }
    }

    function removeEntitledSwapRouter(address[] memory _swapRouters) external isKeeper {
        for (uint256 i = 0; i < _swapRouters.length; i++) {
            entitledSwapRouters[_swapRouters[i]] = false;
        }
    }

    function updateSwapRouterV3(address[] memory _swapRouters, bool _isSwapRouterV3) external isKeeper {
        for (uint256 i = 0; i < _swapRouters.length; i++) {
            isSwapRouterV3[_swapRouters[i]] = _isSwapRouterV3;
        }
    }
}
