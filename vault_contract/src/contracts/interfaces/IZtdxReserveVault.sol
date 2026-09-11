// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IZtdxReserveVault
 * @notice Interface for the reserveVault contract
 * @dev Defines the interface for USDT-based fundAccount and withdrawal operations
 */
interface IZtdxReserveVault {
    // ==================== Events ====================

    /// @notice Emitted when a user deposits USDT
    /// @param user The address of the user
    /// @param amount The amount of USDT deposited (in USDT decimals)
    /// @param referralCode The referral code used (if any)
    event AccountFunded(
        address indexed user,
        uint256 amount,
        bytes32 referralCode
    );

    /// @notice Emitted when a user withdraws USDT
    /// @param user The address of the user
    /// @param amount The amount of USDT withdrawn (in USDT decimals)
    /// @param nonce The nonce used for this withdrawal
    event FundsReleased(
        address indexed user,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Emitted when a user sets a referral code
    /// @param user The address of the user
    /// @param code The referral code
    /// @param referrer The address of the referrer
    event AffiliateCodeBound(
        address indexed user,
        bytes32 indexed code,
        address indexed referrer
    );

    /// @notice Emitted when the backend signer is updated
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event AuthorizationSignerChanged(
        address indexed oldSigner,
        address indexed newSigner
    );

    // Note: Paused and Unpaused events are inherited from OpenZeppelin's Pausable

    /// @notice Emitted during emergency withdrawal
    /// @param to The recipient address
    /// @param amount The amount withdrawn
    event EmergencyAssetRescued(
        address indexed to,
        uint256 amount
    );

    /// @notice Emitted when minimum fundAccount amount is updated
    /// @param newMinDeposit The new minimum fundAccount amount
    event MinimumFundingChanged(uint256 newMinDeposit);

    /// @notice Emitted when minimum withdrawal amount is updated
    /// @param newMinWithdraw The new minimum withdrawal amount
    event MinimumReleaseChanged(uint256 newMinWithdraw);

    /// @notice Emitted when admin allocates institutional USDT to a multisig
    /// @param multisig The multisig address
    /// @param amount The amount allocated
    event PartnerLedgerCredited(address indexed multisig, uint256 amount);

    /// @notice Emitted when a multisig withdraws its institutional USDT
    /// @param multisig The multisig address
    /// @param amount The amount withdrawn
    event PartnerLedgerSettled(address indexed multisig, uint256 amount);

    // ==================== Functions ====================

    /// @notice AccountFunded USDT into the reserveVault
    /// @param amount The amount of USDT to fundAccount (in USDT decimals)
    /// @param referralCode Optional referral code to set (only on first fundAccount)
    function fundAccount(
        uint256 amount,
        bytes32 referralCode
    ) external;

    /// @notice FundsReleased USDT from the reserveVault (requires backend signature)
    /// @param amount The amount of USDT to releaseFunds (in USDT decimals)
    /// @param deadline The signature expiration timestamp
    /// @param signature The backend signature for this withdrawal
    function releaseFunds(
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Get the user's remaining principal balance from deposits
    /// @param user The address of the user
    /// @return The remaining principal balance (in USDT decimals)
    function accountLiquidity(address user) external view returns (uint256);

    /// @notice Get the user's cumulative deposited amount
    /// @param user The address of the user
    /// @return The cumulative deposited amount (in USDT decimals)
    function accountFundedTotal(address user) external view returns (uint256);

    /// @notice Batch get remaining principal accountLedgers for multiple users
    /// @param users Array of user addresses
    /// @return Array of remaining principal accountLedgers (in USDT decimals)
    function batchAccountLiquidity(
        address[] calldata users
    ) external view returns (uint256[] memory);

    /// @notice Batch get cumulative deposited accountLedgers for multiple users
    /// @param users Array of user addresses
    /// @return Array of cumulative deposited accountLedgers (in USDT decimals)
    function batchFundedTotals(
        address[] calldata users
    ) external view returns (uint256[] memory);

    /// @notice Get the current withdrawal nonce for a user
    /// @param user The address of the user
    /// @return The current nonce
    function releaseNonce(address user) external view returns (uint256);

    /// @notice Get the total USDT balance held by the contract
    /// @return The total USDT balance (in USDT decimals)
    function vaultTokenBalance() external view returns (uint256);

    /// @notice Set a referral code (user can set this directly)
    /// @param code The referral code to set
    function bindAffiliateCode(bytes32 code) external;

    /// @notice Record institutional USDT allocation for a multisig address
    /// @param multisig The target multisig address
    /// @param amount The amount to allocate
    function creditPartnerLedger(address multisig, uint256 amount) external;

    /// @notice FundsReleased institutional USDT for a multisig address
    /// @param multisig The target multisig address
    /// @param amount The amount to releaseFunds
    function settlePartnerLedger(address multisig, uint256 amount) external;

    // ==================== State Variables ====================

    // Note: settlementToken is IERC20 type, accessible via address(settlementToken)

    /// @notice User remaining principal accountLedgers from deposits
    function accountLedgers(address user) external view returns (uint256);

    /// @notice User cumulative deposited accountLedgers
    function fundedTotals(address user) external view returns (uint256);

    /// @notice Remaining institutional USDT accountLedgers for multisigs
    function partnerLedgerBalances(address multisig) external view returns (uint256);

    /// @notice Cumulative institutional USDT allocated to multisigs
    function partnerLedgerCredits(address multisig) external view returns (uint256);

    /// @notice Cumulative institutional USDT withdrawn by multisigs
    function partnerLedgerDebits(address multisig) external view returns (uint256);

    /// @notice Withdrawal nonces for replay protection
    function releaseNonces(address user) external view returns (uint256);

    /// @notice Backend signer address
    function authorizationSigner() external view returns (address);

    /// @notice Minimum fundAccount amount
    function minimumFunding() external view returns (uint256);

    /// @notice Minimum withdrawal amount
    function minimumRelease() external view returns (uint256);

    /// @notice Total deposits
    function aggregateFunding() external view returns (uint256);

    /// @notice Total withdrawals
    function aggregateReleases() external view returns (uint256);

    /// @notice EIP-712 domain separator
    function domainSeparator() external view returns (bytes32);
}
