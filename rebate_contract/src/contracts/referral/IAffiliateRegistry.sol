// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IAffiliateRegistry
 * @notice Interface for the affiliate registry contract
 * @dev Manages referral codes, referrer tierSettings, and trader-referrer relationships
 */
interface IAffiliateRegistry {
    // ==================== View Functions ====================

    /**
     * @notice Get the owner of a referral code
     * @param _code The referral code
     * @return The owner address of the referral code
     */
    function codeOwnerOf(bytes32 _code) external view returns (address);

    /**
     * @notice Get the referral code of a trader
     * @param _account The address of the trader
     * @return The referral code used by the trader
     */
    function traderCodeOf(address _account) external view returns (bytes32);

    /**
     * @notice Get the trader discount share for an affiliate
     * @param _account The address of the affiliate
     * @return The trader discount share (in basis points)
     */
    function affiliateDiscountShares(address _account) external view returns (uint256);

    /**
     * @notice Get the tier level of an affiliate
     * @param _account The address of the affiliate
     * @return The tier level of the affiliate
     */
    function affiliateTiers(address _account) external view returns (uint256);

    /**
     * @notice Get the tier values for a tier level
     * @param _tierLevel The tier level
     * @return totalRebate The total rebate rate (in basis points)
     * @return discountShare The discount share for traders (in basis points)
     */
    function tierSettings(uint256 _tierLevel) external view returns (uint256 totalRebate, uint256 discountShare);

    /**
     * @notice Get the referral info for a trader
     * @param _account The address of the trader
     * @return code The referral code used by the trader
     * @return affiliate The address of the affiliate
     */
    function resolveTraderAffiliate(address _account) external view returns (bytes32 code, address affiliate);

    // ==================== State-Changing Functions ====================

    /**
     * @notice Set the referral code for a trader
     * @param _account The address of the trader
     * @param _code The referral code to set
     */
    function attachTraderCode(address _account, bytes32 _code) external;

    /**
     * @notice Register a new referral code
     * @param _code The referral code to register
     */
    function createAffiliateCode(bytes32 _code) external;

    /**
     * @notice Set the values for a tier
     * @param _tierId The tier level
     * @param _totalRebate The total rebate for the tier (affiliate reward + trader discount) in basis points
     * @param _discountShare The share of the totalRebate for traders in basis points
     */
    function configureTier(uint256 _tierId, uint256 _totalRebate, uint256 _discountShare) external;

    /**
     * @notice Set the tier for an affiliate
     * @param _referrer The address of the affiliate
     * @param _tierId The tier level to set
     */
    function assignAffiliateTier(address _referrer, uint256 _tierId) external;

    /**
     * @notice Set the owner for a referral code (governance only)
     * @param _code The referral code
     * @param _newAccount The new owner address
     */
    function adminTransferCodeOwner(bytes32 _code, address _newAccount) external;
}

