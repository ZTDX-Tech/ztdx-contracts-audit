// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/IZtdxSpotVault.sol";
import "../../libraries/ZtdxSignatureCodec.sol";

/**
 * @title ZtdxSpotVault
 * @notice Multi-token spot vault for registered ERC20 deposits and withdrawals.
 */
contract ZtdxSpotVault is
    Initializable,
    IZtdxSpotVault,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    string public domainName;
    string public domainVersion;

    mapping(address => bool) public registeredTokens;
    mapping(address => bool) public everRegisteredTokens;
    mapping(address => mapping(address => uint256)) private _accountTokenBalances;
    mapping(address => mapping(address => uint256)) private _accountTokenDepositTotals;

    /// @notice Gross deposit volume, not a solvency or current-balance proof.
    mapping(address => uint256) public tokenTotalDeposits;
    /// @notice Gross signed withdrawal volume, not a solvency or current-balance proof.
    mapping(address => uint256) public tokenTotalWithdrawals;
    mapping(address => uint256) public override releaseNonces;

    address public override authorizationSigner;
    bytes32 public override domainSeparator;

    error TokenNotRegistered(address token);
    error InsufficientVaultBalance(address token, uint256 requested, uint256 available);
    error SignatureExpired(uint256 deadline, uint256 currentTime);
    error InvalidSignature();
    error ZeroAddress();
    error ZeroAmount();
    error EmptyDomainName();
    error EmptyDomainVersion();
    error RegisteredTokenRescueDisabled(address token);
    error NativeTransferFailed();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _backendSigner,
        string memory _domainName,
        string memory _domainVersion,
        address _owner
    ) external initializer {
        if (_backendSigner == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (bytes(_domainName).length == 0) revert EmptyDomainName();
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        authorizationSigner = _backendSigner;
        domainName = _domainName;
        domainVersion = _domainVersion;
        domainSeparator = ZtdxSignatureCodec.buildDomainSeparator(
            domainName,
            domainVersion,
            block.chainid,
            address(this)
        );
    }

    function setTokenRegistered(address token, bool registered) external override onlyOwner {
        registeredTokens[token] = registered;
        if (registered) {
            everRegisteredTokens[token] = true;
        }
        emit TokenRegistrationChanged(token, registered);
    }

    function deposit(address token, uint256 amount) external override whenNotPaused nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        _requireRegisteredToken(token);
        if (amount == 0) revert ZeroAmount();

        IERC20 asset = IERC20(token);
        uint256 balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualAmount = asset.balanceOf(address(this)) - balanceBefore;
        if (actualAmount == 0) revert ZeroAmount();

        _accountTokenBalances[msg.sender][token] += actualAmount;
        _accountTokenDepositTotals[msg.sender][token] += actualAmount;
        tokenTotalDeposits[token] += actualAmount;

        emit SpotDeposit(msg.sender, token, actualAmount);
    }

    function depositNative() external payable override whenNotPaused nonReentrant {
        _requireRegisteredToken(address(0));
        if (msg.value == 0) revert ZeroAmount();

        _accountTokenBalances[msg.sender][address(0)] += msg.value;
        _accountTokenDepositTotals[msg.sender][address(0)] += msg.value;
        tokenTotalDeposits[address(0)] += msg.value;

        emit SpotDeposit(msg.sender, address(0), msg.value);
    }

    function withdraw(
        address token,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external override whenNotPaused nonReentrant {
        if (!everRegisteredTokens[token]) revert TokenNotRegistered(token);
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        uint256 nonce = releaseNonces[msg.sender];
        releaseNonces[msg.sender] = nonce + 1;

        if (
            !ZtdxSignatureCodec.validateSpotReleaseAuthorization(
                domainSeparator,
                msg.sender,
                token,
                amount,
                nonce,
                deadline,
                signature,
                authorizationSigner
            )
        ) {
            revert InvalidSignature();
        }

        uint256 vaultBalance = _vaultTokenBalance(token);
        if (amount > vaultBalance) {
            revert InsufficientVaultBalance(token, amount, vaultBalance);
        }

        uint256 accountBalance = _accountTokenBalances[msg.sender][token];
        if (accountBalance >= amount) {
            _accountTokenBalances[msg.sender][token] = accountBalance - amount;
        } else {
            _accountTokenBalances[msg.sender][token] = 0;
        }
        tokenTotalWithdrawals[token] += amount;

        if (token == address(0)) {
            (bool sent, ) = payable(msg.sender).call{value: amount}("");
            if (!sent) revert NativeTransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit SpotWithdrawal(msg.sender, token, amount, nonce);
    }

    function accountTokenBalance(
        address account,
        address token
    ) external view override returns (uint256) {
        return _accountTokenBalances[account][token];
    }

    function accountTokenDepositTotal(
        address account,
        address token
    ) external view override returns (uint256) {
        return _accountTokenDepositTotals[account][token];
    }

    function vaultTokenBalance(address token) external view override returns (uint256) {
        return _vaultTokenBalance(token);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setAuthorizationSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address oldSigner = authorizationSigner;
        authorizationSigner = newSigner;
        emit AuthorizationSignerChanged(oldSigner, newSigner);
    }

    function reinitializeEip712DomainVersion(
        string memory newName,
        string memory newVersion
    ) external override reinitializer(2) onlyOwner {
        if (bytes(newName).length == 0) revert EmptyDomainName();
        if (bytes(newVersion).length == 0) revert EmptyDomainVersion();

        domainName = newName;
        domainVersion = newVersion;
        domainSeparator = ZtdxSignatureCodec.buildDomainSeparator(
            newName,
            newVersion,
            block.chainid,
            address(this)
        );
    }

    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        if (!paused()) revert("Not paused");
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (registeredTokens[token]) revert RegisteredTokenRescueDisabled(token);

        IERC20(token).safeTransfer(to, amount);
        emit EmergencyTokenRescued(token, to, amount);
    }

    function rescueNative(address to, uint256 amount) external onlyOwner {
        if (!paused()) revert("Not paused");
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (registeredTokens[address(0)]) revert RegisteredTokenRescueDisabled(address(0));

        (bool sent, ) = payable(to).call{value: amount}("");
        if (!sent) revert NativeTransferFailed();
        emit EmergencyNativeRescued(to, amount);
    }

    function _requireRegisteredToken(address token) internal view {
        if (!registeredTokens[token]) revert TokenNotRegistered(token);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    function _vaultTokenBalance(address token) internal view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }

    uint256[40] private __gap;
}
