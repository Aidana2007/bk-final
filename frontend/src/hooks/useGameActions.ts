import { useMemo } from "react";
import { Abi, Address, parseEther, parseUnits } from "viem";
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import ammAbi from "../abi/AMM.json";
import craftingAbi from "../abi/CraftingSystem.json";
import gameItemsAbi from "../abi/GameItems.json";
import governorAbi from "../abi/Governor.json";
import lootAbi from "../abi/VRFLootDrop.json";
import marketplaceAbi from "../abi/Marketplace.json";
import { contracts } from "../web3/addresses";

const erc20Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

function readableError(message?: string) {
  if (!message) return undefined;
  const lower = message.toLowerCase();
  if (lower.includes("user rejected") || lower.includes("user denied")) {
    return "Transaction rejected in wallet.";
  }
  if (lower.includes("insufficient funds") || lower.includes("exceeds balance")) {
    return "Insufficient balance for this transaction.";
  }
  if (lower.includes("chain") || lower.includes("network")) {
    return "Wallet is connected to the wrong network.";
  }
  return message.split("\n")[0];
}

export function useTransactionState(hash?: `0x${string}`) {
  const receipt = useWaitForTransactionReceipt({ hash });
  return {
    isPending: Boolean(hash && receipt.isLoading),
    isConfirmed: receipt.isSuccess,
    error: readableError(receipt.error?.message),
  };
}

export function useGameActions() {
  const { address } = useAccount();
  const writer = useWriteContract();
  const tx = useTransactionState(writer.data);

  return useMemo(
    () => ({
      hash: writer.data,
      isWriting: writer.isPending,
      isPending: tx.isPending,
      isConfirmed: tx.isConfirmed,
      error: readableError(writer.error?.message) ?? tx.error,
      approveTokenForAmm: (token: Address, amount: string) =>
        writer.writeContract({
          address: token,
          abi: erc20Abi,
          functionName: "approve",
          args: [contracts.amm, parseUnits(amount, 18)],
        }),
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
      swap: (tokenIn: Address, amountIn: string, minAmountOut: string) => {
        if (!address) return;
        writer.writeContract({
          address: contracts.amm,
          abi: ammAbi as Abi,
          functionName: "swapExactTokenForToken",
          args: [tokenIn, parseUnits(amountIn, 18), parseUnits(minAmountOut, 18), address],
        });
      },
      buyListing: (listingId: bigint, priceEth: string) =>
        writer.writeContract({
          address: contracts.marketplace,
          abi: marketplaceAbi as Abi,
          functionName: "buy",
          args: [listingId],
          value: parseEther(priceEth),
        }),
    }),
    [address, tx.error, tx.isConfirmed, tx.isPending, writer]
  );
}
