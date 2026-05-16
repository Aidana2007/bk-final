// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";

contract AMMGasTest is Test {
    ConstantProductAMM internal pool;

    function setUp() public {
        pool = new ConstantProductAMM();
    }

    function testGas_solidityBenchmarkGetAmountOut() public view {
        pool.getAmountOutSolidityBenchmark(100 ether, 10_000 ether, 25_000 ether);
    }

    function testGas_yulGetAmountOut() public view {
        pool.getAmountOutYul(100 ether, 10_000 ether, 25_000 ether);
    }
}
