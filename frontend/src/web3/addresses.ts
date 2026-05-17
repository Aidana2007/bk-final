import { Address } from "viem";

export const contracts = {
  gameItems: (import.meta.env.VITE_GAME_ITEMS ?? "0x0000000000000000000000000000000000000000") as Address,
  craftingSystem: (import.meta.env.VITE_CRAFTING_SYSTEM ?? "0x0000000000000000000000000000000000000000") as Address,
  lootDrop: (import.meta.env.VITE_VRF_LOOT_DROP ?? "0x0000000000000000000000000000000000000000") as Address,
  governor: (import.meta.env.VITE_GOVERNOR ?? "0x0000000000000000000000000000000000000000") as Address,
  amm: (import.meta.env.VITE_AMM ?? "0x0000000000000000000000000000000000000000") as Address,
  marketplace: (import.meta.env.VITE_MARKETPLACE ?? "0x0000000000000000000000000000000000000000") as Address,
};

export const subgraphUrl = import.meta.env.VITE_SUBGRAPH_URL ?? "";