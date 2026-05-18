// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { AMMFactory } from "../src/AMMFactory.sol";
import { AMMLPToken } from "../src/AMMLPToken.sol";
import { ConstantProductAMM } from "../src/ConstantProductAMM.sol";
import { CraftingSystem } from "../src/CraftingSystem.sol";
import { DemoERC20 } from "../src/DemoERC20.sol";
import { GameItemMarketplace } from "../src/GameItemMarketplace.sol";
import { GameItems } from "../src/GameItems.sol";
import { GamePriceOracle } from "../src/GamePriceOracle.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { ProtocolGovernor } from "../src/ProtocolGovernor.sol";
import { RentalVault } from "../src/RentalVault.sol";
import { TreasuryVault } from "../src/TreasuryVault.sol";
import { IGameItems } from "../src/interfaces/IGameItems.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";

interface IUniswapV3FactoryRead {
    function owner() external view returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

contract AMMLPTokenCoverageTest is Test {
    AMMLPToken internal lp;
    address internal owner = address(0xA11CE);
    address internal user = address(0xBEEF);

    function setUp() public {
        lp = new AMMLPToken("LP Token", "LPT", owner);
    }

    function testLPTokenMetadata() public view {
        assertEq(lp.name(), "LP Token");
        assertEq(lp.symbol(), "LPT");
        assertEq(lp.decimals(), 18);
    }

    function testLPTokenConstructorRejectsZeroOwner() public {
        vm.expectRevert();
        new AMMLPToken("LP Token", "LPT", address(0));
    }

    function testLPTokenOwnerCanMint() public {
        vm.prank(owner);
        lp.mint(user, 100);
        assertEq(lp.balanceOf(user), 100);
    }

    function testLPTokenNonOwnerCannotMint() public {
        vm.prank(user);
        vm.expectRevert();
        lp.mint(user, 100);
    }

    function testLPTokenOwnerCanBurn() public {
        vm.startPrank(owner);
        lp.mint(user, 100);
        lp.burn(user, 40);
        vm.stopPrank();
        assertEq(lp.balanceOf(user), 60);
    }

    function testLPTokenBurnTooMuchReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        lp.burn(user, 1);
    }
}

contract AMMFactoryCoverageTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal implementation;
    AMMFactory internal factory;
    address internal owner = address(0xA11CE);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        implementation = new ConstantProductAMM();
        factory = new AMMFactory(address(implementation), owner, owner);
    }

    function testFactoryConstructorRejectsZeroImplementation() public {
        vm.expectRevert(AMMFactory.ZeroAddress.selector);
        new AMMFactory(address(0), owner, owner);
    }

    function testFactoryConstructorRejectsZeroUpgradeAdmin() public {
        vm.expectRevert(AMMFactory.ZeroAddress.selector);
        new AMMFactory(address(implementation), address(0), owner);
    }

    function testFactoryConstructorRejectsZeroOwner() public {
        vm.expectRevert();
        new AMMFactory(address(implementation), owner, address(0));
    }

    function testFactoryInitialPoolCountIsZero() public view {
        assertEq(factory.allPoolsLength(), 0);
    }

    function testFactorySortTokensCanonicalizesPair() public view {
        (address token0, address token1) = factory.sortTokens(address(tokenB), address(tokenA));
        assertLt(uint160(token0), uint160(token1));
    }

    function testFactorySortTokensRejectsZero() public {
        vm.expectRevert(AMMFactory.ZeroAddress.selector);
        factory.sortTokens(address(0), address(tokenA));
    }

    function testFactorySortTokensRejectsIdentical() public {
        vm.expectRevert(AMMFactory.IdenticalTokens.selector);
        factory.sortTokens(address(tokenA), address(tokenA));
    }

    function testFactoryNonOwnerCannotCreatePool() public {
        vm.expectRevert();
        factory.createPool(address(tokenA), address(tokenB));
    }

    function testFactoryPredictDeterministicPoolIsOrderIndependent() public view {
        bytes32 salt = keccak256("salt");
        (address poolAB, address lpAB) =
            factory.predictDeterministicPool(address(tokenA), address(tokenB), salt);
        (address poolBA, address lpBA) =
            factory.predictDeterministicPool(address(tokenB), address(tokenA), salt);
        assertEq(poolAB, poolBA);
        assertEq(lpAB, lpBA);
    }
}

contract AMMCoverageTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    ConstantProductAMM internal implementation;
    ConstantProductAMM internal pool;
    address internal owner = address(0xA11CE);
    address internal user = address(0xBEEF);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        tokenC = new MockERC20("Token C", "TKNC");
        implementation = new ConstantProductAMM();
        AMMFactory factory = new AMMFactory(address(implementation), owner, owner);
        vm.prank(owner);
        (address poolAddress,) = factory.createPool(address(tokenA), address(tokenB));
        pool = ConstantProductAMM(poolAddress);

        tokenA.mint(user, 10_000 ether);
        tokenB.mint(user, 10_000 ether);
        vm.startPrank(user);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        pool.addLiquidity(1_000 ether, 1_000 ether, 1, 1, user);
        vm.stopPrank();
    }

    function testAMMImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(
            owner, address(tokenA), address(tokenB), address(1), address(this)
        );
    }

    function testAMMFactoryGetterIsSet() public view {
        assertTrue(pool.factory() != address(0));
    }

    function testAMMQuoteReturnsRatio() public view {
        assertEq(pool.quote(5 ether, 10 ether, 20 ether), 10 ether);
    }

    function testAMMQuoteRejectsZero() public {
        vm.expectRevert(ConstantProductAMM.InsufficientAmount.selector);
        pool.quote(0, 10 ether, 20 ether);
    }

    function testAMMGetAmountOutRejectsZeroInput() public {
        vm.expectRevert(ConstantProductAMM.InsufficientAmount.selector);
        pool.getAmountOut(0, 1 ether, 1 ether);
    }

    function testAMMAddLiquidityRejectsZeroRecipient() public {
        vm.prank(user);
        vm.expectRevert(ConstantProductAMM.ZeroAddress.selector);
        pool.addLiquidity(1 ether, 1 ether, 1, 1, address(0));
    }

    function testAMMAddLiquidityRejectsZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(ConstantProductAMM.InsufficientAmount.selector);
        pool.addLiquidity(0, 1 ether, 1, 1, user);
    }

    function testAMMSwapRejectsInvalidToken() public {
        vm.prank(user);
        vm.expectRevert(ConstantProductAMM.InvalidToken.selector);
        pool.swapExactTokenForToken(address(tokenC), 1 ether, 1, user);
    }

    function testAMMSwapRejectsZeroRecipient() public {
        vm.prank(user);
        vm.expectRevert(ConstantProductAMM.ZeroAddress.selector);
        pool.swapExactTokenForToken(address(tokenA), 1 ether, 1, address(0));
    }

    function testAMMSwapRejectsZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(ConstantProductAMM.InsufficientAmount.selector);
        pool.swapExactTokenForToken(address(tokenA), 0, 1, user);
    }

    function testAMMRemoveLiquidityRejectsZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(ConstantProductAMM.InsufficientAmount.selector);
        pool.removeLiquidity(0, 1, 1, user);
    }

    function testAMMOnlyOwnerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        pool.pause();
    }
}

contract GovernanceTokenCoverageTest is Test {
    GovernanceToken internal token;
    address internal admin = address(this);
    address internal treasury = address(0x7777);
    address internal user = address(0xBEEF);

    function setUp() public {
        token = new GovernanceToken("Governance Token", "GOV", 1_000 ether, admin, treasury);
    }

    function testGovernanceTokenConstructorRejectsZeroAdmin() public {
        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        new GovernanceToken("Governance Token", "GOV", 1_000 ether, address(0), treasury);
    }

    function testGovernanceTokenConstructorRejectsZeroTreasury() public {
        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        new GovernanceToken("Governance Token", "GOV", 1_000 ether, admin, address(0));
    }

    function testGovernanceTokenInitialSupplyGoesToTreasury() public view {
        assertEq(token.balanceOf(treasury), 1_000 ether);
    }

    function testGovernanceTokenAdminCanMint() public {
        token.mint(user, 10 ether);
        assertEq(token.balanceOf(user), 10 ether);
    }

    function testGovernanceTokenNonMinterCannotMint() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 10 ether);
    }

    function testGovernanceTokenAdminCanBurn() public {
        token.burn(treasury, 10 ether);
        assertEq(token.balanceOf(treasury), 990 ether);
    }

    function testGovernanceTokenUsesTimestampClock() public view {
        assertEq(token.clock(), uint48(block.timestamp));
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
    }
}

contract VaultCoverageTest is Test {
    MockERC20 internal asset;
    TreasuryVault internal vault;
    address internal admin = address(this);
    address internal recipient = address(0x7777);
    address internal user = address(0xBEEF);

    function setUp() public {
        asset = new MockERC20("Mock Asset", "ASSET");
        vault = new TreasuryVault(asset, "Vault Share", "vSHARE", admin, recipient, 100 ether);
        asset.mint(user, 200 ether);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);
    }

    function testVaultMaxDepositRespectsCap() public view {
        assertEq(vault.maxDeposit(user), 100 ether);
    }

    function testVaultDepositReducesRemainingCap() public {
        vm.prank(user);
        vault.deposit(25 ether, user);
        assertEq(vault.maxDeposit(user), 75 ether);
    }

    function testVaultPauseSetsMaxDepositToZero() public {
        vault.pause();
        assertEq(vault.maxDeposit(user), 0);
    }

    function testVaultSetDepositCap() public {
        vault.setDepositCap(50 ether);
        assertEq(vault.depositCap(), 50 ether);
    }

    function testVaultSetTreasuryRecipientRejectsZero() public {
        vm.expectRevert(TreasuryVault.ZeroAddress.selector);
        vault.setTreasuryRecipient(address(0));
    }

    function testVaultCannotRescueUnderlyingAsset() public {
        vm.expectRevert(TreasuryVault.AssetRescueForbidden.selector);
        vault.rescueToken(asset, recipient, 1);
    }

    function testVaultCanRescueNonAssetToken() public {
        MockERC20 other = new MockERC20("Other", "OTHER");
        other.mint(address(vault), 10 ether);
        vault.rescueToken(other, recipient, 4 ether);
        assertEq(other.balanceOf(recipient), 4 ether);
    }

    function testVaultNonManagerCannotSetCap() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setDepositCap(10 ether);
    }
}

contract RentalVaultCoverageTest is Test {
    MockERC20 internal paymentToken;
    MockERC721 internal nft;
    RentalVault internal rental;
    address internal admin = address(this);
    address internal lender = address(0xA11CE);
    address internal renter = address(0xBEEF);
    address internal feeRecipient = address(0xFEE);

    function setUp() public {
        paymentToken = new MockERC20("Payment", "PAY");
        nft = new MockERC721("Rental NFT", "RNFT");
        rental = new RentalVault(paymentToken, admin, feeRecipient, 250);
        nft.mint(lender);
        paymentToken.mint(renter, 100 ether);
    }

    function testRentalConstructorRejectsInvalidFee() public {
        vm.expectRevert(RentalVault.InvalidFeeBps.selector);
        new RentalVault(paymentToken, admin, feeRecipient, 10_001);
    }

    function testRentalSetFeeConfig() public {
        rental.setFeeConfig(300, address(0x1234));
        assertEq(rental.protocolFeeBps(), 300);
        assertEq(rental.feeRecipient(), address(0x1234));
    }

    function testRentalSetFeeConfigRejectsZeroRecipient() public {
        vm.expectRevert(RentalVault.ZeroAddress.selector);
        rental.setFeeConfig(100, address(0));
    }

    function testRentalPauseBlocksOfferCreation() public {
        rental.pause();
        vm.startPrank(lender);
        nft.approve(address(rental), 1);
        vm.expectRevert();
        rental.createOffer(
            IERC721(address(nft)),
            1,
            renter,
            uint64(block.timestamp + 1),
            uint64(block.timestamp + 2),
            1,
            1
        );
        vm.stopPrank();
    }

    function testRentalCreateOfferRejectsBadWindow() public {
        vm.startPrank(lender);
        nft.approve(address(rental), 1);
        vm.expectRevert(RentalVault.InvalidTimeWindow.selector);
        rental.createOffer(
            IERC721(address(nft)), 1, renter, uint64(block.timestamp), uint64(block.timestamp), 1, 1
        );
        vm.stopPrank();
    }

    function testRentalSettleRejectsUnacceptedOffer() public {
        bytes32 offerId = _createOffer();
        vm.expectRevert(RentalVault.OfferNotAccepted.selector);
        rental.settleOffer(offerId, false);
    }

    function testRentalSettleRejectsBeforeEnd() public {
        bytes32 offerId = _createOffer();
        vm.startPrank(renter);
        paymentToken.approve(address(rental), type(uint256).max);
        rental.acceptOffer(offerId);
        nft.approve(address(rental), 1);
        vm.stopPrank();

        vm.expectRevert(RentalVault.OfferNotFinished.selector);
        rental.settleOffer(offerId, false);
    }

    function testRentalNonManagerCannotSettle() public {
        bytes32 offerId = _createOffer();
        vm.prank(renter);
        vm.expectRevert();
        rental.settleOffer(offerId, false);
    }

    function _createOffer() internal returns (bytes32 offerId) {
        vm.startPrank(lender);
        nft.approve(address(rental), 1);
        offerId = rental.createOffer(
            IERC721(address(nft)),
            1,
            renter,
            uint64(block.timestamp + 1),
            uint64(block.timestamp + 1 days),
            1 ether,
            1 ether
        );
        vm.stopPrank();
    }
}

contract GameSystemsCoverageTest is Test {
    GameItems internal items;
    CraftingSystem internal crafting;
    GameItemMarketplace internal marketplace;
    DemoERC20 internal demoToken;
    address internal admin = address(this);
    address internal player = address(0xBEEF);
    address payable internal seller = payable(address(0x51E11E2));

    function setUp() public {
        items = new GameItems("ipfs://base/{id}.json", admin);
        crafting = new CraftingSystem(IGameItems(address(items)), admin);
        marketplace = new GameItemMarketplace(IGameItems(address(items)), admin);
        demoToken = new DemoERC20("Demo Gold", "GOLD", admin);
        items.grantRole(items.MINTER_ROLE(), address(crafting));
        items.grantRole(items.MINTER_ROLE(), address(marketplace));
        items.mint(player, 1, 10, "");
    }

    function testGameItemsUriFallsBackToBase() public view {
        assertEq(items.uri(1), "ipfs://base/{id}.json");
    }

    function testGameItemsSetItemUriOverridesBase() public {
        items.setItemUri(1, "ipfs://one.json");
        assertEq(items.uri(1), "ipfs://one.json");
    }

    function testGameItemsNonUriManagerCannotSetUri() public {
        vm.prank(player);
        vm.expectRevert();
        items.setItemUri(1, "ipfs://one.json");
    }

    function testGameItemsNonMinterCannotMint() public {
        vm.prank(player);
        vm.expectRevert();
        items.mint(player, 2, 1, "");
    }

    function testGameItemsBatchMint() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 2;
        ids[1] = 3;
        amounts[0] = 4;
        amounts[1] = 5;
        items.mintBatch(player, ids, amounts, "");
        assertEq(items.balanceOf(player, 2), 4);
        assertEq(items.balanceOf(player, 3), 5);
    }

    function testDemoTokenMinterCanMint() public {
        demoToken.mint(player, 100 ether);

        assertEq(demoToken.balanceOf(player), 100 ether);
        assertEq(demoToken.minter(), admin);
    }

    function testDemoTokenNonMinterCannotMint() public {
        vm.prank(player);
        vm.expectRevert(DemoERC20.NotMinter.selector);
        demoToken.mint(player, 1 ether);
    }

    function testCraftingCreateRecipeRejectsZeroOutput() public {
        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](1);
        ingredients[0] = CraftingSystem.Ingredient({ itemId: 1, amount: 1 });
        vm.expectRevert(bytes("Crafting: zero output"));
        crafting.createRecipe(2, 0, ingredients);
    }

    function testCraftingCreateRecipeRejectsNoIngredients() public {
        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](0);
        vm.expectRevert(bytes("Crafting: no ingredients"));
        crafting.createRecipe(2, 1, ingredients);
    }

    function testCraftingInactiveRecipeCannotBeCrafted() public {
        CraftingSystem.Ingredient[] memory ingredients = new CraftingSystem.Ingredient[](1);
        ingredients[0] = CraftingSystem.Ingredient({ itemId: 1, amount: 1 });
        uint256 recipeId = crafting.createRecipe(2, 1, ingredients);
        crafting.setRecipeActive(recipeId, false);

        vm.startPrank(player);
        items.setApprovalForAll(address(crafting), true);
        vm.expectRevert(bytes("Crafting: inactive recipe"));
        crafting.craft(recipeId);
        vm.stopPrank();
    }

    function testMarketplaceCreateAndBuyListing() public {
        uint256 listingId = marketplace.createListing(30, 2, 0.25 ether, seller);
        uint256 sellerBefore = seller.balance;

        vm.deal(player, 1 ether);
        vm.prank(player);
        marketplace.buy{ value: 0.25 ether }(listingId);

        assertEq(items.balanceOf(player, 30), 2);
        assertEq(seller.balance, sellerBefore + 0.25 ether);
    }

    function testMarketplaceCancelDisablesListing() public {
        uint256 listingId = marketplace.createListing(31, 1, 0.1 ether, seller);

        marketplace.cancel(listingId);

        vm.deal(player, 1 ether);
        vm.prank(player);
        vm.expectRevert(GameItemMarketplace.ListingInactive.selector);
        marketplace.buy{ value: 0.1 ether }(listingId);
    }

    function testMarketplaceRejectsInvalidListing() public {
        vm.expectRevert(GameItemMarketplace.InvalidListing.selector);
        marketplace.createListing(0, 1, 0.1 ether, seller);

        vm.expectRevert(GameItemMarketplace.InvalidListing.selector);
        marketplace.createListing(30, 0, 0.1 ether, seller);

        vm.expectRevert(GameItemMarketplace.InvalidListing.selector);
        marketplace.createListing(30, 1, 0, seller);

        vm.expectRevert(GameItemMarketplace.InvalidListing.selector);
        marketplace.createListing(30, 1, 0.1 ether, payable(address(0)));
    }

    function testMarketplaceRejectsIncorrectPayment() public {
        uint256 listingId = marketplace.createListing(32, 1, 0.2 ether, seller);

        vm.deal(player, 1 ether);
        vm.prank(player);
        vm.expectRevert(
            abi.encodeWithSelector(
                GameItemMarketplace.IncorrectPayment.selector, 0.2 ether, 0.1 ether
            )
        );
        marketplace.buy{ value: 0.1 ether }(listingId);
    }

    function testMarketplaceNonManagerCannotCreateOrCancel() public {
        vm.prank(player);
        vm.expectRevert();
        marketplace.createListing(33, 1, 0.1 ether, seller);

        uint256 listingId = marketplace.createListing(33, 1, 0.1 ether, seller);
        vm.prank(player);
        vm.expectRevert();
        marketplace.cancel(listingId);
    }
}

contract OracleCoverageTest is Test {
    GamePriceOracle internal oracle;
    MockAggregatorV3 internal feed;
    bytes32 internal constant ETH_USD = keccak256("ETH/USD");

    function setUp() public {
        oracle = new GamePriceOracle(address(this));
        feed = new MockAggregatorV3(8, 3_000e8, block.timestamp);
    }

    function testOracleSetFeedRejectsZeroAddress() public {
        vm.expectRevert(GamePriceOracle.ZeroAddress.selector);
        oracle.setFeed(ETH_USD, AggregatorV3Interface(address(0)));
    }

    function testOracleSetMaxPriceAgeRejectsZero() public {
        vm.expectRevert(GamePriceOracle.InvalidPrice.selector);
        oracle.setMaxPriceAge(0);
    }

    function testOracleFutureTimestampReverts() public {
        oracle.setFeed(ETH_USD, AggregatorV3Interface(address(feed)));
        feed.setRoundData(3_000e8, block.timestamp + 1);
        vm.expectRevert(GamePriceOracle.InvalidPrice.selector);
        oracle.latestPrice(ETH_USD);
    }
}

contract ForkCoverageTest is Test {
    address private constant OP_SEPOLIA_USDC = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
    address private constant OP_SEPOLIA_UNISWAP_V3_FACTORY =
        0x8CE191193D15ea94e11d327b4c7ad8bbE520f6aF;
    address private constant OP_SEPOLIA_ETH_USD_FEED = 0x61Ec26aA57019C486B10502285c5A3D4A4750AD7;

    function _selectForkOrSkip() private {
        if (!vm.envOr("RUN_FORK_TESTS", false)) {
            vm.skip(true);
        }
        vm.createSelectFork(vm.envString("OPTIMISM_SEPOLIA_RPC_URL"));
    }

    function testForkOptimismSepoliaUSDCMetadata() public {
        _selectForkOrSkip();
        assertGt(IERC20(OP_SEPOLIA_USDC).totalSupply(), 0);
    }

    function testForkOptimismSepoliaUniswapFactoryRead() public {
        _selectForkOrSkip();
        IUniswapV3FactoryRead factory = IUniswapV3FactoryRead(OP_SEPOLIA_UNISWAP_V3_FACTORY);
        assertTrue(factory.owner() != address(0));
        assertEq(factory.feeAmountTickSpacing(3000), 60);
    }

    function testForkOptimismSepoliaChainlinkFeedRead() public {
        _selectForkOrSkip();
        AggregatorV3Interface feed = AggregatorV3Interface(OP_SEPOLIA_ETH_USD_FEED);
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        assertGt(answer, 0);
        assertGt(updatedAt, 0);
    }
}
