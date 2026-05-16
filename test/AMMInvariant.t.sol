// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AMMFactory} from "../src/AMMFactory.sol";
import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AMMHandler is Test {
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    ConstantProductAMM public pool;
    uint256 public lastSwapK;

    constructor(MockERC20 tokenA_, MockERC20 tokenB_, ConstantProductAMM pool_) {
        tokenA = tokenA_;
        tokenB = tokenB_;
        pool = pool_;

        tokenA.mint(address(this), type(uint128).max);
        tokenB.mint(address(this), type(uint128).max);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);

        pool.addLiquidity(1_000_000 ether, 1_000_000 ether, 1, 1, address(this));
        lastSwapK = pool.kLast();
    }

    function swapAForB(uint128 rawAmountIn) public {
        uint256 amountIn = bound(uint256(rawAmountIn), 1, 5_000 ether);
        pool.swapExactTokenForToken(address(tokenA), amountIn, 1, address(this));
        lastSwapK = pool.kLast();
    }

    function swapBForA(uint128 rawAmountIn) public {
        uint256 amountIn = bound(uint256(rawAmountIn), 1, 5_000 ether);
        pool.swapExactTokenForToken(address(tokenB), amountIn, 1, address(this));
        lastSwapK = pool.kLast();
    }
}

contract AMMInvariantTest is Test {
    AMMHandler internal handler;
    ConstantProductAMM internal pool;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    IERC20 internal lpToken;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        ConstantProductAMM implementation = new ConstantProductAMM();
        AMMFactory factory = new AMMFactory(address(implementation), address(this), address(this));
        (address poolAddress, address lpTokenAddress) = factory.createPool(address(tokenA), address(tokenB));
        pool = ConstantProductAMM(poolAddress);
        lpToken = IERC20(lpTokenAddress);

        handler = new AMMHandler(tokenA, tokenB, pool);
    }

    function swapAForB(uint128 rawAmountIn) public {
        handler.swapAForB(rawAmountIn);
    }

    function swapBForA(uint128 rawAmountIn) public {
        handler.swapBForA(rawAmountIn);
    }

    function invariant_KNeverDecreasesAfterSwap() public {
        assertGe(pool.kLast(), handler.lastSwapK());
    }

    function invariant_ReservesMatchBalances() public {
        (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
        (address token0, address token1,) = pool.poolTokens();

        assertEq(uint256(reserve0), IERC20(token0).balanceOf(address(pool)));
        assertEq(uint256(reserve1), IERC20(token1).balanceOf(address(pool)));
    }

    function invariant_TotalLPAccountingValid() public {
        assertEq(
            lpToken.totalSupply(),
            lpToken.balanceOf(address(handler)) + lpToken.balanceOf(pool.MINIMUM_LIQUIDITY_RECIPIENT())
        );
    }
}
