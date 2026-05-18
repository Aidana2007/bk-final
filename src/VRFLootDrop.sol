// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    VRFConsumerBaseV2Plus
} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {
    VRFV2PlusClient
} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { IGameItems } from "./interfaces/IGameItems.sol";

contract VRFLootDrop is VRFConsumerBaseV2Plus, AccessControl, ReentrancyGuard {
    bytes32 public constant LOOT_MANAGER_ROLE = keccak256("LOOT_MANAGER_ROLE");

    struct LootEntry {
        uint256 itemId;
        uint32 weight;
        uint16 minAmount;
        uint16 maxAmount;
    }

    struct RequestStatus {
        address player;
        bool fulfilled;
    }

    IGameItems public immutable gameItems;
    uint256 public immutable subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit = 200_000;
    uint16 public requestConfirmations = 3;

    LootEntry[] public lootTable;
    uint32 public totalWeight;
    mapping(uint256 => RequestStatus) public requests;

    event LootTableUpdated(uint256 entries, uint32 totalWeight);
    event LootRequested(uint256 indexed requestId, address indexed player);
    event LootDelivered(
        uint256 indexed requestId, address indexed player, uint256 indexed itemId, uint256 amount
    );

    constructor(
        IGameItems gameItems_,
        address vrfCoordinator,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        address admin
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        gameItems = gameItems_;
        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LOOT_MANAGER_ROLE, admin);
    }

    function setVrfConfig(bytes32 keyHash_, uint32 callbackGasLimit_, uint16 requestConfirmations_)
        external
        onlyRole(LOOT_MANAGER_ROLE)
    {
        keyHash = keyHash_;
        callbackGasLimit = callbackGasLimit_;
        requestConfirmations = requestConfirmations_;
    }

    function setLootTable(LootEntry[] calldata entries) external onlyRole(LOOT_MANAGER_ROLE) {
        require(entries.length > 0, "Loot: empty table");
        delete lootTable;
        uint32 newTotalWeight;

        for (uint256 i = 0; i < entries.length; i++) {
            require(entries[i].weight > 0, "Loot: zero weight");
            require(
                entries[i].minAmount > 0 && entries[i].maxAmount >= entries[i].minAmount,
                "Loot: bad amount"
            );
            lootTable.push(entries[i]);
            newTotalWeight += entries[i].weight;
        }

        totalWeight = newTotalWeight;
        emit LootTableUpdated(entries.length, newTotalWeight);
    }

    function requestLoot() external nonReentrant returns (uint256 requestId) {
        require(totalWeight > 0, "Loot: table not set");
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: false })
                )
            })
        );
        requests[requestId] = RequestStatus({ player: msg.sender, fulfilled: false });
        emit LootRequested(requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)
        internal
        override
    {
        RequestStatus storage request = requests[requestId];
        require(request.player != address(0), "Loot: unknown request");
        require(!request.fulfilled, "Loot: fulfilled");
        request.fulfilled = true;

        LootEntry memory entry = _pickLoot(randomWords[0]);
        uint256 spread = entry.maxAmount - entry.minAmount + 1;
        uint256 amount = entry.minAmount + (randomWords[0] / totalWeight % spread);

        gameItems.mint(request.player, entry.itemId, amount, "");
        emit LootDelivered(requestId, request.player, entry.itemId, amount);
    }

    function _pickLoot(uint256 randomWord) internal view returns (LootEntry memory) {
        uint256 roll = randomWord % totalWeight;
        uint256 cursor;

        for (uint256 i = 0; i < lootTable.length; i++) {
            cursor += lootTable[i].weight;
            if (roll < cursor) {
                return lootTable[i];
            }
        }

        return lootTable[lootTable.length - 1];
    }
}
