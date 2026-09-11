// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface IZtdxSpotVault {
    event TokenRegistrationChanged(address indexed token, bool registered);
    event SpotDeposit(address indexed account, address indexed token, uint256 amount);
    event SpotWithdrawal(address indexed account, address indexed token, uint256 amount, uint256 nonce);
    event EmergencyTokenRescued(address indexed token, address indexed to, uint256 amount);
    event EmergencyNativeRescued(address indexed to, uint256 amount);
    event AuthorizationSignerChanged(address indexed oldSigner, address indexed newSigner);

    function setTokenRegistered(address token, bool registered) external;
    function setAuthorizationSigner(address newSigner) external;
    function reinitializeEip712DomainVersion(string memory newName, string memory newVersion) external;
    function deposit(address token, uint256 amount) external;
    function depositNative() external payable;
    function withdraw(address token, uint256 amount, uint256 deadline, bytes calldata signature) external;
    function rescueNative(address to, uint256 amount) external;
    function accountTokenBalance(address account, address token) external view returns (uint256);
    function accountTokenDepositTotal(address account, address token) external view returns (uint256);
    function vaultTokenBalance(address token) external view returns (uint256);
    function registeredTokens(address token) external view returns (bool);
    function everRegisteredTokens(address token) external view returns (bool);
    /// @notice Gross signed withdrawal volume, not a solvency or current-balance proof.
    function tokenTotalDeposits(address token) external view returns (uint256);
    /// @notice Gross signed withdrawal volume, not a solvency or current-balance proof.
    function tokenTotalWithdrawals(address token) external view returns (uint256);
    function releaseNonces(address account) external view returns (uint256);
    function authorizationSigner() external view returns (address);
    function domainSeparator() external view returns (bytes32);
}
