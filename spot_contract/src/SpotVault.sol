// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SpotVault · BSC-side custody for ZTDX multi-token spot
/// @notice Custody: native BNB (token=address(0)) + admin-whitelisted ERC20s (initial: USDT).
/// @dev    Backend polls SpotDeposit / SpotWithdrawal events (indexed account,token).
///         Withdrawals require EIP-712 signature from ops backend signer.
///         Nonces per (account, token) tuple, monotonically increasing; used nonces stay used.
contract SpotVault is EIP712, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /// Sentinel for native BNB · matches how backend records "chain-native asset"
    address public constant NATIVE = address(0);

    /// keccak256("SpotReleaseFunds(address account,address token,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant SPOT_RELEASE_FUNDS_TYPEHASH =
        keccak256("SpotReleaseFunds(address account,address token,uint256 value,uint256 nonce,uint256 deadline)");

    /// Backend signer EOA (KMS-derived · rotatable by owner)
    address public backendSigner;

    /// Whitelist · admin controls which ERC20s / NATIVE(=address(0)) may be deposited.
    /// NATIVE is enabled by default in constructor.
    mapping(address => bool) public supportedTokens;

    /// Per-(account, token) used-nonce bitmap.
    mapping(address => mapping(address => mapping(uint256 => bool))) public usedNonces;

    /// Next unused nonce per (account, token) — monotonic.
    mapping(address => mapping(address => uint256)) private _nextNonce;

    // ============================== EVENTS ==============================

    event SpotDeposit(address indexed account, address indexed token, uint256 amount);
    event SpotWithdrawal(address indexed account, address indexed token, uint256 amount, uint256 nonce);
    event BackendSignerRotated(address indexed oldSigner, address indexed newSigner);
    event TokenSupported(address indexed token, bool supported);
    event RescueToken(address indexed token, address indexed to, uint256 amount);

    // ============================== ERRORS ==============================

    error ZeroAddress();
    error ZeroAmount();
    error SignatureExpired();
    error NonceAlreadyUsed(address account, address token, uint256 nonce);
    error InvalidSignature(address recovered, address expected);
    error TokenNotSupported(address token);
    error ValueMismatch(uint256 sent, uint256 expected);
    error NativeTransferFailed();

    // ============================== CONSTRUCTOR ==============================

    /// @param _backendSigner   EOA derived from AWS KMS
    /// @param _owner           Contract admin (KMS EOA for MVP · Safe multisig later)
    /// @param _initialTokens   ERC20 addresses to whitelist at deploy (native BNB always on)
    constructor(address _backendSigner, address _owner, address[] memory _initialTokens)
        EIP712("ZTDX Spot Vault", "1")
        Ownable(_owner)
    {
        if (_backendSigner == address(0) || _owner == address(0)) revert ZeroAddress();
        backendSigner = _backendSigner;

        // Native BNB always supported (cannot be turned off)
        supportedTokens[NATIVE] = true;
        emit TokenSupported(NATIVE, true);

        for (uint256 i = 0; i < _initialTokens.length; i++) {
            address t = _initialTokens[i];
            if (t == address(0)) revert ZeroAddress();
            supportedTokens[t] = true;
            emit TokenSupported(t, true);
        }
    }

    // ============================== DEPOSIT ==============================

    /// @notice Deposit ERC20 · requires prior approve.
    /// @dev    For native BNB, use `depositNative()` instead.
    function deposit(address token, uint256 amount) external nonReentrant whenNotPaused {
        if (token == NATIVE) revert TokenNotSupported(NATIVE); // use depositNative
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit SpotDeposit(msg.sender, token, amount);
    }

    /// @notice Deposit native BNB · payable · amount = msg.value.
    function depositNative() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        emit SpotDeposit(msg.sender, NATIVE, msg.value);
    }

    // ============================== WITHDRAW ==============================

    /// @notice Backend-signed release · anyone can relay(signature authenticates account).
    /// @param  token     address(0) for BNB · else supported ERC20
    function withdraw(
        address account,
        address token,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        if (account == address(0)) revert ZeroAddress();
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (value == 0) revert ZeroAmount();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (usedNonces[account][token][nonce]) revert NonceAlreadyUsed(account, token, nonce);

        bytes32 structHash = keccak256(abi.encode(
            SPOT_RELEASE_FUNDS_TYPEHASH,
            account,
            token,
            value,
            nonce,
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != backendSigner) revert InvalidSignature(recovered, backendSigner);

        usedNonces[account][token][nonce] = true;
        if (nonce >= _nextNonce[account][token]) {
            _nextNonce[account][token] = nonce + 1;
        }

        if (token == NATIVE) {
            (bool ok, ) = payable(account).call{value: value}("");
            if (!ok) revert NativeTransferFailed();
        } else {
            IERC20(token).safeTransfer(account, value);
        }
        emit SpotWithdrawal(account, token, value, nonce);
    }

    // ============================== VIEW ==============================

    /// @notice Next unused nonce backend should sign for (account, token).
    /// @dev    Backend abigen must include `(address,address)` params matching this.
    function releaseNonces(address account, address token) external view returns (uint256) {
        return _nextNonce[account][token];
    }

    // ============================== ADMIN ==============================

    function setBackendSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address old = backendSigner;
        backendSigner = newSigner;
        emit BackendSignerRotated(old, newSigner);
    }

    /// @notice Whitelist/de-whitelist an ERC20. Native BNB cannot be de-whitelisted.
    function setTokenSupport(address token, bool supported) external onlyOwner {
        if (token == NATIVE) revert TokenNotSupported(NATIVE); // native always on
        supportedTokens[token] = supported;
        emit TokenSupported(token, supported);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Rescue non-whitelisted ERC20 accidentally sent to vault.
    /// @dev    Cannot rescue any supported token or NATIVE (invariants).
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        if (token == NATIVE || supportedTokens[token]) revert TokenNotSupported(token);
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit RescueToken(token, to, amount);
    }

    /// Contract may hold native BNB deposits; do not accept plain sends outside depositNative.
    receive() external payable {
        revert("Use depositNative()");
    }
}
