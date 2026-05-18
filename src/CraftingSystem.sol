// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IGameItems } from "./interfaces/IGameItems.sol";

contract CraftingSystem is AccessControl, ReentrancyGuard {
    bytes32 public constant RECIPE_MANAGER_ROLE = keccak256("RECIPE_MANAGER_ROLE");

    struct Ingredient {
        uint256 itemId;
        uint256 amount;
    }

    struct Recipe {
        bool active;
        uint256 outputItemId;
        uint256 outputAmount;
        Ingredient[] ingredients;
    }

    IGameItems public immutable gameItems;
    uint256 public nextRecipeId = 1;
    mapping(uint256 => Recipe) private _recipes;

    event RecipeCreated(
        uint256 indexed recipeId, uint256 indexed outputItemId, uint256 outputAmount
    );
    event RecipeStatusChanged(uint256 indexed recipeId, bool active);
    event Crafted(
        address indexed player,
        uint256 indexed recipeId,
        uint256 indexed outputItemId,
        uint256 outputAmount
    );

    constructor(IGameItems gameItems_, address admin) {
        gameItems = gameItems_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RECIPE_MANAGER_ROLE, admin);
    }

    function createRecipe(
        uint256 outputItemId,
        uint256 outputAmount,
        Ingredient[] calldata ingredients
    ) external onlyRole(RECIPE_MANAGER_ROLE) returns (uint256 recipeId) {
        require(outputAmount > 0, "Crafting: zero output");
        require(ingredients.length > 0, "Crafting: no ingredients");

        recipeId = nextRecipeId++;
        Recipe storage recipe = _recipes[recipeId];
        recipe.active = true;
        recipe.outputItemId = outputItemId;
        recipe.outputAmount = outputAmount;

        for (uint256 i = 0; i < ingredients.length; i++) {
            require(ingredients[i].amount > 0, "Crafting: zero ingredient");
            recipe.ingredients.push(ingredients[i]);
        }

        emit RecipeCreated(recipeId, outputItemId, outputAmount);
    }

    function setRecipeActive(uint256 recipeId, bool active) external onlyRole(RECIPE_MANAGER_ROLE) {
        require(_recipes[recipeId].outputAmount != 0, "Crafting: missing recipe");
        _recipes[recipeId].active = active;
        emit RecipeStatusChanged(recipeId, active);
    }

    function craft(uint256 recipeId) external nonReentrant {
        Recipe storage recipe = _recipes[recipeId];
        require(recipe.active, "Crafting: inactive recipe");

        for (uint256 i = 0; i < recipe.ingredients.length; i++) {
            Ingredient memory ingredient = recipe.ingredients[i];
            gameItems.burn(msg.sender, ingredient.itemId, ingredient.amount);
        }

        gameItems.mint(msg.sender, recipe.outputItemId, recipe.outputAmount, "");
        emit Crafted(msg.sender, recipeId, recipe.outputItemId, recipe.outputAmount);
    }

    function getRecipe(uint256 recipeId)
        external
        view
        returns (
            bool active,
            uint256 outputItemId,
            uint256 outputAmount,
            Ingredient[] memory ingredients
        )
    {
        Recipe storage recipe = _recipes[recipeId];
        return (recipe.active, recipe.outputItemId, recipe.outputAmount, recipe.ingredients);
    }
}
