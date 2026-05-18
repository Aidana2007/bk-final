// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IAMMLPToken } from "./interfaces/IAMMLPToken.sol";

/// @notice Upgrade-safe reentrancy guard using namespaced storage for proxy deployments.
abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    bytes32 private constant REENTRANCY_GUARD_STORAGE_LOCATION =
        0x56f5a5185e86f8629e18fee3978b5b7fdc5ec3f3dd6cb5f602d6593867383c00;

    struct ReentrancyGuardStorage {
        uint256 status;
    }

    error ReentrantCall();

    modifier nonReentrant() {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        if ($.status == ENTERED) revert ReentrantCall();
        $.status = ENTERED;
        _;
        $.status = NOT_ENTERED;
    }

    function __ReentrancyGuard_init() internal onlyInitializing {
        _getReentrancyGuardStorage().status = NOT_ENTERED;
    }

    function _getReentrancyGuardStorage() private pure returns (ReentrancyGuardStorage storage $) {
        assembly {
            $.slot := REENTRANCY_GUARD_STORAGE_LOCATION
        }
    }
}

/// @notice UUPS-upgradeable constant-product AMM with 0.3% swap fees and LP shares.
contract ConstantProductAMM is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant FEE_BPS = 30;
    uint256 public constant FEE_DENOMINATOR = BPS;
    uint256 public constant FEE_MULTIPLIER = 9_970;
    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
    address public constant MINIMUM_LIQUIDITY_RECIPIENT = address(1);

    struct AMMStorage {
        IERC20 token0;
        IERC20 token1;
        IAMMLPToken lpToken;
        address factory;
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
    }

    bytes32 private constant AMM_STORAGE_LOCATION =
        0x26ea05dddf5741b534c80cad9fe3b7f75dfc2be1f415470e6b2835ba2b89ed00;

    uint256[50] private __gap;

    error ZeroAddress();
    error IdenticalTokens();
    error InvalidToken();
    error InsufficientAmount();
    error InsufficientLiquidity();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error KInvariantDecreased(uint256 beforeK, uint256 afterK);
    error ReserveOverflow();

    event LiquidityAdded(
        address indexed provider,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed provider,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event Swap(
        address indexed trader,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address to
    );
    event ReservesUpdated(uint112 reserve0, uint112 reserve1);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a pool proxy with its token pair, LP token, factory, and upgrade admin.
    function initialize(
        address upgradeAdmin,
        address token0_,
        address token1_,
        address lpToken_,
        address factory_
    ) external initializer {
        if (
            upgradeAdmin == address(0) || token0_ == address(0) || token1_ == address(0)
                || lpToken_ == address(0) || factory_ == address(0)
        ) revert ZeroAddress();
        if (token0_ == token1_) revert IdenticalTokens();

        __Ownable_init(upgradeAdmin);
        __Pausable_init();
        __ReentrancyGuard_init();

        AMMStorage storage $ = _getAMMStorage();
        $.token0 = IERC20(token0_);
        $.token1 = IERC20(token1_);
        $.lpToken = IAMMLPToken(lpToken_);
        $.factory = factory_;
    }

    /// @notice Adds liquidity at the current pool ratio and mints proportional LP shares.
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount0Desired == 0 || amount1Desired == 0) revert InsufficientAmount();

        AMMStorage storage $ = _getAMMStorage();
        (uint112 reserve0_, uint112 reserve1_) = ($.reserve0, $.reserve1);

        if (reserve0_ == 0 && reserve1_ == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            liquidity = _sqrt(amount0 * amount1);
            if (liquidity <= MINIMUM_LIQUIDITY) revert InsufficientLiquidity();
            liquidity -= MINIMUM_LIQUIDITY;
        } else {
            uint256 amount1Optimal = quote(amount0Desired, reserve0_, reserve1_);
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                amount0 = quote(amount1Desired, reserve1_, reserve0_);
                amount1 = amount1Desired;
            }
            if (amount0 == 0 || amount1 == 0) revert InsufficientAmount();
            if (amount0 < amount0Min) revert SlippageExceeded(amount0, amount0Min);
            if (amount1 < amount1Min) revert SlippageExceeded(amount1, amount1Min);

            uint256 totalSupply = $.lpToken.totalSupply();
            liquidity =
                _min((amount0 * totalSupply) / reserve0_, (amount1 * totalSupply) / reserve1_);
            if (liquidity == 0) revert InsufficientLiquidity();
        }

        if (amount0 < amount0Min) revert SlippageExceeded(amount0, amount0Min);
        if (amount1 < amount1Min) revert SlippageExceeded(amount1, amount1Min);

        $.token0.safeTransferFrom(msg.sender, address(this), amount0);
        $.token1.safeTransferFrom(msg.sender, address(this), amount1);

        if ($.lpToken.totalSupply() == 0) {
            $.lpToken.mint(MINIMUM_LIQUIDITY_RECIPIENT, MINIMUM_LIQUIDITY);
        }
        $.lpToken.mint(to, liquidity);

        _update($, reserve0_ + amount0, reserve1_ + amount1);
        emit LiquidityAdded(msg.sender, to, amount0, amount1, liquidity);
    }

    /// @notice Burns LP shares and returns the proportional token reserves to `to`.
    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1)
    {
        if (to == address(0)) revert ZeroAddress();
        if (liquidity == 0) revert InsufficientAmount();

        AMMStorage storage $ = _getAMMStorage();
        (uint112 reserve0_, uint112 reserve1_) = ($.reserve0, $.reserve1);
        uint256 totalSupply = $.lpToken.totalSupply();
        if (totalSupply == 0) revert InsufficientLiquidity();

        amount0 = (liquidity * reserve0_) / totalSupply;
        amount1 = (liquidity * reserve1_) / totalSupply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();
        if (amount0 < amount0Min) revert SlippageExceeded(amount0, amount0Min);
        if (amount1 < amount1Min) revert SlippageExceeded(amount1, amount1Min);

        IERC20(address($.lpToken)).safeTransferFrom(msg.sender, address(this), liquidity);
        $.lpToken.burn(address(this), liquidity);

        _update($, reserve0_ - amount0, reserve1_ - amount1);
        $.token0.safeTransfer(to, amount0);
        $.token1.safeTransfer(to, amount1);

        emit LiquidityRemoved(msg.sender, to, amount0, amount1, liquidity);
    }

    /// @notice Swaps an exact input amount of one pool token for the other pool token.
    function swapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (to == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert InsufficientAmount();

        AMMStorage storage $ = _getAMMStorage();
        bool zeroForOne = tokenIn == address($.token0);
        if (!zeroForOne && tokenIn != address($.token1)) revert InvalidToken();

        amountOut = _swap($, zeroForOne, amountIn, amountOutMin, to);
    }

    function _swap(
        AMMStorage storage $,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) private returns (uint256 amountOut) {
        (uint112 reserve0_, uint112 reserve1_) = ($.reserve0, $.reserve1);
        if (reserve0_ == 0 || reserve1_ == 0) revert InsufficientLiquidity();

        uint256 beforeK = uint256(reserve0_) * reserve1_;
        if (zeroForOne) {
            amountOut = getAmountOut(amountIn, reserve0_, reserve1_);
            if (amountOut == 0) revert InsufficientLiquidity();
            if (amountOut < amountOutMin) revert SlippageExceeded(amountOut, amountOutMin);

            uint256 nextReserve0 = reserve0_ + amountIn;
            uint256 nextReserve1 = reserve1_ - amountOut;
            if (nextReserve0 * nextReserve1 < beforeK) {
                revert KInvariantDecreased(beforeK, nextReserve0 * nextReserve1);
            }

            $.token0.safeTransferFrom(msg.sender, address(this), amountIn);
            _update($, nextReserve0, nextReserve1);
            $.token1.safeTransfer(to, amountOut);
            emit Swap(msg.sender, address($.token0), address($.token1), amountIn, amountOut, to);
            return amountOut;
        }

        amountOut = getAmountOut(amountIn, reserve1_, reserve0_);
        if (amountOut == 0) revert InsufficientLiquidity();
        if (amountOut < amountOutMin) revert SlippageExceeded(amountOut, amountOutMin);

        uint256 newReserve0 = reserve0_ - amountOut;
        uint256 newReserve1 = reserve1_ + amountIn;
        uint256 afterK = newReserve0 * newReserve1;
        if (afterK < beforeK) revert KInvariantDecreased(beforeK, afterK);

        $.token1.safeTransferFrom(msg.sender, address(this), amountIn);
        _update($, newReserve0, newReserve1);
        $.token0.safeTransfer(to, amountOut);

        emit Swap(msg.sender, address($.token1), address($.token0), amountIn, amountOut, to);
    }

    /// @notice Returns output amount for an exact-input swap after the 0.3% fee.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256)
    {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) revert InsufficientAmount();
        uint256 amountInWithFee = amountIn * FEE_MULTIPLIER;
        return (amountInWithFee * reserveOut) / ((reserveIn * FEE_DENOMINATOR) + amountInWithFee);
    }

    /// @notice Pure Solidity benchmark implementation of the swap output formula.
    function getAmountOutSolidityBenchmark(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256)
    {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0) revert InsufficientAmount();
        if (reserveOut == 0) revert InsufficientAmount();
        uint256 amountInWithFee = amountIn;
        amountInWithFee *= FEE_MULTIPLIER;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        return numerator / denominator;
    }

    /// @notice Assembly benchmark implementation of the swap output formula.
    function getAmountOutYul(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 out)
    {
        assembly ("memory-safe") {
            if iszero(and(and(amountIn, reserveIn), reserveOut)) {
                mstore(0x00, 0x5945ea56)
                revert(0x1c, 0x04)
            }
            let amountInWithFee := mul(amountIn, FEE_MULTIPLIER)
            out := div(
                mul(amountInWithFee, reserveOut),
                add(mul(reserveIn, FEE_DENOMINATOR), amountInWithFee)
            )
        }
    }

    /// @notice Quotes the amount of token B equivalent to `amountA` at the current reserve ratio.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        returns (uint256)
    {
        if (amountA == 0 || reserveA == 0 || reserveB == 0) revert InsufficientAmount();
        return (amountA * reserveB) / reserveA;
    }

    /// @notice Returns the pool token addresses and LP token address.
    function poolTokens()
        external
        view
        returns (address token0_, address token1_, address lpToken_)
    {
        AMMStorage storage $ = _getAMMStorage();
        return (address($.token0), address($.token1), address($.lpToken));
    }

    /// @notice Returns the latest stored reserves and update timestamp.
    function getReserves()
        public
        view
        returns (uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_)
    {
        AMMStorage storage $ = _getAMMStorage();
        return ($.reserve0, $.reserve1, $.blockTimestampLast);
    }

    /// @notice Returns the current reserve product.
    function kLast() external view returns (uint256) {
        AMMStorage storage $ = _getAMMStorage();
        return uint256($.reserve0) * $.reserve1;
    }

    /// @notice Returns the factory that deployed this pool.
    function factory() external view returns (address) {
        return _getAMMStorage().factory;
    }

    /// @notice Pauses liquidity and swap operations.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes liquidity and swap operations.
    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    function _update(AMMStorage storage $, uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert ReserveOverflow();
        $.reserve0 = uint112(balance0);
        $.reserve1 = uint112(balance1);
        $.blockTimestampLast = uint32(block.timestamp);
        emit ReservesUpdated(uint112(balance0), uint112(balance1));
    }

    function _getAMMStorage() private pure returns (AMMStorage storage $) {
        assembly {
            $.slot := AMM_STORAGE_LOCATION
        }
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = (y / 2) + 1;
            while (x < z) {
                z = x;
                x = ((y / x) + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
