// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BaseDexCenter.sol";
import "../../libraries/Path.sol";
import "../../util/BoringMath.sol";
import "../../interfaces/ISRC20.sol";
import "../../interfaces/uniswapv2/IUniswapV2Router02.sol";
import "../../interfaces/uniswapv3/IV3SwapRouter.sol";

contract UniClassDexCenter is BaseDexCenter {
    using BoringMath for uint256;
    using Path for bytes;

    constructor(address _SAVIOR) public BaseDexCenter(_SAVIOR) {}

    modifier uniV2CheckPath(address[] calldata _path) {
        uint256 pathSize = _path.length;
        if (pathSize > 2) {
            for (uint256 i = 1; i < pathSize - 1; i++) {
                require(isMiddleToken[_path[i]], "UniV2DexCenter: Invaild middle token");
            }
        }
        _;
    }

    modifier uniV3CheckPath(bytes calldata _pathBytes) {
        address[] memory _path = Path.getRouter(_pathBytes);
        uint256 pathSize = _path.length;
        if (pathSize > 2) {
            for (uint256 i = 1; i < pathSize - 1; i++) {
                require(isMiddleToken[_path[i]], "UniV3DexCenter: Invaild middle token");
            }
        }
        _;
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address swapRouter, address to, address[] calldata path) external onlyEntitledSwapRouters(swapRouter) uniV2CheckPath(path) returns (uint256) {
        approve(swapRouter, path[0]);
        IUniswapV2Router02(swapRouter).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp);
        return amountIn;
    }

    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address swapRouter, address to, address[] calldata path) external onlyEntitledSwapRouters(swapRouter) uniV2CheckPath(path) returns (uint256) {
        approve(swapRouter, path[0]);
        IUniswapV2Router02(swapRouter).swapTokensForExactTokens(amountOut, amountInMax, path, to, block.timestamp);
        transfer(path[0], msg.sender, ISRC20(path[0]).balanceOf(address(this)));
        return amountInMax;
    }

    function exactInput(address swapRouter, IV3SwapRouter.ExactInputParams calldata exactInputParams) external onlyEntitledSwapRouters(swapRouter) uniV3CheckPath(exactInputParams.path) returns (uint256) {
        approve(swapRouter, exactInputParams.path.getTokenIn());
        IV3SwapRouter(swapRouter).exactInput(exactInputParams);
        return exactInputParams.amountIn;
    }

    function exactOutput(address swapRouter, IV3SwapRouter.ExactOutputParams calldata exactOutputParams) external onlyEntitledSwapRouters(swapRouter) uniV3CheckPath(exactOutputParams.path) returns (uint256) {
        address token0 = exactOutputParams.path.getTokenOut();
        approve(swapRouter, token0);
        IV3SwapRouter(swapRouter).exactOutput(exactOutputParams);
        transfer(token0, msg.sender, ISRC20(token0).balanceOf(address(this)));
        return exactOutputParams.amountInMaximum;
    }
}
