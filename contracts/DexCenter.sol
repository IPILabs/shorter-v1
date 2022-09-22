// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/ISRC20.sol";
import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./libraries/Path.sol";
import "./libraries/TickMath.sol";
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

    uint256 public twapInterval = 60;
    mapping(address => bool) public override entitledSwapRouters;
    mapping(address => bool) public override isSwapRouterV3;
    mapping(address => bool) public isMiddleToken;

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

    function _exactOutput(
        uint256 amountOut,
        uint256 amountInMax,
        address swapRouter,
        address to,
        bytes memory path
    ) internal returns (uint256 amountIn) {
        amountIn = IV3SwapRouter(swapRouter).exactOutput(IV3SwapRouter.ExactOutputParams({path: path, recipient: to, amountOut: amountOut, amountInMaximum: amountInMax}));
    }

    function getTokenPrice(
        address swapRouter,
        address[] memory path,
        uint24[] memory fees
    ) external view override returns (uint256 price) {
        require(isSwapRouterV3[swapRouter], "Dex: Invalid swapRouter");
        IUniswapV3Factory swapFactory = IUniswapV3Factory(IV3SwapRouter(swapRouter).factory());
        price = 1e18;
        for (uint256 i = 0; i < fees.length; i++) {
            address poolAddr = swapFactory.getPool(path[i], path[i + 1], fees[i]);
            uint160 sqrtPriceX96 = _getSqrtTWAP(poolAddr);
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

    function checkPath(
        address token0,
        address token1,
        address swapRouter,
        bool isSell,
        bytes memory path
    ) external override {
        address[] memory _path = path.getRouter();
        uint256 pathSize = _path.length;
        require(pathSize >= 2 && pathSize < 5, "Dex: Invaild path");
        if (isSell || isSwapRouterV3[swapRouter]) {
            require(_path[0] == token0 && _path[pathSize.sub(1)] == token1, "Dex: Invaild path");
        } else {
            require(_path[0] == token1 && _path[pathSize.sub(1)] == token0, "Dex: Invaild path");
        }
        if (pathSize > 2) {
            for (uint256 i = 1; i < pathSize.sub(1); i++) {
                require(isMiddleToken[_path[i]], "Dex: Invaild middle token");
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

    function addMiddleTokens(address[] calldata newMiddleTokens) external isKeeper {
        uint256 middleTokenSize = newMiddleTokens.length;
        for (uint256 i = 0; i < middleTokenSize; i++) {
            isMiddleToken[newMiddleTokens[i]] = true;
        }
    }

    function removeMiddleTokens(address[] calldata _middleTokens) external isKeeper {
        uint256 middleTokenSize = _middleTokens.length;
        for (uint256 i = 0; i < middleTokenSize; i++) {
            isMiddleToken[_middleTokens[i]] = false;
        }
    }

    function updateTwapInterval(uint256 newTwapInterval) external isSavior {
        twapInterval = newTwapInterval;
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

    function _getSqrtTWAP(address uniswapV3Pool) internal view returns (uint160 sqrtPriceX96) {
        uint32 _twapInterval = uint32(twapInterval);
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Pool);
        (, , uint16 index, uint16 cardinality, , , ) = pool.slot0();
        (uint32 targetElementTime, , , bool initialized) = pool.observations((index + 1) % cardinality);
        if (!initialized) {
            (targetElementTime, , , ) = pool.observations(0);
        }
        uint32 delta = uint32(block.timestamp) - targetElementTime;
        if (delta == 0) {
            (sqrtPriceX96, , , , , , ) = pool.slot0();
        } else {
            if (delta < _twapInterval) _twapInterval = delta;
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = _twapInterval;
            secondsAgos[1] = 0;
            (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(_twapInterval))));
        }
    }
}
