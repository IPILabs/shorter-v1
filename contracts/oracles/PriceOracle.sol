// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/TickMath.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/uniswapv3/IUniswapV3Pool.sol";
import "../interfaces/uniswapv3/IV3SwapRouter.sol";
import "../interfaces/uniswapv3/IUniswapV3Factory.sol";
import "./IPriceOracle.sol";
import "../criteria/Affinity.sol";
import "../util/BoringMath.sol";
import "./AggregatorV3Interface.sol";

contract PriceOracle is IPriceOracle, Affinity {
    using BoringMath for uint256;

    struct UniV3RouterInfo {
        address swapRouter;
        address[] swapPath;
        uint24[] fees;
    }

    uint256 public twapInterval = 60;

    mapping(address => uint256) public prices;
    mapping(address => address) public spareFeedContracts;
    mapping(address => PriceOracleMode) public priceOracleModeMap;
    mapping(address => UniV3RouterInfo) public tokenUniv3RouterInfoMap;

    event PriceUpdated(address indexed tokenAddr, uint256 price);

    constructor(address _SAVIOR) public Affinity(_SAVIOR) {}

    function getLatestMixinPrice(address tokenAddr) external view override returns (uint256 tokenPrice) {
        tokenPrice = getTokenPrice(tokenAddr);
        require(tokenPrice > 0, "PriceOracle: Price precision is less than 18");
    }

    function quote(address baseToken, address quoteToken) external view override returns (uint256 tokenPrice) {
        uint256 baseTokenPrice = getTokenPrice(baseToken);
        uint256 quoteTokenPrice = getTokenPrice(quoteToken);
        require(baseTokenPrice > 0 && quoteTokenPrice > 0, "PriceOracle: Price precision is less than 18");
        tokenPrice = baseTokenPrice.mul(1e18).div(quoteTokenPrice);
    }

    function getTokenUniv3RouterInfo(address tokenAddr) external view returns (UniV3RouterInfo memory) {
        return tokenUniv3RouterInfoMap[tokenAddr];
    }

    function setPriceOracleMode(address[] calldata tokenAddrs, PriceOracleMode mode) external isSavior {
        uint256 tokenSize = tokenAddrs.length;
        require(tokenSize > 0, "PriceOracle: tokenAddr is an empty array");
        for (uint256 i = 0; i < tokenSize; i++) {
            priceOracleModeMap[tokenAddrs[i]] = mode;
        }
    }

    function setSpareFeedContracts(address[] calldata tokenAddrs, address[] calldata feedContracts) external isSavior {
        uint256 tokenSize = tokenAddrs.length;
        require(tokenSize > 0, "PriceOracle: tokenAddr is an empty array");
        for (uint256 i = 0; i < tokenSize; i++) {
            spareFeedContracts[tokenAddrs[i]] = feedContracts[i];
        }
    }

    function setUniswapRouterInfo(address[] calldata tokenAddrs, UniV3RouterInfo[] memory uniV3RouterInfos) external isSavior {
        uint256 tokenSize = tokenAddrs.length;
        require(tokenSize > 0, "PriceOracle: tokenAddr is an empty array");
        for (uint256 i = 0; i < tokenSize; i++) {
            tokenUniv3RouterInfoMap[tokenAddrs[i]] = uniV3RouterInfos[i];
        }
    }

    function setTwapInterval(uint256 _twapInterval) external isSavior {
        twapInterval = _twapInterval;
    }

    function setPrice(address tokenAddr, uint256 price) external isSavior {
        prices[tokenAddr] = price;
        emit PriceUpdated(tokenAddr, price);
    }

    function getTokenPrice(address tokenAddr) internal view returns (uint256 tokenPrice) {
        if (priceOracleModeMap[tokenAddr] == PriceOracleMode.DEX_MODE) {
            tokenPrice = getUniV3TokenPrice(tokenAddr);
        }

        if (priceOracleModeMap[tokenAddr] == PriceOracleMode.CHAINLINK_MODE) {
            tokenPrice = getChainLinkPrice(tokenAddr);
        }

        if (priceOracleModeMap[tokenAddr] == PriceOracleMode.FEED_MODE) {
            tokenPrice = getLatestPrice(tokenAddr);
        }
    }

    function getUniV3TokenPrice(address token) internal view returns (uint256 tokenPrice) {
        UniV3RouterInfo storage univ3RouterInfo = tokenUniv3RouterInfoMap[token];
        require(univ3RouterInfo.swapRouter != address(0), "PriceOracle: swapRouter is zero Address");
        IUniswapV3Factory swapFactory = IUniswapV3Factory(IV3SwapRouter(univ3RouterInfo.swapRouter).factory());
        tokenPrice = 1e18;
        for (uint256 i = 0; i < univ3RouterInfo.fees.length; i++) {
            address[] storage path = univ3RouterInfo.swapPath;
            address poolAddr = swapFactory.getPool(path[i], path[i + 1], univ3RouterInfo.fees[i]);
            uint160 sqrtPriceX96 = getTokenTwapPriceByV3Pool(poolAddr);
            address token0 = IUniswapV3Pool(poolAddr).token0();
            uint256 token0Decimals = uint256(ISRC20(token0).decimals());
            uint256 token1Decimals = path[i] == token0 ? uint256(ISRC20(path[i + 1]).decimals()) : uint256(ISRC20(path[i]).decimals());
            uint256 token0Price;
            uint256 sqrtDecimals = uint256(18).add(token0Decimals).sub(token1Decimals).div(2);
            if (sqrtDecimals.mul(2) == uint256(18).add(token0Decimals).sub(token1Decimals)) {
                uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10 ** sqrtDecimals).div(2 ** 96);
                token0Price = sqrtPrice.mul(sqrtPrice);
            } else {
                uint256 sqrtPrice = uint256(sqrtPriceX96).mul(10 ** (sqrtDecimals + 1)).div(2 ** 96);
                token0Price = sqrtPrice.mul(sqrtPrice).div(10);
            }
            if (token0 == path[i]) {
                tokenPrice = tokenPrice.mul(token0Price).div(1e18);
            } else {
                tokenPrice = tokenPrice.mul(uint256(1e36).div(token0Price)).div(1e18);
            }
        }
    }

    function getTokenTwapPriceByV3Pool(address v3Pool) internal view returns (uint160 sqrtPriceX96) {
        uint32 _twapInterval = uint32(twapInterval);
        IUniswapV3Pool pool = IUniswapV3Pool(v3Pool);
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

    function getChainLinkPrice(address tokenAddr) internal view returns (uint256 tokenPirce) {
        require(spareFeedContracts[tokenAddr] != address(0), "PriceOracle: Feed contract is zero");
        AggregatorV3Interface feedContract = AggregatorV3Interface(spareFeedContracts[tokenAddr]);
        uint256 decimals = uint256(feedContract.decimals());
        (, int256 _tokenPrice, , , ) = feedContract.latestRoundData();
        tokenPirce = uint256(_tokenPrice).mul(1e18).div(10 ** decimals);
    }

    function getLatestPrice(address tokenAddr) internal view returns (uint256 tokenPirce) {
        return prices[tokenAddr];
    }
}
