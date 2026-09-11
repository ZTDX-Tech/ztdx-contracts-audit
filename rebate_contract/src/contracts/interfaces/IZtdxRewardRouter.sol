// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IZtdxRewardRouter
 * @notice Interface for Referral Rebate contract
 * @dev Defines the interface for USDT-based rebate claiming operations
 */
interface IZtdxRewardRouter {
    // ==================== Events ====================

    /// @notice Emitted when a user claims rebate
    /// @param user The address of the user
    /// @param amount The amount of USDT rebate claimed (6 decimals)
    /// @param nonce The nonce used for this redeemPlan
    event RewardRedeemed(
        address indexed user,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Emitted when rebates are batch synced
    /// @param batchId The batch ID
    /// @param totalAmount The total amount of rebates distributed
    /// @param userCount The number of users who received rebates
    event RewardBatchSettled(
        uint256 indexed batchId,
        uint256 totalAmount,
        uint256 userCount
    );

    /// @notice Emitted when the backend signer is updated
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event AuthorizationSignerChanged(
        address indexed oldSigner,
        address indexed newSigner
    );

    /// @notice Emitted when the affiliate registry is replaced
    /// @param oldRegistry The previous registry address
    /// @param newRegistry The new registry address
    event AffiliateRegistryChanged(address indexed oldRegistry, address indexed newRegistry);

    // ==================== Functions ====================

    /// @notice Claim rebate (requires backend signature)
    /// @param amount The amount of USDT rebate to redeemPlan (6 decimals)
    /// @param deadline The signature expiration timestamp
    /// @param signature The backend signature for this redeemPlan
    function redeemReward(
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Batch sync rebates (admin only)
    /// @param users Array of user addresses
    /// @param amounts Array of rebate amounts (6 decimals)
    /// @param batchId The batch ID for tracking
    function batchSettleRewards(
        address[] calldata users,
        uint256[] calldata amounts,
        uint256 batchId
    ) external;

    /// @notice Get user rebate information
    /// @param user The address of the user
    /// @return claimed The total amount of rebates claimed
    /// @return nonce The current rebate nonce
    /// @return referralCode The user's referral code
    /// @return referrer The address of the referrer
    /// @return tierLevel The tier level of the referrer
    function rewardAccountInfo(
        address user
    )
        external
        view
        returns (
            uint256 claimed,
            uint256 nonce,
            bytes32 referralCode,
            address referrer,
            uint256 tierLevel
        );

    // ==================== State Variables ====================

    /// @notice Total claimed rebates per user
    function redeemedRewards(address user) external view returns (uint256);

    /// @notice Rebate nonces for replay protection
    function rewardNonces(address user) external view returns (uint256);

    /// @notice Backend signer address
    function authorizationSigner() external view returns (address);

    // Note: reserveVault and affiliateRegistry are interface types, not addresses
}


