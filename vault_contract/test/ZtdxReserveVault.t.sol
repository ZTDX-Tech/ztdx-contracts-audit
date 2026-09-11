// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/contracts/core/vault/ZtdxReserveVault.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Minimal registry exposing only the calls ZtdxReserveVault makes
contract MockAffiliateRegistry {
    mapping(bytes32 => address) public codeOwnerOf;
    mapping(address => bytes32) public traderCodeOf;

    function setCodeOwner(bytes32 code, address codeOwner) external { codeOwnerOf[code] = codeOwner; }
    function attachTraderCode(address account, bytes32 code) external { traderCodeOf[account] = code; }
}

contract ZtdxReserveVaultTest is Test {
    event AccountFunded(address indexed user, uint256 amount, bytes32 referralCode);
    event AffiliateRegistryChanged(address indexed oldRegistry, address indexed newRegistry);
    event ExcessReleaseLimitsChanged(uint256 txLimit, uint256 windowLimit);

    ZtdxReserveVault vault;
    MockUSDT usdt;
    MockAffiliateRegistry registry;
    address owner = address(0xA11CE);
    uint256 signerPk = 0xB0BB051;
    address signer;
    address alice = address(0xA11);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    bytes32 constant CODE_CAROL = keccak256("CAROL");
    bytes32 constant CODE_BOB = keccak256("BOB");

    function setUp() public {
        signer = vm.addr(signerPk);
        usdt = new MockUSDT();
        registry = new MockAffiliateRegistry();
        registry.setCodeOwner(CODE_CAROL, carol);
        registry.setCodeOwner(CODE_BOB, bob);

        ZtdxReserveVault impl = new ZtdxReserveVault();
        bytes memory init = abi.encodeCall(
            ZtdxReserveVault.initialize,
            (address(usdt), signer, address(registry), "ZTDX Reserve Vault", "1", owner)
        );
        vault = ZtdxReserveVault(address(new ERC1967Proxy(address(impl), init)));
    }

    // ============ helpers ============

    function _fund(address user, uint256 amount) internal {
        usdt.mint(user, amount);
        vm.startPrank(user);
        usdt.approve(address(vault), amount);
        vault.fundAccount(amount, bytes32(0));
        vm.stopPrank();
    }

    function _fundExpectingCode(address user, bytes32 code, bytes32 expectedCode) internal {
        usdt.mint(user, 100e6);
        vm.startPrank(user);
        usdt.approve(address(vault), 100e6);
        vm.expectEmit(true, false, false, true, address(vault));
        emit AccountFunded(user, 100e6, expectedCode);
        vault.fundAccount(100e6, code);
        vm.stopPrank();
    }

    function _signRelease(address user, uint256 amount, uint256 deadline) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            vault.RELEASE_TYPEHASH(), user, amount, vault.releaseNonces(user), deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _release(address user, uint256 amount) internal {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRelease(user, amount, deadline);
        vm.prank(user);
        vault.releaseFunds(amount, deadline, sig);
    }

    // ============ ZTD-06: AccountFunded reports the effective code ============

    function test_FundAccount_EmitsNewlyBoundCode() public {
        _fundExpectingCode(alice, CODE_CAROL, CODE_CAROL);
        assertEq(registry.traderCodeOf(alice), CODE_CAROL);
    }

    function test_FundAccount_EmitsExistingCodeWhenAlreadyBound() public {
        _fundExpectingCode(alice, CODE_CAROL, CODE_CAROL);
        _fundExpectingCode(alice, CODE_BOB, CODE_CAROL);
        assertEq(registry.traderCodeOf(alice), CODE_CAROL);
    }

    function test_FundAccount_EmitsZeroForUnknownCode() public {
        _fundExpectingCode(alice, keccak256("UNKNOWN"), bytes32(0));
    }

    function test_FundAccount_EmitsZeroForOwnCode() public {
        _fundExpectingCode(carol, CODE_CAROL, bytes32(0));
    }

    // ============ ZTD-11: referral attribution fixed at first funding ============

    function test_FundAccount_LaterFundingDoesNotBindCode() public {
        _fund(alice, 100e6);
        _fundExpectingCode(alice, CODE_CAROL, bytes32(0));
        assertEq(registry.traderCodeOf(alice), bytes32(0));
    }

    function test_BindAffiliateCode_BeforeFundingBinds() public {
        vm.prank(alice);
        vault.bindAffiliateCode(CODE_CAROL);
        assertEq(registry.traderCodeOf(alice), CODE_CAROL);
    }

    function test_BindAffiliateCode_AfterFundingReverts() public {
        _fund(alice, 100e6);
        vm.prank(alice);
        vm.expectRevert(ZtdxReserveVault.AffiliateBindingClosed.selector);
        vault.bindAffiliateCode(CODE_CAROL);
        assertEq(registry.traderCodeOf(alice), bytes32(0));
    }

    // ============ ZTD-04: releases above principal are bounded ============

    function test_ReleaseFunds_WithinPrincipalDoesNotConsumeExcessAllowance() public {
        vm.prank(owner);
        vault.setExcessReleaseLimits(1e6, 1e6);
        _fund(alice, 100e6);

        _release(alice, 100e6);

        assertEq(usdt.balanceOf(alice), 100e6);
        assertEq(vault.accountLedgers(alice), 0);
        assertEq(vault.excessReleasedInWindow(), 0);
    }

    function test_ReleaseFunds_ExcessUnlimitedByDefault() public {
        _fund(bob, 1_000e6);
        _fund(alice, 100e6);

        _release(alice, 150e6);

        assertEq(usdt.balanceOf(alice), 150e6);
        assertEq(vault.accountLedgers(alice), 0);
        assertEq(vault.excessReleasedInWindow(), 50e6);
        assertEq(vault.aggregateReleases(), 150e6);
    }

    function test_ReleaseFunds_ExcessAboveTxLimitReverts() public {
        vm.prank(owner);
        vault.setExcessReleaseLimits(40e6, 0);
        _fund(bob, 1_000e6);
        _fund(alice, 100e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRelease(alice, 150e6, deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZtdxReserveVault.ExcessReleaseAboveTxLimit.selector, 50e6, 40e6));
        vault.releaseFunds(150e6, deadline, sig);

        _release(alice, 140e6);
        assertEq(usdt.balanceOf(alice), 140e6);
    }

    function test_ReleaseFunds_ExcessWindowLimitResetsAfterWindow() public {
        vm.prank(owner);
        vault.setExcessReleaseLimits(0, 60e6);
        _fund(bob, 1_000e6);
        _fund(alice, 100e6);
        _release(alice, 150e6); // 50 above principal

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRelease(alice, 20e6, deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZtdxReserveVault.ExcessReleaseAboveWindowLimit.selector, 20e6, 10e6));
        vault.releaseFunds(20e6, deadline, sig);

        vm.warp(block.timestamp + vault.EXCESS_RELEASE_WINDOW());
        _release(alice, 20e6);

        assertEq(vault.excessReleasedInWindow(), 20e6);
        assertEq(usdt.balanceOf(alice), 170e6);
    }

    function test_ReleaseFunds_WindowLimitLoweredBelowReleasedReportsZeroRemaining() public {
        _fund(bob, 1_000e6);
        _fund(alice, 100e6);
        _release(alice, 150e6); // 50 above principal, no limit yet

        vm.prank(owner);
        vault.setExcessReleaseLimits(0, 30e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRelease(alice, 1e6, deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZtdxReserveVault.ExcessReleaseAboveWindowLimit.selector, 1e6, 0));
        vault.releaseFunds(1e6, deadline, sig);
    }

    function test_SetExcessReleaseLimits_OwnerOnly_EmitsEvent() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit ExcessReleaseLimitsChanged(10e6, 100e6);
        vm.prank(owner);
        vault.setExcessReleaseLimits(10e6, 100e6);

        assertEq(vault.excessReleaseTxLimit(), 10e6);
        assertEq(vault.excessReleaseWindowLimit(), 100e6);

        vm.prank(alice);
        vm.expectRevert();
        vault.setExcessReleaseLimits(0, 0);
    }

    // ============ ZTD-07 / ZTD-10: registry setter ============

    function test_SetAffiliateRegistry_ZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZtdxReserveVault.ZeroAddress.selector);
        vault.setAffiliateRegistry(address(0));
    }

    function test_SetAffiliateRegistry_EmitsEvent() public {
        address newRegistry = address(0xBEEF);
        vm.expectEmit(true, true, false, false, address(vault));
        emit AffiliateRegistryChanged(address(registry), newRegistry);
        vm.prank(owner);
        vault.setAffiliateRegistry(newRegistry);

        assertEq(address(vault.affiliateRegistry()), newRegistry);
    }

    // ============ pause emits a single event ============

    function test_Pause_EmitsPausedOnce() public {
        vm.recordLogs();
        vm.prank(owner);
        vault.pause();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Paused(address)")) count++;
        }
        assertEq(count, 1);
    }

    // ============ partner settlement stays bounded by credit ============

    function test_SettlePartnerLedger_AboveCreditReverts() public {
        _fund(alice, 100e6);
        vm.startPrank(owner);
        vault.creditPartnerLedger(carol, 30e6);
        vm.expectRevert(abi.encodeWithSelector(ZtdxReserveVault.InsufficientInstitutionalBalance.selector, 50e6, 30e6));
        vault.settlePartnerLedger(carol, 50e6);
        vm.stopPrank();
    }
}
