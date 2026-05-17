import { LootRequest } from "../../generated/schema";
import { LootDelivered, LootRequested } from "../../generated/VRFLootDrop/VRFLootDrop";

export function handleLootRequested(event: LootRequested): void {
  let request = new LootRequest(event.params.requestId.toString());
  request.player = event.params.player;
  request.fulfilled = false;
  request.requestedAt = event.block.timestamp;
  request.save();
}

export function handleLootDelivered(event: LootDelivered): void {
  let request = LootRequest.load(event.params.requestId.toString());
  if (request == null) {
    request = new LootRequest(event.params.requestId.toString());
    request.player = event.params.player;
    request.requestedAt = event.block.timestamp;
  }
  request.fulfilled = true;
  request.itemId = event.params.itemId;
  request.amount = event.params.amount;
  request.fulfilledAt = event.block.timestamp;
  request.save();
}