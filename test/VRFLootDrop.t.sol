// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import {
    VRFV2PlusClient
} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import { GameItems } from "../src/GameItems.sol";
import { VRFLootDrop } from "../src/VRFLootDrop.sol";
import { IGameItems } from "../src/interfaces/IGameItems.sol";

contract MockVRFCoordinatorV2Plus {
    uint256 public nextRequestId = 100;
    VRFV2PlusClient.RandomWordsRequest public lastRequest;

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId)
    {
        lastRequest = req;
        requestId = nextRequestId++;
    }

    function lastRequestSummary() external view returns (uint256 subId, uint32 numWords) {
        return (lastRequest.subId, lastRequest.numWords);
    }
}

contract ExposedVRFLootDrop is VRFLootDrop {
    constructor(
        IGameItems gameItems_,
        address vrfCoordinator,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        address admin
    ) VRFLootDrop(gameItems_, vrfCoordinator, subscriptionId_, keyHash_, admin) { }

    function exposedFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        fulfillRandomWords(requestId, randomWords);
    }
}

contract VRFLootDropTest is Test {
    GameItems internal items;
    MockVRFCoordinatorV2Plus internal coordinator;
    ExposedVRFLootDrop internal lootDrop;

    address internal admin = address(this);
    address internal player = address(0xBEEF);
    bytes32 internal keyHash = keccak256("keyhash");

    function setUp() public {
        items = new GameItems("ipfs://items/{id}.json", admin);
        coordinator = new MockVRFCoordinatorV2Plus();
        lootDrop = new ExposedVRFLootDrop(
            IGameItems(address(items)), address(coordinator), 7, keyHash, admin
        );
        items.grantRole(items.MINTER_ROLE(), address(lootDrop));
    }

    function testSetVrfConfigUpdatesParameters() public {
        bytes32 nextKeyHash = keccak256("next");
        lootDrop.setVrfConfig(nextKeyHash, 300_000, 5);

        assertEq(lootDrop.keyHash(), nextKeyHash);
        assertEq(lootDrop.callbackGasLimit(), 300_000);
        assertEq(lootDrop.requestConfirmations(), 5);
    }

    function testSetLootTableUpdatesWeights() public {
        lootDrop.setLootTable(_lootEntries());

        assertEq(lootDrop.totalWeight(), 100);
        (uint256 itemId, uint32 weight, uint16 minAmount, uint16 maxAmount) = lootDrop.lootTable(0);
        assertEq(itemId, 20);
        assertEq(weight, 70);
        assertEq(minAmount, 1);
        assertEq(maxAmount, 2);
    }

    function testSetLootTableRejectsEmptyTable() public {
        VRFLootDrop.LootEntry[] memory entries = new VRFLootDrop.LootEntry[](0);
        vm.expectRevert(bytes("Loot: empty table"));
        lootDrop.setLootTable(entries);
    }

    function testSetLootTableRejectsZeroWeight() public {
        VRFLootDrop.LootEntry[] memory entries = new VRFLootDrop.LootEntry[](1);
        entries[0] = VRFLootDrop.LootEntry({ itemId: 20, weight: 0, minAmount: 1, maxAmount: 1 });

        vm.expectRevert(bytes("Loot: zero weight"));
        lootDrop.setLootTable(entries);
    }

    function testSetLootTableRejectsBadAmountRange() public {
        VRFLootDrop.LootEntry[] memory entries = new VRFLootDrop.LootEntry[](1);
        entries[0] = VRFLootDrop.LootEntry({ itemId: 20, weight: 1, minAmount: 2, maxAmount: 1 });

        vm.expectRevert(bytes("Loot: bad amount"));
        lootDrop.setLootTable(entries);
    }

    function testRequestLootStoresPlayerAndCoordinatorRequest() public {
        lootDrop.setLootTable(_lootEntries());

        vm.prank(player);
        uint256 requestId = lootDrop.requestLoot();

        (address requester, bool fulfilled) = lootDrop.requests(requestId);
        assertEq(requester, player);
        assertFalse(fulfilled);
        (uint256 subId, uint32 numWords) = coordinator.lastRequestSummary();
        assertEq(subId, 7);
        assertEq(numWords, 1);
    }

    function testRequestLootRejectsMissingTable() public {
        vm.prank(player);
        vm.expectRevert(bytes("Loot: table not set"));
        lootDrop.requestLoot();
    }

    function testFulfillRandomWordsMintsWeightedLoot() public {
        lootDrop.setLootTable(_lootEntries());
        vm.prank(player);
        uint256 requestId = lootDrop.requestLoot();

        uint256[] memory words = new uint256[](1);
        words[0] = 72;
        lootDrop.exposedFulfillRandomWords(requestId, words);

        (address requester, bool fulfilled) = lootDrop.requests(requestId);
        assertEq(requester, player);
        assertTrue(fulfilled);
        assertEq(items.balanceOf(player, 21), 1);
    }

    function testFulfillRandomWordsRejectsUnknownRequest() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 1;

        vm.expectRevert(bytes("Loot: unknown request"));
        lootDrop.exposedFulfillRandomWords(999, words);
    }

    function testFulfillRandomWordsRejectsDuplicateFulfillment() public {
        lootDrop.setLootTable(_lootEntries());
        vm.prank(player);
        uint256 requestId = lootDrop.requestLoot();
        uint256[] memory words = new uint256[](1);
        words[0] = 1;

        lootDrop.exposedFulfillRandomWords(requestId, words);
        vm.expectRevert(bytes("Loot: fulfilled"));
        lootDrop.exposedFulfillRandomWords(requestId, words);
    }

    function _lootEntries() internal pure returns (VRFLootDrop.LootEntry[] memory entries) {
        entries = new VRFLootDrop.LootEntry[](3);
        entries[0] = VRFLootDrop.LootEntry({ itemId: 20, weight: 70, minAmount: 1, maxAmount: 2 });
        entries[1] = VRFLootDrop.LootEntry({ itemId: 21, weight: 25, minAmount: 1, maxAmount: 1 });
        entries[2] = VRFLootDrop.LootEntry({ itemId: 22, weight: 5, minAmount: 1, maxAmount: 1 });
    }
}
