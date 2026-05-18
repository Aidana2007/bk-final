// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { AMMLPToken } from "./AMMLPToken.sol";
import { ConstantProductAMM } from "./ConstantProductAMM.sol";

/// @notice Deploys and indexes AMM pools for token pairs using CREATE or CREATE2.
contract AMMFactory is Ownable {
    string private constant LP_TOKEN_NAME = "Capstone AMM LP";
    string private constant LP_TOKEN_SYMBOL = "cAMM-LP";
    string private constant LP_SALT_DOMAIN = "LP";
    string private constant POOL_SALT_DOMAIN = "POOL";

    address public immutable implementation;
    address public immutable upgradeAdmin;

    mapping(address token0 => mapping(address token1 => address pool)) public getPool;
    address[] public allPools;

    error ZeroAddress();
    error IdenticalTokens();
    error PoolExists(address pool);
    error PairNotSorted();

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address indexed pool,
        address lpToken,
        bytes32 salt,
        bool deterministic
    );

    /// @notice Configures the shared AMM implementation, pool upgrade admin, and factory owner.
    constructor(address implementation_, address upgradeAdmin_, address owner_) Ownable(owner_) {
        if (implementation_ == address(0) || upgradeAdmin_ == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }
        implementation = implementation_;
        upgradeAdmin = upgradeAdmin_;
    }

    /// @notice Deploys a pool for `tokenA` and `tokenB` with standard CREATE.
    function createPool(address tokenA, address tokenB)
        external
        onlyOwner
        returns (address pool, address lpToken)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        if (getPool[token0][token1] != address(0)) revert PoolExists(getPool[token0][token1]);

        lpToken = address(new AMMLPToken(LP_TOKEN_NAME, LP_TOKEN_SYMBOL, address(this)));
        pool = address(new ERC1967Proxy(implementation, _initData(token0, token1, lpToken)));
        AMMLPToken(lpToken).transferOwnership(pool);

        _register(token0, token1, pool, lpToken, bytes32(0), false);
    }

    /// @notice Deploys a pool for `tokenA` and `tokenB` with deterministic CREATE2 salts.
    function createPoolDeterministic(address tokenA, address tokenB, bytes32 salt)
        external
        onlyOwner
        returns (address pool, address lpToken)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        if (getPool[token0][token1] != address(0)) revert PoolExists(getPool[token0][token1]);

        bytes32 lpSalt = _lpSalt(token0, token1, salt);
        bytes32 proxySalt = _proxySalt(token0, token1, salt);
        lpToken =
            address(new AMMLPToken{ salt: lpSalt }(LP_TOKEN_NAME, LP_TOKEN_SYMBOL, address(this)));
        pool = address(
            new ERC1967Proxy{ salt: proxySalt }(implementation, _initData(token0, token1, lpToken))
        );
        AMMLPToken(lpToken).transferOwnership(pool);

        _register(token0, token1, pool, lpToken, salt, true);
    }

    /// @notice Predicts the CREATE2 pool and LP token addresses for a sorted pair and public salt.
    function predictDeterministicPool(address tokenA, address tokenB, bytes32 salt)
        external
        view
        returns (address predictedPool, address predictedLPToken)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        predictedLPToken = Create2.computeAddress(
            _lpSalt(token0, token1, salt),
            keccak256(
                abi.encodePacked(
                    type(AMMLPToken).creationCode,
                    abi.encode(LP_TOKEN_NAME, LP_TOKEN_SYMBOL, address(this))
                )
            )
        );
        predictedPool = Create2.computeAddress(
            _proxySalt(token0, token1, salt),
            keccak256(
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(implementation, _initData(token0, token1, predictedLPToken))
                )
            )
        );
    }

    /// @notice Returns the number of pools deployed by this factory.
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Sorts two token addresses so each pair has one canonical storage key.
    function sortTokens(address tokenA, address tokenB)
        public
        pure
        returns (address token0, address token1)
    {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        if (tokenA == tokenB) revert IdenticalTokens();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _register(
        address token0,
        address token1,
        address pool,
        address lpToken,
        bytes32 salt,
        bool deterministic
    ) private {
        getPool[token0][token1] = pool;
        getPool[token1][token0] = pool;
        allPools.push(pool);
        emit PoolCreated(token0, token1, pool, lpToken, salt, deterministic);
    }

    function _initData(address token0, address token1, address lpToken)
        private
        view
        returns (bytes memory)
    {
        return abi.encodeCall(
            ConstantProductAMM.initialize, (upgradeAdmin, token0, token1, lpToken, address(this))
        );
    }

    function _lpSalt(address token0, address token1, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(LP_SALT_DOMAIN, token0, token1, salt));
    }

    function _proxySalt(address token0, address token1, bytes32 salt)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(POOL_SALT_DOMAIN, token0, token1, salt));
    }
}
