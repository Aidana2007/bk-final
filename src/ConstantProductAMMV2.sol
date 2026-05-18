// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ConstantProductAMM } from "./ConstantProductAMM.sol";

/// @notice Example V2 implementation used to prove UUPS upgrades preserve pool state.
contract ConstantProductAMMV2 is ConstantProductAMM {
    /// @notice Returns the implementation version string.
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
