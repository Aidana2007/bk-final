import { Craft, Recipe } from "../../generated/schema";
import { Crafted, RecipeCreated, RecipeStatusChanged } from "../../generated/CraftingSystem/CraftingSystem";

export function handleRecipeCreated(event: RecipeCreated): void {
  let recipe = new Recipe(event.params.recipeId.toString());
  recipe.outputItemId = event.params.outputItemId;
  recipe.outputAmount = event.params.outputAmount;
  recipe.active = true;
  recipe.createdAt = event.block.timestamp;
  recipe.save();
}

export function handleRecipeStatusChanged(event: RecipeStatusChanged): void {
  let recipe = Recipe.load(event.params.recipeId.toString());
  if (recipe == null) {
    return;
  }
  recipe.active = event.params.active;
  recipe.save();
}

export function handleCrafted(event: Crafted): void {
  let craft = new Craft(event.transaction.hash.toHexString().concat("-").concat(event.logIndex.toString()));
  craft.player = event.params.player;
  craft.recipe = event.params.recipeId.toString();
  craft.outputItemId = event.params.outputItemId;
  craft.outputAmount = event.params.outputAmount;
  craft.blockNumber = event.block.number;
  craft.transactionHash = event.transaction.hash;
  craft.save();
}