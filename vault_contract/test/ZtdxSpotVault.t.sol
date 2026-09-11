// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/contracts/core/vault/ZtdxSpotVault.sol";

contract MockToken is ERC20 {
    uint8 private immutable _tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract ZtdxSpotVaultTest is Test {
    bytes32 private constant SPOT_RELEASE_TYPEHASH = keccak256(
        "SpotReleaseFunds(address account,address token,uint256 value,uint256 nonce,uint256 deadline)"
    );

    ZtdxSpotVault private vault;
    MockToken private token;
    MockToken private secondToken;

    uint256 private authorizationSignerPrivateKey = 0xA11CE123;
    address private authorizationSigner;
    address private owner = address(0xA11CE);
    address private user = address(0xB0B);

    function setUp() external {
        authorizationSigner = vm.addr(authorizationSignerPrivateKey);
        token = new MockToken("Mock USDT", "mUSDT", 6);
        secondToken = new MockToken("Mock WBTC", "mWBTC", 8);
        ZtdxSpotVault implementation = new ZtdxSpotVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxSpotVault.initialize,
                (authorizationSigner, "ZTDX Spot Vault", "1", owner)
            )
        );
        vault = ZtdxSpotVault(address(proxy));
    }

    function testOwnerCanRegisterToken() external {
        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        assertTrue(vault.registeredTokens(address(token)));
    }

    function testDepositRegisteredTokenUpdatesLedgerAndTransfersFunds() external {
        uint256 amount = 100e6;
        token.mint(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        vm.stopPrank();

        assertEq(vault.accountTokenBalance(user, address(token)), amount);
        assertEq(vault.accountTokenDepositTotal(user, address(token)), amount);
        assertEq(vault.tokenTotalDeposits(address(token)), amount);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(token.balanceOf(user), 0);
    }

    function testDepositRegisteredNativeTokenUpdatesLedgerAndTransfersFunds() external {
        uint256 amount = 1 ether;
        vm.deal(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(0), true);

        vm.prank(user);
        vault.depositNative{value: amount}();

        assertEq(vault.accountTokenBalance(user, address(0)), amount);
        assertEq(vault.accountTokenDepositTotal(user, address(0)), amount);
        assertEq(vault.tokenTotalDeposits(address(0)), amount);
        assertEq(vault.vaultTokenBalance(address(0)), amount);
        assertEq(address(vault).balance, amount);
    }

    function testCannotDepositNativeWhenNativeTokenIsUnregistered() external {
        uint256 amount = 1 ether;
        vm.deal(user, amount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ZtdxSpotVault.TokenNotRegistered.selector, address(0)));
        vault.depositNative{value: amount}();
    }

    function testPlainNativeTransferDoesNotDeposit() external {
        uint256 amount = 1 ether;
        vm.deal(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(0), true);

        vm.prank(user);
        (bool sent, ) = address(vault).call{value: amount}("");

        assertFalse(sent);
        assertEq(vault.accountTokenBalance(user, address(0)), 0);
        assertEq(address(vault).balance, 0);
    }

    function testCannotDepositUnregisteredToken() external {
        uint256 amount = 100e6;
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vm.expectRevert(abi.encodeWithSelector(ZtdxSpotVault.TokenNotRegistered.selector, address(token)));
        vault.deposit(address(token), amount);
        vm.stopPrank();
    }

    function testWithdrawRegisteredTokenUpdatesLedgerAndTransfersFunds() external {
        uint256 depositAmount = 100e6;
        uint256 withdrawAmount = 40e6;
        token.mint(user, depositAmount);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, withdrawAmount, deadline);

        vm.startPrank(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(address(token), depositAmount);
        vault.withdraw(address(token), withdrawAmount, deadline, signature);
        vm.stopPrank();

        assertEq(vault.accountTokenBalance(user, address(token)), depositAmount - withdrawAmount);
        assertEq(vault.tokenTotalWithdrawals(address(token)), withdrawAmount);
        assertEq(token.balanceOf(user), withdrawAmount);
        assertEq(token.balanceOf(address(vault)), depositAmount - withdrawAmount);
    }

    function testCanWithdrawExistingBalanceAfterTokenIsUnregistered() external {
        uint256 amount = 100e6;
        token.mint(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        vm.stopPrank();

        vm.prank(owner);
        vault.setTokenRegistered(address(token), false);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, amount, deadline);

        vm.prank(user);
        vault.withdraw(address(token), amount, deadline, signature);

        assertEq(vault.accountTokenBalance(user, address(token)), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function testCannotWithdrawMoreThanVaultTokenBalance() external {
        uint256 amount = 100e6;
        token.mint(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, amount + 1, deadline);
        vm.expectRevert(
            abi.encodeWithSelector(
                ZtdxSpotVault.InsufficientVaultBalance.selector,
                address(token),
                amount + 1,
                amount
            )
        );
        vault.withdraw(address(token), amount + 1, deadline, signature);
        vm.stopPrank();
    }

    function testCanWithdrawBackendAuthorizedAmountAboveDepositLedger() external {
        address liquidityProvider = address(0xC0FFEE);
        uint256 vaultLiquidity = 100e6;
        uint256 withdrawalAmount = 40e6;
        token.mint(liquidityProvider, vaultLiquidity);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        vm.startPrank(liquidityProvider);
        token.approve(address(vault), vaultLiquidity);
        vault.deposit(address(token), vaultLiquidity);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, withdrawalAmount, deadline);

        vm.prank(user);
        vault.withdraw(address(token), withdrawalAmount, deadline, signature);

        assertEq(vault.accountTokenBalance(user, address(token)), 0);
        assertEq(vault.tokenTotalWithdrawals(address(token)), withdrawalAmount);
        assertEq(token.balanceOf(user), withdrawalAmount);
        assertEq(token.balanceOf(address(vault)), vaultLiquidity - withdrawalAmount);
    }

    function testWithdrawNativeTokenWithBackendAuthorization() external {
        uint256 depositAmount = 2 ether;
        uint256 withdrawalAmount = 0.75 ether;
        vm.deal(user, depositAmount);

        vm.prank(owner);
        vault.setTokenRegistered(address(0), true);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawalForToken(address(0), user, withdrawalAmount, deadline);

        vm.startPrank(user);
        vault.depositNative{value: depositAmount}();
        uint256 userBalanceAfterDeposit = user.balance;
        vault.withdraw(address(0), withdrawalAmount, deadline, signature);
        vm.stopPrank();

        assertEq(vault.accountTokenBalance(user, address(0)), depositAmount - withdrawalAmount);
        assertEq(vault.tokenTotalWithdrawals(address(0)), withdrawalAmount);
        assertEq(user.balance, userBalanceAfterDeposit + withdrawalAmount);
        assertEq(address(vault).balance, depositAmount - withdrawalAmount);
    }

    function testCannotRescueRegisteredToken() external {
        uint256 amount = 100e6;
        token.mint(address(vault), amount);

        vm.startPrank(owner);
        vault.setTokenRegistered(address(token), true);
        vault.pause();
        vm.expectRevert(abi.encodeWithSelector(ZtdxSpotVault.RegisteredTokenRescueDisabled.selector, address(token)));
        vault.rescueToken(address(token), owner, amount);
        vm.stopPrank();
    }

    function testCanReinitializeEip712DomainVersion() external {
        bytes32 oldSeparator = vault.domainSeparator();

        vm.prank(owner);
        vault.reinitializeEip712DomainVersion("ZTDX Spot Vault", "2");

        assertEq(vault.domainName(), "ZTDX Spot Vault");
        assertEq(vault.domainVersion(), "2");
        assertTrue(vault.domainSeparator() != oldSeparator);
    }

    function testInitializeRevertsForZeroBackendSigner() external {
        ZtdxSpotVault implementation = new ZtdxSpotVault();
        vm.expectRevert(ZtdxSpotVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxSpotVault.initialize,
                (address(0), "ZTDX Spot Vault", "1", owner)
            )
        );
    }

    function testCannotWithdrawWithoutBackendAuthorization() external {
        uint256 amount = 100e6;
        token.mint(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        bytes memory wrongSignature = _signWithdrawalWithKey(0xB0B123, user, amount, block.timestamp + 1 hours);
        vm.expectRevert(ZtdxSpotVault.InvalidSignature.selector);
        vault.withdraw(address(token), amount, block.timestamp + 1 hours, wrongSignature);
        vm.stopPrank();
    }

    function testCannotReplayWithdrawalSignature() external {
        uint256 amount = 100e6;
        token.mint(user, amount * 2);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, amount, deadline);

        vm.startPrank(user);
        token.approve(address(vault), amount * 2);
        vault.deposit(address(token), amount * 2);
        vault.withdraw(address(token), amount, deadline, signature);
        vm.expectRevert(ZtdxSpotVault.InvalidSignature.selector);
        vault.withdraw(address(token), amount, deadline, signature);
        vm.stopPrank();
    }

    function testCannotWithdrawWithExpiredSignature() external {
        uint256 amount = 100e6;
        token.mint(user, amount);

        vm.prank(owner);
        vault.setTokenRegistered(address(token), true);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, amount, deadline);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(ZtdxSpotVault.SignatureExpired.selector, deadline, block.timestamp));
        vault.withdraw(address(token), amount, deadline, signature);
        vm.stopPrank();
    }

    function testCannotUseSignatureAcrossTokens() external {
        uint256 amount = 100e6;
        secondToken.mint(user, amount);

        vm.startPrank(owner);
        vault.setTokenRegistered(address(token), true);
        vault.setTokenRegistered(address(secondToken), true);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signatureForFirstToken = _signWithdrawal(user, amount, deadline);

        vm.startPrank(user);
        secondToken.approve(address(vault), amount);
        vault.deposit(address(secondToken), amount);
        vm.expectRevert(ZtdxSpotVault.InvalidSignature.selector);
        vault.withdraw(address(secondToken), amount, deadline, signatureForFirstToken);
        vm.stopPrank();
    }

    function testCannotWithdrawNeverRegisteredTokenEvenWithValidSignature() external {
        uint256 amount = 100e6;
        token.mint(address(vault), amount);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawal(user, amount, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ZtdxSpotVault.TokenNotRegistered.selector, address(token)));
        vault.withdraw(address(token), amount, deadline, signature);
    }

    function testCannotWithdrawNeverRegisteredNativeTokenEvenWithValidSignature() external {
        uint256 amount = 1 ether;
        vm.deal(address(vault), amount);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signWithdrawalForToken(address(0), user, amount, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ZtdxSpotVault.TokenNotRegistered.selector, address(0)));
        vault.withdraw(address(0), amount, deadline, signature);
    }

    function _signWithdrawal(
        address account,
        uint256 amount,
        uint256 deadline
    ) private view returns (bytes memory) {
        return _signWithdrawalWithKey(authorizationSignerPrivateKey, account, amount, deadline);
    }

    function _signWithdrawalForToken(
        address withdrawalToken,
        address account,
        uint256 amount,
        uint256 deadline
    ) private view returns (bytes memory) {
        return _signWithdrawalForTokenWithKey(authorizationSignerPrivateKey, withdrawalToken, account, amount, deadline);
    }

    function _signWithdrawalWithKey(
        uint256 privateKey,
        address account,
        uint256 amount,
        uint256 deadline
    ) private view returns (bytes memory) {
        return _signWithdrawalForTokenWithKey(privateKey, address(token), account, amount, deadline);
    }

    function _signWithdrawalForTokenWithKey(
        uint256 privateKey,
        address withdrawalToken,
        address account,
        uint256 amount,
        uint256 deadline
    ) private view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                SPOT_RELEASE_TYPEHASH,
                account,
                withdrawalToken,
                amount,
                vault.releaseNonces(account),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
