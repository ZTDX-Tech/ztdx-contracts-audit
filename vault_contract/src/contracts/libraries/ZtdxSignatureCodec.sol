// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title ZtdxSignatureCodec
 * @notice Library for EIP-712 signature verification
 * @dev Provides utilities for verifying typed data signatures according to EIP-712
 * @dev Implements security best practices: signature length validation, zero address checks
 */
library ZtdxSignatureCodec {
    using ECDSA for bytes32;

    /// @notice ECDSA signature length (r: 32 bytes + s: 32 bytes + v: 1 byte)
    uint256 private constant SIGNATURE_LENGTH = 65;

    /// @notice Error thrown when signature length is invalid
    error InvalidSignatureLength(uint256 length);

    /// @notice Error thrown when recovered signer is zero address
    error InvalidSigner();

    /**
     * @notice Verify a withdrawal signature
     * @dev Validates signature length, recovers signer, and checks against expected signer
     * @param domainSeparator The EIP-712 domain separator
     * @param user The user address
     * @param amount The withdrawal amount
     * @param nonce The withdrawal nonce
     * @param deadline The signature deadline
     * @param signature The signature to verify (65 bytes: r + s + v)
     * @param expectedSigner The expected signer address
     * @return isValid Whether the signature is valid
     */
    function validateReleaseAuthorization(
        bytes32 domainSeparator,
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        // Validate signature length (must be 65 bytes: 32 bytes r + 32 bytes s + 1 byte v)
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        // Compute EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ReleaseFunds(address account,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                user,
                amount,
                nonce,
                deadline
            )
        );

        // Compute EIP-712 message hash
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // Recover signer from signature
        address signer = hash.recover(signature);

        // Check that signer is not zero address (ECDSA.recover can return address(0) for invalid signatures)
        if (signer == address(0)) {
            revert InvalidSigner();
        }

        // Verify signer matches expected signer
        return signer == expectedSigner;
    }

    function validateSpotReleaseAuthorization(
        bytes32 domainSeparator,
        address user,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "SpotReleaseFunds(address account,address token,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                user,
                token,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        address signer = hash.recover(signature);
        if (signer == address(0)) {
            revert InvalidSigner();
        }

        return signer == expectedSigner;
    }

    /**
     * @notice Verify a rebate redeemPlan signature
     * @dev Validates signature length, recovers signer, and checks against expected signer
     * @param domainSeparator The EIP-712 domain separator
     * @param user The user address
     * @param amount The rebate amount
     * @param nonce The rebate nonce
     * @param deadline The signature deadline
     * @param signature The signature to verify (65 bytes: r + s + v)
     * @param expectedSigner The expected signer address
     * @return isValid Whether the signature is valid
     */
    function validateRewardAuthorization(
        bytes32 domainSeparator,
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        // Validate signature length (must be 65 bytes: 32 bytes r + 32 bytes s + 1 byte v)
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        // Compute EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "RedeemReward(address account,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                user,
                amount,
                nonce,
                deadline
            )
        );

        // Compute EIP-712 message hash
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // Recover signer from signature
        address signer = hash.recover(signature);

        // Check that signer is not zero address (ECDSA.recover can return address(0) for invalid signatures)
        if (signer == address(0)) {
            revert InvalidSigner();
        }

        // Verify signer matches expected signer
        return signer == expectedSigner;
    }

    /**
     * @notice Compute EIP-712 domain separator
     * @param name The contract name
     * @param version The contract version
     * @param chainId The chain ID
     * @param verifyingContract The contract address
     * @return The domain separator
     */
    function buildDomainSeparator(
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    chainId,
                    verifyingContract
                )
            );
    }
}

