// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../libraries/AllyLibrary.sol";
import "./IPriceOracle.sol";
import "../interfaces/uniswapv2/IUniswapV2Factory.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/IDexCenter.sol";
import "../interfaces/IShorterBone.sol";
import "../criteria/Affinity.sol";
import "../util/BoringMath.sol";
import "../libraries/OracleLibrary.sol";
import "./AggregatorV3Interface.sol";

contract PriceOracle is IPriceOracle, Affinity {
    using BoringMath for uint256;
    using AllyLibrary for IShorterBone;

    struct Router {
        bool flag;
        address swapRouter;
        address[] path;
        uint24[] fees;
    }

    address public immutable stableTokenAddr;
    IDexCenter public dexCenter;
    IShorterBone public shorterBone;

    mapping(address => Router) public getRouter;
    mapping(address => uint256) public prices;
    mapping(address => address) public spareFeedContracts;
    mapping(address => PriceOracleMode) public priceOracleModeMap;

    event PriceUpdated(address indexed tokenAddr, uint256 price);

    modifier onlyCommittee() {
        shorterBone.assertCaller(msg.sender, AllyLibrary.COMMITTEE);
        _;
    }

    constructor(
        address _SAVIOR,
        address _stableTokenAddr,
        address _dexCenter,
        IShorterBone _shorterBone
    ) public Affinity(_SAVIOR) {
        stableTokenAddr = _stableTokenAddr;
        shorterBone = _shorterBone;
        dexCenter = IDexCenter(_dexCenter);
    }

    /// @notice Get lastest USD price of one specified token, use spare price feeder first
    function getLatestMixinPrice(address tokenAddr) external view override returns (uint256 tokenPrice) {
        if (priceOracleModeMap[tokenAddr] == PriceOracleMode.DEX_MODE) {
            tokenPrice = _getDexPrice(tokenAddr);
        } else if (priceOracleModeMap[tokenAddr] == PriceOracleMode.CHAINLINK_MODE) {
            tokenPrice = _getChainLinkPrice(tokenAddr);
        } else if (priceOracleModeMap[tokenAddr] == PriceOracleMode.FEED_MODE) {
            tokenPrice = _getLatestPrice(tokenAddr);
        }
        uint256 decimals;
        (tokenPrice, decimals) = OracleLibrary.getFormatPrice(tokenPrice);
        tokenPrice = tokenPrice.mul(10**(uint256(18).sub(decimals)));
    }

    function setPrice(address tokenAddr, uint256 price) external isKeeper {
        emit PriceUpdated(tokenAddr, price);
        prices[tokenAddr] = price;
    }

    function setSpareFeedContract(address tokenAddr, address feedContract) external isKeeper {
        spareFeedContracts[tokenAddr] = feedContract;
    }

    function setSpareFeedContracts(address[] memory tokenAddrs, address[] memory feedContracts) external onlyCommittee {
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            spareFeedContracts[tokenAddrs[i]] = feedContracts[i];
        }
    }

    function setRouter(
        address tokenAddr,
        bool flag,
        address swapRouter,
        address[] memory path,
        uint24[] memory fees
    ) external isManager {
        getRouter[tokenAddr] = Router({flag: flag, swapRouter: swapRouter, path: path, fees: fees});
    }

    function setPriceOracleMode(address tokenAddr, PriceOracleMode mode) external isKeeper {
        priceOracleModeMap[tokenAddr] = mode;
    }

    function setDexCenter(IDexCenter _dexCenter) external onlyCommittee {
        dexCenter = _dexCenter;
    }

    function _getLatestPrice(address tokenAddr) internal view returns (uint256 tokenPirce) {
        return prices[tokenAddr];
    }

    function _getChainLinkPrice(address tokenAddr) internal view returns (uint256 tokenPirce) {
        require(spareFeedContracts[tokenAddr] != address(0), "PriceOracle: Feed contract is zero");
        AggregatorV3Interface feedContract = AggregatorV3Interface(spareFeedContracts[tokenAddr]);
        uint256 decimals = uint256(feedContract.decimals());
        (, int256 _tokenPrice, , , ) = feedContract.latestRoundData();
        tokenPirce = uint256(_tokenPrice).mul(10**18).div(10**decimals);
    }

    function _getDexPrice(address tokenAddr) internal view returns (uint256 tokenPirce) {
        (address swapRouter, address[] memory path, uint24[] memory fees) = getAutoRouter(tokenAddr);
        tokenPirce = dexCenter.getTokenPrice(swapRouter, path, fees);
    }

    function getAutoRouter(address tokenAddr)
        internal
        view
        returns (
            address swapRouter,
            address[] memory path,
            uint24[] memory fees
        )
    {
        Router storage pathInfo = getRouter[tokenAddr];
        if (pathInfo.flag) {
            return (pathInfo.swapRouter, pathInfo.path, pathInfo.fees);
        }

        (, swapRouter, ) = shorterBone.getTokenInfo(tokenAddr);
        path = new address[](2);
        (path[0], path[1]) = (tokenAddr, stableTokenAddr);

        fees = new uint24[](1);
        fees[0] = 3000;
    }
}
