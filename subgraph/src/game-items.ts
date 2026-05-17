import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { TransferBatch, TransferSingle } from "../../generated/GameItems/GameItems";
import { ItemBalance, ItemTransfer } from "../../generated/schema";

let ZERO = "0x0000000000000000000000000000000000000000";

function balanceId(account: Bytes, itemId: BigInt): string {
  return account.toHexString().concat("-").concat(itemId.toString());
}

function applyDelta(account: Bytes, itemId: BigInt, delta: BigInt, blockNumber: BigInt): void {
  if (account.toHexString() == ZERO) {
    return;
  }

  let id = balanceId(account, itemId);
  let balance = ItemBalance.load(id);
  if (balance == null) {
    balance = new ItemBalance(id);
    balance.account = account;
    balance.itemId = itemId;
    balance.balance = BigInt.zero();
  }
  balance.balance = balance.balance.plus(delta);
  balance.updatedAt = blockNumber;
  balance.save();
}

function saveTransfer(
  id: string,
  operator: Bytes,
  from: Bytes,
  to: Bytes,
  itemId: BigInt,
  amount: BigInt,
  blockNumber: BigInt,
  transactionHash: Bytes
): void {
  let transfer = new ItemTransfer(id);
  transfer.operator = operator;
  transfer.from = from;
  transfer.to = to;
  transfer.itemId = itemId;
  transfer.amount = amount;
  transfer.blockNumber = blockNumber;
  transfer.transactionHash = transactionHash;
  transfer.save();
}

export function handleTransferSingle(event: TransferSingle): void {
  let itemId = event.params.id;
  let amount = event.params.value;
  applyDelta(event.params.from, itemId, amount.neg(), event.block.number);
  applyDelta(event.params.to, itemId, amount, event.block.number);
  saveTransfer(
    event.transaction.hash.toHexString().concat("-").concat(event.logIndex.toString()),
    event.params.operator,
    event.params.from,
    event.params.to,
    itemId,
    amount,
    event.block.number,
    event.transaction.hash
  );
}

export function handleTransferBatch(event: TransferBatch): void {
  for (let i = 0; i < event.params.ids.length; i++) {
    let itemId = event.params.ids[i];
    let amount = event.params.values[i];
    applyDelta(event.params.from, itemId, amount.neg(), event.block.number);
    applyDelta(event.params.to, itemId, amount, event.block.number);
    saveTransfer(
      event.transaction.hash.toHexString().concat("-").concat(event.logIndex.toString()).concat("-").concat(i.toString()),
      event.params.operator,
      event.params.from,
      event.params.to,
      itemId,
      amount,
      event.block.number,
      event.transaction.hash
    );
  }
}