// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/IZtdxReserveVault.sol";
import "../../libraries/ZtdxSignatureCodec.sol";
import "../../referral/IAffiliateRegistry.sol";

/**
 * @title ZtdxReserveVault
 * @notice Main reserveVault contract with USDT-only deposits
 * @dev Handles user deposits, withdrawals with backend signature, and referral code management
 */
contract ZtdxReserveVault is
    Initializable,
    IZtdxReserveVault,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using ECDSA for bytes32;

    // ==================== Constants ====================

    /// @notice EIP-712 Domain name, injected at deployment time
    string public domainName;

    /// @notice FundsReleased type hash for EIP-712
    bytes32 public constant RELEASE_TYPEHASH = keccak256(
        "ReleaseFunds(address account,uint256 value,uint256 nonce,uint256 deadline)"
    );

    // ==================== State Variables ====================

    /// @notice USDT token contract
    IERC20Metadata public settlementToken;

    /// @notice User remaining principal accountLedgers from deposits: user => amount
    mapping(address => uint256) private _balances;

    /// @notice User cumulative deposited accountLedgers: user => amount
    mapping(address => uint256) public override fundedTotals;

    /// @notice Remaining institutional USDT accountLedgers for multisigs
    mapping(address => uint256) public override partnerLedgerBalances;

    /// @notice Cumulative institutional USDT allocated to multisigs
    mapping(address => uint256) public override partnerLedgerCredits;

    /// @notice Cumulative institutional USDT withdrawn by multisigs
    mapping(address => uint256) public override partnerLedgerDebits;

    /// @notice Withdrawal nonces for replay protection: user => nonce
    mapping(address => uint256) public override releaseNonces;

    /// @notice Backend signer address for withdrawal authorization
    address public override authorizationSigner;

    /// @notice Referral storage contract
    IAffiliateRegistry public affiliateRegistry;

    /// @notice Total deposits (in USDT decimals)
    uint256 public override aggregateFunding;

    /// @notice Total withdrawals (in USDT decimals)
    uint256 public override aggregateReleases;

    /// @notice Minimum fundAccount amount (in USDT decimals)
    uint256 public override minimumFunding;

    /// @notice Minimum withdrawal amount (in USDT decimals)
    uint256 public override minimumRelease;

    /// @notice EIP-712 Domain Separator
    bytes32 public override domainSeparator;

    // ==================== Errors ====================

    /// @notice Thrown when amount is below minimum
    error AmountBelowMinimum(uint256 amount, uint256 minimum);

    /// @notice Thrown when signature is expired
    error SignatureExpired(uint256 deadline, uint256 currentTime);

    /// @notice Thrown when signature is invalid
    error InvalidSignature();

    /// @notice Thrown when balance is insufficient
    error InsufficientBalance(uint256 requested, uint256 available);

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when referral storage is not set
    error ReferralStorageNotSet();

    /// @notice Thrown when institutional balance is insufficient
    error InsufficientInstitutionalBalance(uint256 requested, uint256 available);

    /// @notice Thrown when domain name is empty
    error EmptyDomainName();

    /// @notice Thrown when domain version is empty
    error EmptyDomainVersion();

    // ==================== Initialization ====================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the reserveVault
     * @param _usdt USDT token address
     * @param _backendSigner Backend signer address for withdrawal authorization
     * @param _referralStorage Referral storage contract address (can be zero)
     * @param _domainName EIP-712 domain name, should come from backend env
     * @param _domainVersion EIP-712 domain version, should come from backend env
     * @param _owner Owner address with upgrade authority
     */
    function initialize(
        address _usdt,
        address _backendSigner,
        address _referralStorage,
        string memory _domainName,
        string memory _domainVersion,
        address _owner
    ) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        if (_usdt == address(0)) revert ZeroAddress();
        if (_backendSigner == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (bytes(_domainName).length == 0) revert EmptyDomainName();
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        settlementToken = IERC20Metadata(_usdt);
        authorizationSigner = _backendSigner;
        domainName = _domainName;
        domainVersion = _domainVersion;

        if (_referralStorage != address(0)) {
            affiliateRegistry = IAffiliateRegistry(_referralStorage);
        }

        // Set default minimums (1 token unit in the token's decimals)
        uint8 decimals = settlementToken.decimals();
        minimumFunding = 10 ** decimals;
        minimumRelease = 10 ** decimals;

        // Compute EIP-712 domain separator
        domainSeparator = ZtdxSignatureCodec.buildDomainSeparator(
            domainName,
            domainVersion,
            block.chainid,
            address(this)
        );
    }

    /**
     * @notice Set EIP-712 domain version during an upgrade migration
     * @param _domainVersion EIP-712 domain version, should come from backend env
     */
    function reinitializeEip712DomainVersion(
        string memory _domainVersion
    ) external reinitializer(2) onlyOwner {
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        domainVersion = _domainVersion;
        domainSeparator = ZtdxSignatureCodec.buildDomainSeparator(
            domainName,
            domainVersion,
            block.chainid,
            address(this)
        );
    }

    // ==================== AccountFunded Functions ====================

    /**
     * @notice AccountFunded USDT into the reserveVault
     * @dev User must approve this contract to spend USDT first
     * @dev Can set referral code on first fundAccount
     * @param amount Amount of USDT to fundAccount (in USDT decimals)
     * @param referralCode Optional referral code (only set on first fundAccount)
     */
    function fundAccount(
        uint256 amount,
        bytes32 referralCode
    ) external override whenNotPaused nonReentrant {
        if (amount < minimumFunding) {
            revert AmountBelowMinimum(amount, minimumFunding);
        }

        // Transfer USDT from user to contract
        uint256 balanceBefore = settlementToken.balanceOf(address(this));
        settlementToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualAmount = settlementToken.balanceOf(address(this)) - balanceBefore;

        // Update principal and cumulative fundAccount accounting
        _balances[msg.sender] += actualAmount;
        fundedTotals[msg.sender] += actualAmount;
        aggregateFunding += actualAmount;

        // Set referral code if provided and not already set
        if (referralCode != bytes32(0) && address(affiliateRegistry) != address(0)) {
            _setReferralCode(msg.sender, referralCode);
        }

        emit AccountFunded(msg.sender, actualAmount, referralCode);
    }

    // ==================== Withdrawal Functions ====================

    /**
     * @notice FundsReleased USDT from the reserveVault (requires backend signature)
     * @dev Uses EIP-712 signature for authorization
     * @dev Implements nonce-based replay protection
     * @param amount Amount of USDT to releaseFunds (in USDT decimals)
     * @param deadline Signature expiration timestamp
     * @param signature Backend signature for this withdrawal
     */
    function releaseFunds(
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external override whenNotPaused nonReentrant {
        // Validate deadline
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        // Validate amount
        if (amount < minimumRelease) {
            revert AmountBelowMinimum(amount, minimumRelease);
        }

        // Get and increment nonce
        uint256 nonce = releaseNonces[msg.sender];
        releaseNonces[msg.sender] = nonce + 1;

        // Verify signature
        if (
            !ZtdxSignatureCodec.validateReleaseAuthorization(
                domainSeparator,
                msg.sender,
                amount,
                nonce,
                deadline,
                signature,
                authorizationSigner
            )
        ) {
            revert InvalidSignature();
        }

        // Update balance (Checks-Effects-Interactions pattern)
        uint256 userBalance = _balances[msg.sender];
        if (userBalance >= amount) {
            _balances[msg.sender] = userBalance - amount;
        } else {
            _balances[msg.sender] = 0;
        }
        aggregateReleases += amount;

        // Transfer USDT to user
        settlementToken.safeTransfer(msg.sender, amount);

        emit FundsReleased(msg.sender, amount, nonce);
    }

    // ==================== Query Functions ====================

    /**
     * @notice Get user remaining principal balance from deposits
     * @param user User address
     * @return User's remaining principal balance (in USDT decimals)
     */
    function accountLiquidity(
        address user
    ) external view override returns (uint256) {
        return _balances[user];
    }

    /**
     * @notice Get user cumulative deposited balance
     * @param user User address
     * @return User's cumulative deposited balance (in USDT decimals)
     */
    function accountFundedTotal(
        address user
    ) external view override returns (uint256) {
        return fundedTotals[user];
    }

    /**
     * @notice Batch get remaining principal accountLedgers for multiple users
     * @param users Array of user addresses
     * @return Array of remaining principal accountLedgers (in USDT decimals)
     */
    function batchAccountLiquidity(
        address[] calldata users
    ) external view override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            result[i] = _balances[users[i]];
        }
        return result;
    }

    /**
     * @notice Batch get cumulative deposited accountLedgers for multiple users
     * @param users Array of user addresses
     * @return Array of cumulative deposited accountLedgers (in USDT decimals)
     */
    function batchFundedTotals(
        address[] calldata users
    ) external view override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            result[i] = fundedTotals[users[i]];
        }
        return result;
    }

    /**
     * @notice Get user remaining principal balance from deposits
     * @param user User address
     * @return User's remaining principal balance (in USDT decimals)
     */
    function accountLedgers(address user) external view override returns (uint256) {
        return _balances[user];
    }

    /**
     * @notice Get current withdrawal nonce for a user
     * @param user User address
     * @return Current nonce
     */
    function releaseNonce(
        address user
    ) external view override returns (uint256) {
        return releaseNonces[user];
    }

    /**
     * @notice Get total USDT balance held by contract
     * @return Total USDT balance (in USDT decimals)
     */
    function vaultTokenBalance() external view override returns (uint256) {
        return settlementToken.balanceOf(address(this));
    }

    /**
     * @notice Get USDT token decimals
     * @return The number of decimals for USDT token
     */
    function settlementTokenDecimals() external view returns (uint8) {
        return settlementToken.decimals();
    }

    // ==================== Referral Functions ====================

    /**
     * @notice Set referral code (user can call this directly)
     * @param code Referral code to set
     */
    function bindAffiliateCode(bytes32 code) external override {
        _setReferralCode(msg.sender, code);
    }

    /**
     * @notice Record institutional USDT allocation for a multisig address
     * @dev Only updates internal accounting. It does not transfer tokens in.
     * @param multisig The multisig address
     * @param amount The amount to allocate
     */
    function creditPartnerLedger(
        address multisig,
        uint256 amount
    ) external override onlyOwner {
        if (multisig == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        partnerLedgerBalances[multisig] += amount;
        partnerLedgerCredits[multisig] += amount;

        emit PartnerLedgerCredited(multisig, amount);
    }

    /**
     * @notice FundsReleased institutional USDT for a multisig address
     * @param multisig The target multisig address
     * @param amount The amount to releaseFunds
     */
    function settlePartnerLedger(
        address multisig,
        uint256 amount
    ) external override onlyOwner whenNotPaused nonReentrant {
        if (multisig == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = partnerLedgerBalances[multisig];
        if (balance < amount) {
            revert InsufficientInstitutionalBalance(amount, balance);
        }
        partnerLedgerBalances[multisig] = balance - amount;
        partnerLedgerDebits[multisig] += amount;

        settlementToken.safeTransfer(multisig, amount);

        emit PartnerLedgerSettled(multisig, amount);
    }

    /**
     * @notice Internal function to set referral code
     * @dev Only sets if user doesn't already have a code and code is valid
     * @param user User address
     * @param code Referral code
     */
    function _setReferralCode(address user, bytes32 code) internal {
        if (address(affiliateRegistry) == address(0)) {
            return; // Silently return if referral storage not set
        }
        if (code == bytes32(0)) {
            return; // Silently return if code is zero
        }

        // Check if user already has a referral code
        bytes32 existingCode = affiliateRegistry.traderCodeOf(user);
        if (existingCode != bytes32(0)) {
            return; // User already has a code
        }

        // Check if referral code exists and get owner
        address codeOwner = affiliateRegistry.codeOwnerOf(code);
        if (codeOwner == address(0)) {
            return; // Code doesn't exist
        }
        if (codeOwner == user) {
            return; // User cannot use their own code
        }

        // Set the referral code
        affiliateRegistry.attachTraderCode(user, code);

        emit AffiliateCodeBound(user, code, codeOwner);
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Update backend signer address
     * @param newSigner New signer address
     */
    function setAuthorizationSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address oldSigner = authorizationSigner;
        authorizationSigner = newSigner;
        emit AuthorizationSignerChanged(oldSigner, newSigner);
    }

    /**
     * @notice Set referral storage contract
     * @param _referralStorage Referral storage contract address
     */
    function setAffiliateRegistry(address _referralStorage) external onlyOwner {
        affiliateRegistry = IAffiliateRegistry(_referralStorage);
    }

    /**
     * @notice Pause the contract (emergency only)
     */
    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Emergency releaseFunds USDT (only when paused)
     * @param to Recipient address
     * @param amount Amount to releaseFunds
     */
    function rescueSettlementAsset(
        address to,
        uint256 amount
    ) external onlyOwner {
        if (!paused()) {
            revert("Not paused");
        }
        if (to == address(0)) revert ZeroAddress();
        settlementToken.safeTransfer(to, amount);
        emit EmergencyAssetRescued(to, amount);
    }

    /**
     * @notice Set minimum fundAccount amount
     * @param _minDeposit New minimum fundAccount amount (in USDT decimals)
     */
    function setMinimumFunding(uint256 _minDeposit) external onlyOwner {
        minimumFunding = _minDeposit;
        emit MinimumFundingChanged(_minDeposit);
    }

    /**
     * @notice Set minimum withdrawal amount
     * @param _minWithdraw New minimum withdrawal amount (in USDT decimals)
     */
    function setMinimumRelease(uint256 _minWithdraw) external onlyOwner {
        minimumRelease = _minWithdraw;
        emit MinimumReleaseChanged(_minWithdraw);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    /// @notice EIP-712 Domain version, appended for upgrade-safe storage layout
    string public domainVersion;

    uint256[49] private __gap;
}
