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

    mapping(address => bool) public override getSwapRouterWhiteList;
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
            tokenIn.approve(params.swapRouter, params.amountIn.sub(allowance));
        }

        if (params.isSwapRouterV3) {
            usdAmount = exactInput(params.amountIn, params.amountOutMin, params.swapRouter, params.to, params.path);
        } else {
            usdAmount = swapExactTokensForTokens(params.amountIn, params.amountOutMin, params.swapRouter, params.to, _path);
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
                tokenIn.approve(params.swapRouter, params.amountInMax.sub(allowance));
            }
        }

        if (params.isSwapRouterV3) {
            amountIn = exactOutput(params.amountOut, params.amountInMax, params.swapRouter, params.to, params.path);
        } else {
            amountIn = swapTokensForExactTokens(params.amountOut, params.amountInMax, params.swapRouter, params.to, _path);
        }

        uint256 tokenInAft = tokenIn.balanceOf(address(this));
        uint256 tokenOutAft = tokenOut.balanceOf(params.to);

        if (tokenInAft.add(amountIn) != tokenInBal || tokenOutBal.add(params.amountOut) != tokenOutAft) {
            revert("Dex: buyCover failed");
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address swapRouter,
        address to,
        address[] memory path
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = IUniswapV2Router02(swapRouter).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp);
        amountOut = amounts[amounts.length - 1];
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address swapRouter,
        address to,
        address[] memory path
    ) internal returns (uint256 amountIn) {
        uint256[] memory amounts = IUniswapV2Router02(swapRouter).swapTokensForExactTokens(amountOut, amountInMax, path, to, block.timestamp);
        amountIn = amounts[0];
    }

    function exactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address swapRouter,
        address to,
        bytes memory path
    ) internal returns (uint256 amountOut) {
        amountOut = IV3SwapRouter(swapRouter).exactInput(IV3SwapRouter.ExactInputParams({path: path, recipient: to, amountIn: amountIn, amountOutMinimum: amountOutMin}));
    }

    function exactOutput(
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
            address tokenIn = IUniswapV3Pool(poolAddr).token0();
            uint256 tokenInDecimals = uint256(ISRC20(path[i]).decimals());
            uint256 tokenOutDecimals = uint256(ISRC20(path[i + 1]).decimals());
            if (tokenIn == path[i]) {
                uint256 sqrtDecimals = (uint256(19).add(tokenInDecimals).sub(tokenOutDecimals)).div(2);
                uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10**sqrtDecimals).div(2**96);
                price = sqrtDecimals.mul(2) == uint256(19).add(tokenInDecimals).sub(tokenOutDecimals) ? sqrtPrice.mul(sqrtPrice).mul(price).div(1e19) : sqrtPrice.mul(sqrtPrice).mul(price).div(1e18);
            } else {
                uint256 sqrtDecimals = (uint256(19).add(tokenOutDecimals).sub(tokenInDecimals)).div(2);
                uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10**sqrtDecimals).div(2**96);
                uint256 _price = sqrtDecimals.mul(2) == uint256(19).add(tokenOutDecimals).sub(tokenInDecimals) ? sqrtPrice.mul(sqrtPrice).div(10) : sqrtPrice.mul(sqrtPrice);
                _price = uint256(1e36).div(_price);
                price = price.mul(_price).div(1e18);
            }
        }
    }

    function setSwapRouterWhiteList(address _swapRouter, bool _flag) external isManager {
        getSwapRouterWhiteList[_swapRouter] = _flag;
    }

    function addSwapRouterWhiteList(address _swapRouter, bool _isSwapRouterV3) external isManager {
        getSwapRouterWhiteList[_swapRouter] = true;
        isSwapRouterV3[_swapRouter] = _isSwapRouterV3;
    }
}
