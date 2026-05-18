// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AMMFactory } from "../src/AMMFactory.sol";
import { ConstantProductAMM } from "../src/ConstantProductAMM.sol";
import { CraftingSystem } from "../src/CraftingSystem.sol";
import { GameItems } from "../src/GameItems.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";
import { IGameItems } from "../src/interfaces/IGameItems.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract AMMGasTest is Test {
    ConstantProductAMM internal implementation;
    ConstantProductAMM internal pool;
    AMMFactory internal factory;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    MockERC20 internal tokenD;
    IERC20 internal lpToken;
    GovernanceToken internal governanceToken;
    ProtocolGovernor internal governor;
    GameItems internal gameItems;
    CraftingSystem internal crafting;
    uint256 internal recipeId;
    address internal user = address(0xCAFE);

    function setUp() public {
        implementation = new ConstantProductAMM();
        pool = new ConstantProductAMM();

        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        tokenC = new MockERC20("Token C", "TKNC");
        tokenD = new MockERC20("Token D", "TKND");

        factory = new AMMFactory(address(implementation), address(this), address(this));
        (address poolAddress, address lpTokenAddress) =
            factory.createPool(address(tokenA), address(tokenB));
        pool = ConstantProductAMM(poolAddress);
        lpToken = IERC20(lpTokenAddress);

        tokenA.mint(user, 1_000_000 ether);
        tokenB.mint(user, 1_000_000 ether);
        vm.startPrank(user);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        lpToken.approve(address(pool), type(uint256).max);
        pool.addLiquidity(100_000 ether, 100_000 ether, 1, 1, user);
        vm.stopPrank();

        governanceToken = new GovernanceToken(
            "Governance Token", "GOV", 1_000_000 ether, address(this), address(this)
        );
        governanceToken.delegate(address(this));
        vm.warp(block.timestamp + 1);
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock =
            new TimelockController(2 days, proposers, executors, address(this));
        governor = new ProtocolGovernor(governanceToken, timelock, 10_000 ether);

        gameItems = new GameItems("ipfs://items/{id}.json", address(this));
        crafting = new CraftingSystem(IGameItems(address(gameItems)), address(this));
        gameItems.grantRole(gameItems.MINTER_ROLE(), address(crafting));
        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](2);
        ingredients[0] = CraftingSystem.Ingredient({ itemId: 1, amount: 2 });
        ingredients[1] = CraftingSystem.Ingredient({ itemId: 2, amount: 1 });
        recipeId = crafting.createRecipe(10, 1, ingredients);
        gameItems.mint(user, 1, 10, "");
        gameItems.mint(user, 2, 10, "");
        vm.prank(user);
        gameItems.setApprovalForAll(address(crafting), true);
    }

    function testGas_solidityBenchmarkGetAmountOut() public view {
        implementation.getAmountOutSolidityBenchmark(100 ether, 10_000 ether, 25_000 ether);
    }

    function testGas_yulGetAmountOut() public view {
        implementation.getAmountOutYul(100 ether, 10_000 ether, 25_000 ether);
    }

    function testGas_createPool() public {
        factory.createPool(address(tokenC), address(tokenD));
    }

    function testGas_addLiquidity() public {
        vm.prank(user);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1, 1, user);
    }

    function testGas_swapExactInput() public {
        vm.prank(user);
        pool.swapExactTokenForToken(address(tokenA), 100 ether, 1, user);
    }

    function testGas_removeLiquidity() public {
        uint256 liquidity = lpToken.balanceOf(user) / 10;

        vm.prank(user);
        pool.removeLiquidity(liquidity, 1, 1, user);
    }

    function testGas_createGovernanceProposal() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governanceToken);
        calldatas[0] = abi.encodeCall(GovernanceToken.mint, (address(0xBEEF), 1 ether));

        governor.propose(targets, values, calldatas, "Gas proposal");
    }

    function testGas_craftItem() public {
        vm.prank(user);
        crafting.craft(recipeId);
    }
}
