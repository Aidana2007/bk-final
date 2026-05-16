// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AMMFactory} from "../src/AMMFactory.sol";
import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AMMFuzzTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal pool;
    IERC20 internal lpToken;
    address internal owner = address(this);
    address internal user = address(0xCAFE);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        ConstantProductAMM implementation = new ConstantProductAMM();
        AMMFactory factory = new AMMFactory(address(implementation), owner, owner);
        (address poolAddress, address lpTokenAddress) = factory.createPool(address(tokenA), address(tokenB));
        pool = ConstantProductAMM(poolAddress);
        lpToken = IERC20(lpTokenAddress);

        tokenA.mint(user, type(uint128).max);
        tokenB.mint(user, type(uint128).max);

        vm.startPrank(user);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        lpToken.approve(address(pool), type(uint256).max);
        pool.addLiquidity(1_000_000 ether, 1_000_000 ether, 1, 1, user);
        vm.stopPrank();
    }

    function testFuzzSwapExactInput(uint128 rawAmountIn, bool zeroForOne) public {
        uint256 amountIn = bound(uint256(rawAmountIn), 1 ether, 10_000 ether);
        address tokenIn = zeroForOne ? address(tokenA) : address(tokenB);
        uint256 beforeK = pool.kLast();

        vm.prank(user);
        uint256 out = pool.swapExactTokenForToken(tokenIn, amountIn, 1, user);
        (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
        (address poolToken0, address poolToken1,) = pool.poolTokens();

        assertGt(out, 0);
        assertGe(pool.kLast(), beforeK);
        assertEq(uint256(reserve0), IERC20(poolToken0).balanceOf(address(pool)));
        assertEq(uint256(reserve1), IERC20(poolToken1).balanceOf(address(pool)));
    }

    function testFuzzAddAndRemoveLiquidity(uint128 rawAmount0, uint128 rawAmount1) public {
        uint256 amount0 = bound(uint256(rawAmount0), 1 ether, 50_000 ether);
        uint256 amount1 = bound(uint256(rawAmount1), 1 ether, 50_000 ether);

        vm.startPrank(user);
        (,, uint256 liquidity) = pool.addLiquidity(amount0, amount1, 1, 1, user);
        (uint256 out0, uint256 out1) = pool.removeLiquidity(liquidity, 1, 1, user);
        (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
        (address poolToken0, address poolToken1,) = pool.poolTokens();
        vm.stopPrank();

        assertGt(out0, 0);
        assertGt(out1, 0);
        assertEq(uint256(reserve0), IERC20(poolToken0).balanceOf(address(pool)));
        assertEq(uint256(reserve1), IERC20(poolToken1).balanceOf(address(pool)));
    }
}
