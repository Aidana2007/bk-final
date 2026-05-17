import { useMemo } from "react";
import { Abi, Address, parseEther, parseUnits } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import ammAbi from "../abi/AMM.json";
import craftingAbi from "../abi/CraftingSystem.json";
import gameItemsAbi from "../abi/GameItems.json";
import governorAbi from "../abi/Governor.json";
import lootAbi from "../abi/VRFLootDrop.json";
import marketplaceAbi from "../abi/Marketplace.json";
import { contracts } from "../web3/addresses";

export function useTransactionState(hash?: `0x${string}`) {
  const receipt = useWaitForTransactionReceipt({ hash });
  return {
    isPending: Boolean(hash && receipt.isLoading),
    isConfirmed: receipt.isSuccess,
    error: receipt.error?.message,
  };
}

export function useGameActions() {
  const writer = useWriteContract();
  const tx = useTransactionState(writer.data);

  return useMemo(
    () => ({
      hash: writer.data,
      isWriting: writer.isPending,
      isPending: tx.isPending,
      isConfirmed: tx.isConfirmed,
      error: writer.error?.message ?? tx.error,
      approveCrafting: () =>
        writer.writeContract({
          address: contracts.gameItems,
          abi: gameItemsAbi as Abi,
          functionName: "setApprovalForAll",
          args: [contracts.craftingSystem, true],
        }),
      craft: (recipeId: bigint) =>
        writer.writeContract({
          address: contracts.craftingSystem,
          abi: craftingAbi as Abi,
          functionName: "craft",
          args: [recipeId],
        }),
      requestLoot: () =>
        writer.writeContract({
          address: contracts.lootDrop,
          abi: lootAbi as Abi,
          functionName: "requestLoot",
        }),
      vote: (proposalId: bigint, support: number) =>
        writer.writeContract({
          address: contracts.governor,
          abi: governorAbi as Abi,
          functionName: "castVote",
          args: [proposalId, support],
        }),
      swap: (tokenIn: Address, amountIn: string, minAmountOut: string) =>
        writer.writeContract({
          address: contracts.amm,
          abi: ammAbi as Abi,
          functionName: "swap",
          args: [tokenIn, parseUnits(amountIn, 18), parseUnits(minAmountOut, 18)],
        }),
      buyListing: (listingId: bigint, priceEth: string) =>
        writer.writeContract({
          address: contracts.marketplace,
          abi: marketplaceAbi as Abi,
          functionName: "buy",
          args: [listingId],
          value: parseEther(priceEth),
        }),
    }),
    [tx.error, tx.isConfirmed, tx.isPending, writer]
  );
}