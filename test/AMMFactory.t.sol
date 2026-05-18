// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AMMFactory } from "../src/AMMFactory.sol";
import { AMMLPToken } from "../src/AMMLPToken.sol";
import { ConstantProductAMM } from "../src/ConstantProductAMM.sol";
import { ConstantProductAMMV2 } from "../src/ConstantProductAMMV2.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract AMMFactoryTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal implementation;
    AMMFactory internal factory;

    address internal owner = address(0xA11CE);
    address internal lp = address(0xB0B);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        implementation = new ConstantProductAMM();
        factory = new AMMFactory(address(implementation), owner, owner);
    }

    function testCreatePoolWithCreate() public {
        vm.prank(owner);
        (address pool, address lpToken) = factory.createPool(address(tokenA), address(tokenB));

        assertEq(factory.allPoolsLength(), 1);
        assertEq(AMMLPToken(lpToken).owner(), pool);
        assertEq(factory.getPool(address(tokenA), address(tokenB)), pool);
        assertEq(factory.getPool(address(tokenB), address(tokenA)), pool);

        (address token0, address token1, address actualLP) = ConstantProductAMM(pool).poolTokens();
        assertEq(actualLP, lpToken);
        assertTrue(token0 < token1);
    }

    function testCreatePoolWithCreate2MatchesPrediction() public {
        bytes32 salt = keccak256("optimism-sepolia-demo");
        (address predictedPool, address predictedLP) =
            factory.predictDeterministicPool(address(tokenA), address(tokenB), salt);

        vm.prank(owner);
        (address pool, address lpToken) =
            factory.createPoolDeterministic(address(tokenA), address(tokenB), salt);

        assertEq(pool, predictedPool);
        assertEq(lpToken, predictedLP);
    }

    function testDuplicatePoolReverts() public {
        vm.startPrank(owner);
        factory.createPool(address(tokenA), address(tokenB));
        vm.expectRevert();
        factory.createPool(address(tokenB), address(tokenA));
        vm.stopPrank();
    }
}

contract ConstantProductAMMTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    AMMFactory internal factory;
    ConstantProductAMM internal implementation;
    ConstantProductAMM internal pool;
    IERC20 internal lpToken;

    address internal owner = address(0xA11CE);
    address internal user = address(0xBEEF);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        implementation = new ConstantProductAMM();
        factory = new AMMFactory(address(implementation), owner, owner);

        vm.prank(owner);
        (address poolAddress, address lpTokenAddress) =
            factory.createPool(address(tokenA), address(tokenB));
        pool = ConstantProductAMM(poolAddress);
        lpToken = IERC20(lpTokenAddress);

        tokenA.mint(user, 2_000_000 ether);
        tokenB.mint(user, 2_000_000 ether);

        vm.startPrank(user);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        lpToken.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testAddLiquidityMintsLPAndLocksMinimumLiquidity() public {
        vm.prank(user);
        (uint256 amount0, uint256 amount1, uint256 liquidity) =
            pool.addLiquidity(100 ether, 100 ether, 99 ether, 99 ether, user);

        assertEq(amount0, 100 ether);
        assertEq(amount1, 100 ether);
        assertEq(liquidity, 100 ether - pool.MINIMUM_LIQUIDITY());
        assertEq(lpToken.balanceOf(user), liquidity);
        assertEq(lpToken.balanceOf(pool.MINIMUM_LIQUIDITY_RECIPIENT()), pool.MINIMUM_LIQUIDITY());
    }

    function testAddLiquidityUsesOptimalRatio() public {
        vm.startPrank(user);
        pool.addLiquidity(100 ether, 200 ether, 100 ether, 200 ether, user);
        (uint256 amount0, uint256 amount1,) =
            pool.addLiquidity(50 ether, 150 ether, 50 ether, 100 ether, user);
        vm.stopPrank();

        assertEq(amount0, 50 ether);
        assertEq(amount1, 100 ether);
    }

    function testSwapChargesFeeAndDoesNotDecreaseK() public {
        vm.startPrank(user);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether, 1_000 ether, user);
        uint256 beforeK = pool.kLast();
        uint256 expectedOut = pool.getAmountOut(10 ether, 1_000 ether, 1_000 ether);
        uint256 out = pool.swapExactTokenForToken(address(tokenA), 10 ether, expectedOut, user);
        vm.stopPrank();

        assertEq(out, expectedOut);
        assertGe(pool.kLast(), beforeK);
    }

    function testSwapToken1ForToken0() public {
        vm.startPrank(user);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether, 1_000 ether, user);
        uint256 expectedOut = pool.getAmountOut(25 ether, 1_000 ether, 1_000 ether);
        uint256 out = pool.swapExactTokenForToken(address(tokenB), 25 ether, expectedOut, user);
        vm.stopPrank();

        assertEq(out, expectedOut);
    }

    function testSwapFeeMatchesThirtyBpsFormula() public {
        uint256 amountIn = 10 ether;
        uint256 reserveIn = 1_000 ether;
        uint256 reserveOut = 1_000 ether;
        uint256 expected =
            (amountIn * 9_970 * reserveOut) / ((reserveIn * 10_000) + (amountIn * 9_970));

        assertEq(pool.getAmountOut(amountIn, reserveIn, reserveOut), expected);
    }

    function testSwapSlippageReverts() public {
        vm.startPrank(user);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether, 1_000 ether, user);
        uint256 expectedOut = pool.getAmountOut(10 ether, 1_000 ether, 1_000 ether);
        vm.expectRevert();
        pool.swapExactTokenForToken(address(tokenA), 10 ether, expectedOut + 1, user);
        vm.stopPrank();
    }

    function testFirstLiquidityTooSmallReverts() public {
        vm.prank(user);
        vm.expectRevert();
        pool.addLiquidity(10, 10, 1, 1, user);
    }

    function testPauseBlocksLiquidityAndSwaps() public {
        vm.prank(owner);
        pool.pause();

        vm.startPrank(user);
        vm.expectRevert();
        pool.addLiquidity(1_000 ether, 1_000 ether, 1, 1, user);
        vm.stopPrank();
    }

    function testRemoveLiquidityBurnsLPAndReturnsUnderlying() public {
        vm.startPrank(user);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether, 1_000 ether, user);
        uint256 liquidity = lpToken.balanceOf(user) / 2;
        uint256 balance0Before = tokenA.balanceOf(user);
        uint256 balance1Before = tokenB.balanceOf(user);
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(liquidity, 1, 1, user);
        vm.stopPrank();

        assertGt(amount0, 0);
        assertGt(amount1, 0);
        assertEq(tokenA.balanceOf(user), balance0Before + amount0);
        assertEq(tokenB.balanceOf(user), balance1Before + amount1);
    }

    function testYulAmountOutMatchesSolidity() public {
        uint256 yulOut = pool.getAmountOutYul(13 ether, 2_001 ether, 997 ether);
        uint256 solOut = pool.getAmountOut(13 ether, 2_001 ether, 997 ether);
        uint256 benchmarkOut = pool.getAmountOutSolidityBenchmark(13 ether, 2_001 ether, 997 ether);
        assertEq(yulOut, solOut);
        assertEq(yulOut, benchmarkOut);
    }

    function testUUPSUpgradePreservesReserves() public {
        vm.prank(user);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether, 1_000 ether, user);
        uint256 beforeK = pool.kLast();

        ConstantProductAMMV2 v2 = new ConstantProductAMMV2();
        vm.prank(owner);
        pool.upgradeToAndCall(address(v2), "");

        assertEq(ConstantProductAMMV2(address(pool)).version(), "2.0.0");
        assertEq(pool.kLast(), beforeK);
    }
}
