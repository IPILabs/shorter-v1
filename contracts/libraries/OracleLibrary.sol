// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "../util/BoringMath.sol";

library OracleLibrary {
    using BoringMath for uint256;

    function getFormatPrice(uint256 _tokenPrice) internal pure returns (uint256 tokenPrice, uint256 tokenDecimals) {
        if (_tokenPrice.div(10**20) > 0) {
            return (_tokenPrice.div(10**16), 2);
        } else if (_tokenPrice.div(10**14) > 0) {
            return (_tokenPrice.div(10**14), 4);
        } else if (_tokenPrice.div(10**13) > 0) {
            return (_tokenPrice.div(10**10), 8);
        } else if (_tokenPrice.div(10**12) > 0) {
            return (_tokenPrice.div(10**9), 9);
        } else if (_tokenPrice.div(10**11) > 0) {
            return (_tokenPrice.div(10**8), 10);
        } else if (_tokenPrice.div(10**10) > 0) {
            return (_tokenPrice.div(10**7), 11);
        } else if (_tokenPrice.div(10**9) > 0) {
            return (_tokenPrice.div(10**6), 12);
        } else if (_tokenPrice.div(10**8) > 0) {
            return (_tokenPrice.div(10**5), 13);
        } else if (_tokenPrice.div(10**7) > 0) {
            return (_tokenPrice.div(10**4), 14);
        } else if (_tokenPrice.div(10**6) > 0) {
            return (_tokenPrice.div(10**3), 15);
        } else if (_tokenPrice.div(10**5) > 0) {
            return (_tokenPrice.div(10**2), 16);
        } else if (_tokenPrice.div(10**4) > 0) {
            return (_tokenPrice.div(10**1), 17);
        }

        return (_tokenPrice, 18);
    }
}
