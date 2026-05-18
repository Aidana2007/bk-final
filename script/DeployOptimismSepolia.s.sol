// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { DemoERC20 } from "../src/DemoERC20.sol";
import { GameItems } from "../src/GameItems.sol";
import { GameItemMarketplace } from "../src/GameItemMarketplace.sol";
import { IGameItems } from "../src/interfaces/IGameItems.sol";
import { CraftingSystem } from "../src/CraftingSystem.sol";
import { GamePriceOracle } from "../src/GamePriceOracle.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";
import { VRFLootDrop } from "../src/VRFLootDrop.sol";
import { AMMFactory } from "../src/AMMFactory.sol";
import { ConstantProductAMM } from "../src/ConstantProductAMM.sol";

contract DeployOptimismSepolia is Script {
    uint256 private constant INITIAL_GOV_SUPPLY = 1_000_000 ether;
    uint256 private constant DEMO_TOKEN_SUPPLY = 1_000_000 ether;
    uint256 private constant AMM_INITIAL_LIQUIDITY = 10_000 ether;
    uint256 private constant DEMO_LISTING_PRICE = 0.01 ether;

    struct CoreDeployment {
        ConstantProductAMM implementation;
        AMMFactory factory;
        DemoERC20 tokenA;
        DemoERC20 tokenB;
        address pool;
    }

    struct GameDeployment {
        GameItems gameItems;
        CraftingSystem crafting;
        GamePriceOracle oracle;
        VRFLootDrop lootDrop;
        GameItemMarketplace marketplace;
    }

    struct GovernanceDeployment {
        GovernanceToken governanceToken;
        TimelockController timelock;
        ProtocolGovernor governor;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        CoreDeployment memory core = _deployCore(deployer);
        GameDeployment memory game = _deployGameSystems(deployer);
        GovernanceDeployment memory governance = _deployGovernance(deployer);

        _logDeployment(core, game, governance);

        vm.stopBroadcast();
    }

    function _deployCore(address deployer) private returns (CoreDeployment memory core) {
        ConstantProductAMM implementation = new ConstantProductAMM();
        AMMFactory factory = new AMMFactory(address(implementation), deployer, deployer);
        DemoERC20 tokenA = new DemoERC20("Demo Gold", "GOLD", deployer);
        DemoERC20 tokenB = new DemoERC20("Demo Crystal", "CRYSTAL", deployer);
        tokenA.mint(deployer, DEMO_TOKEN_SUPPLY);
        tokenB.mint(deployer, DEMO_TOKEN_SUPPLY);

        (address pool,) = factory.createPool(address(tokenA), address(tokenB));
        tokenA.approve(pool, AMM_INITIAL_LIQUIDITY);
        tokenB.approve(pool, AMM_INITIAL_LIQUIDITY);
        ConstantProductAMM(pool)
            .addLiquidity(AMM_INITIAL_LIQUIDITY, AMM_INITIAL_LIQUIDITY, 0, 0, deployer);

        core = CoreDeployment({
            implementation: implementation,
            factory: factory,
            tokenA: tokenA,
            tokenB: tokenB,
            pool: pool
        });
    }

    function _deployGameSystems(address deployer) private returns (GameDeployment memory game) {
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");

        GameItems gameItems = new GameItems("ipfs://game-items/{id}.json", deployer);
        CraftingSystem crafting = new CraftingSystem(IGameItems(address(gameItems)), deployer);
        GamePriceOracle oracle = new GamePriceOracle(deployer);
        VRFLootDrop lootDrop = new VRFLootDrop(
            IGameItems(address(gameItems)), vrfCoordinator, subscriptionId, keyHash, deployer
        );

        gameItems.grantRole(gameItems.MINTER_ROLE(), address(crafting));
        gameItems.grantRole(gameItems.MINTER_ROLE(), address(lootDrop));

        GameItemMarketplace marketplace =
            new GameItemMarketplace(IGameItems(address(gameItems)), deployer);
        gameItems.grantRole(gameItems.MINTER_ROLE(), address(marketplace));
        marketplace.createListing(30, 1, DEMO_LISTING_PRICE, payable(deployer));

        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](2);
        ingredients[0] = CraftingSystem.Ingredient({ itemId: 1, amount: 2 });
        ingredients[1] = CraftingSystem.Ingredient({ itemId: 2, amount: 1 });
        crafting.createRecipe(10, 1, ingredients);
        gameItems.mint(deployer, 1, 10, "");
        gameItems.mint(deployer, 2, 10, "");

        VRFLootDrop.LootEntry[] memory lootEntries = new VRFLootDrop.LootEntry[](3);
        lootEntries[0] =
            VRFLootDrop.LootEntry({ itemId: 20, weight: 70, minAmount: 1, maxAmount: 2 });
        lootEntries[1] =
            VRFLootDrop.LootEntry({ itemId: 21, weight: 25, minAmount: 1, maxAmount: 1 });
        lootEntries[2] =
            VRFLootDrop.LootEntry({ itemId: 22, weight: 5, minAmount: 1, maxAmount: 1 });
        lootDrop.setLootTable(lootEntries);

        game = GameDeployment({
            gameItems: gameItems,
            crafting: crafting,
            oracle: oracle,
            lootDrop: lootDrop,
            marketplace: marketplace
        });
    }

    function _deployGovernance(address deployer)
        private
        returns (GovernanceDeployment memory governance)
    {
        GovernanceToken governanceToken = new GovernanceToken(
            "Capstone Governance", "CGOV", INITIAL_GOV_SUPPLY, deployer, deployer
        );
        governanceToken.delegate(deployer);

        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock = new TimelockController(2 days, proposers, executors, deployer);
        uint256 threshold = (INITIAL_GOV_SUPPLY * 100) / 10_000;
        ProtocolGovernor governor = new ProtocolGovernor(governanceToken, timelock, threshold);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        governance = GovernanceDeployment({
            governanceToken: governanceToken, timelock: timelock, governor: governor
        });
    }

    function _logDeployment(
        CoreDeployment memory core,
        GameDeployment memory game,
        GovernanceDeployment memory governance
    ) private pure {
        console2.log("AMM_IMPLEMENTATION=", address(core.implementation));
        console2.log("AMM_FACTORY=", address(core.factory));
        console2.log("DEMO_TOKEN_A=", address(core.tokenA));
        console2.log("DEMO_TOKEN_B=", address(core.tokenB));
        console2.log("AMM_POOL=", core.pool);
        console2.log("GAME_ITEMS=", address(game.gameItems));
        console2.log("CRAFTING_SYSTEM=", address(game.crafting));
        console2.log("GAME_PRICE_ORACLE=", address(game.oracle));
        console2.log("VRF_LOOT_DROP=", address(game.lootDrop));
        console2.log("MARKETPLACE=", address(game.marketplace));
        console2.log("GOVERNANCE_TOKEN=", address(governance.governanceToken));
        console2.log("TIMELOCK=", address(governance.timelock));
        console2.log("GOVERNOR=", address(governance.governor));
        console2.log("BOOTSTRAP_RECIPE_ID=1");
        console2.log("BOOTSTRAP_MARKETPLACE_LISTING_ID=1");
    }
}
