// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConstantProductAMM} from "./ConstantProductAMM.sol";

contract ConstantProductAMMV2 is ConstantProductAMM {
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
