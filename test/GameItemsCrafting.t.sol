// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CraftingSystem} from "../src/CraftingSystem.sol";
import {GameItems} from "../src/GameItems.sol";
import {IGameItems} from "../src/interfaces/IGameItems.sol";

contract GameItemsCraftingTest is Test {
    GameItems internal items;
    CraftingSystem internal crafting;
    address internal player = address(0xBEEF);

    function setUp() public {
        items = new GameItems("ipfs://items/{id}.json", address(this));
        crafting = new CraftingSystem(IGameItems(address(items)), address(this));
        items.grantRole(items.MINTER_ROLE(), address(crafting));
        items.mint(player, 1, 3, "");
        items.mint(player, 2, 2, "");
    }

    function testCraftBurnsIngredientsAndMintsOutput() public {
        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](2);
        ingredients[0] = CraftingSystem.Ingredient({itemId: 1, amount: 2});
        ingredients[1] = CraftingSystem.Ingredient({itemId: 2, amount: 1});
        uint256 recipeId = crafting.createRecipe(10, 1, ingredients);

        vm.startPrank(player);
        items.setApprovalForAll(address(crafting), true);
        crafting.craft(recipeId);
        vm.stopPrank();

        assertEq(items.balanceOf(player, 1), 1);
        assertEq(items.balanceOf(player, 2), 1);
        assertEq(items.balanceOf(player, 10), 1);
    }
}
