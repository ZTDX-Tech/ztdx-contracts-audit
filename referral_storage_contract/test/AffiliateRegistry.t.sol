// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/contracts/referral/AffiliateRegistry.sol";

contract AffiliateRegistryTest is Test {
    // ------- events (redeclare for expectEmit) -------
    event AffiliateCodeCreated(bytes32 indexed code, address indexed owner);
    event TraderAffiliateAttached(address indexed trader, bytes32 indexed code, address indexed referrer);
    event AffiliateTierConfigured(uint256 indexed tierId, uint256 totalRebate, uint256 discountShare);
    event AffiliateTierAssigned(address indexed referrer, uint256 indexed tierId);
    event AffiliateDiscountShareSet(address indexed referrer, uint256 discountShare);
    event AffiliateCodeOwnerChanged(bytes32 indexed code, address indexed oldOwner, address indexed newOwner);

    AffiliateRegistry registry;
    address admin = address(0xA11CE);
    address handler = address(0xC0FFEE);
    address alice = address(0xA11);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    bytes32 constant CODE_ALICE = keccak256("ALICE-2025");
    bytes32 constant CODE_BOB = keccak256("BOB-2025");

    function setUp() public {
        AffiliateRegistry impl = new AffiliateRegistry();
        bytes memory init = abi.encodeCall(AffiliateRegistry.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        registry = AffiliateRegistry(address(proxy));

        // grant handler role from admin
        vm.prank(admin);
        registry.authorizeHandler(handler);
    }

    // ============ init ============

    function test_Constructor_DisablesInitializersOnImpl() public {
        AffiliateRegistry impl = new AffiliateRegistry();
        vm.expectRevert(); // Initializable: contract is already initialized
        impl.initialize(admin);
    }

    function test_Init_GrantsRoles() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.ADMIN_ROLE(), admin));
    }

    function test_Init_ZeroAdminReverts() public {
        AffiliateRegistry impl = new AffiliateRegistry();
        bytes memory init = abi.encodeCall(AffiliateRegistry.initialize, (address(0)));
        vm.expectRevert(AffiliateRegistry.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), init);
    }

    function test_Init_CannotInitTwice() public {
        vm.expectRevert(); // Initializable: contract is already initialized
        registry.initialize(alice);
    }

    // ============ createAffiliateCode ============

    function test_CreateCode_HappyPath() public {
        vm.expectEmit(true, true, false, false);
        emit AffiliateCodeCreated(CODE_ALICE, alice);
        vm.prank(alice);
        registry.createAffiliateCode(CODE_ALICE);
        assertEq(registry.codeOwnerOf(CODE_ALICE), alice);
    }

    function test_CreateCode_ZeroCodeReverts() public {
        vm.expectRevert(AffiliateRegistry.ZeroCode.selector);
        vm.prank(alice);
        registry.createAffiliateCode(bytes32(0));
    }

    function test_CreateCode_DuplicateReverts() public {
        vm.prank(alice);
        registry.createAffiliateCode(CODE_ALICE);
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.CodeAlreadyExists.selector, CODE_ALICE));
        vm.prank(bob);
        registry.createAffiliateCode(CODE_ALICE);
    }

    // ============ attachTraderCode ============

    function test_AttachTrader_HappyPath() public {
        vm.prank(alice);
        registry.createAffiliateCode(CODE_ALICE);

        vm.expectEmit(true, true, true, false);
        emit TraderAffiliateAttached(bob, CODE_ALICE, alice);
        vm.prank(handler);
        registry.attachTraderCode(bob, CODE_ALICE);

        assertEq(registry.traderCodeOf(bob), CODE_ALICE);
        (bytes32 code, address referrer) = registry.resolveTraderAffiliate(bob);
        assertEq(code, CODE_ALICE);
        assertEq(referrer, alice);
    }

    function test_AttachTrader_OnlyHandlerRole() public {
        vm.prank(alice);
        registry.createAffiliateCode(CODE_ALICE);
        vm.prank(bob); // not a handler
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        registry.attachTraderCode(carol, CODE_ALICE);
    }

    function test_AttachTrader_CodeDoesNotExistReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.CodeDoesNotExist.selector, CODE_ALICE));
        vm.prank(handler);
        registry.attachTraderCode(bob, CODE_ALICE);
    }

    function test_AttachTrader_TraderAlreadyHasCodeReverts() public {
        vm.startPrank(alice);
        registry.createAffiliateCode(CODE_ALICE);
        vm.stopPrank();
        vm.prank(bob);
        registry.createAffiliateCode(CODE_BOB);

        vm.prank(handler);
        registry.attachTraderCode(carol, CODE_ALICE);
        vm.prank(handler);
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.TraderAlreadyHasCode.selector, carol, CODE_ALICE));
        registry.attachTraderCode(carol, CODE_BOB);
    }

    function test_AttachTrader_SelfReferralReverts() public {
        vm.prank(alice);
        registry.createAffiliateCode(CODE_ALICE);
        vm.prank(handler);
        vm.expectRevert("Cannot use own code");
        registry.attachTraderCode(alice, CODE_ALICE);
    }

    // ============ configureTier ============

    function test_ConfigureTier_HappyPath() public {
        vm.expectEmit(true, false, false, true);
        emit AffiliateTierConfigured(1, 1000, 5000); // tier 1 · 10% rebate · 50% share
        vm.prank(admin);
        registry.configureTier(1, 1000, 5000);
        (uint256 total, uint256 share) = registry.tierSettings(1);
        assertEq(total, 1000);
        assertEq(share, 5000);
    }

    function test_ConfigureTier_OnlyAdminRole() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.configureTier(1, 1000, 5000);
    }

    function test_ConfigureTier_InvalidTotalRebateReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.InvalidTotalRebate.selector, 10_001));
        registry.configureTier(1, 10_001, 5000); // > BASIS_POINTS
    }

    function test_ConfigureTier_InvalidDiscountShareReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.InvalidDiscountShare.selector, 10_001));
        registry.configureTier(1, 1000, 10_001);
    }

    // ============ assignAffiliateTier + custom share ============

    function test_AssignAffiliateTier_HappyPath() public {
        vm.prank(admin);
        registry.configureTier(3, 1000, 5000);

        vm.expectEmit(true, true, false, false);
        emit AffiliateTierAssigned(alice, 3);
        vm.prank(admin);
        registry.assignAffiliateTier(alice, 3);
        assertEq(registry.affiliateTiers(alice), 3);
    }

    // ============ ZTD-08: only configured tiers can be assigned ============

    function test_AssignAffiliateTier_UnconfiguredReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.TierNotConfigured.selector, 5));
        registry.assignAffiliateTier(alice, 5);
    }

    function test_AssignAffiliateTier_ZeroRateTierAllowedOnceConfigured() public {
        assertFalse(registry.isTierConfigured(2));
        vm.startPrank(admin);
        registry.configureTier(2, 0, 0);
        registry.assignAffiliateTier(alice, 2);
        vm.stopPrank();
        assertTrue(registry.isTierConfigured(2));
        assertEq(registry.affiliateTiers(alice), 2);
    }

    function test_SetAffiliateDiscountShare_ValidatesRange() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AffiliateRegistry.InvalidDiscountShare.selector, 10_001));
        registry.setAffiliateDiscountShare(alice, 10_001);
    }

    // ============ handler admin ============

    function test_AuthorizeHandler_GrantsRole() public {
        vm.prank(admin);
        registry.authorizeHandler(carol);
        assertTrue(registry.hasRole(registry.HANDLER_ROLE(), carol));
    }

    function test_RemoveHandler_RevokesRole() public {
        vm.prank(admin);
        registry.removeHandler(handler);
        assertFalse(registry.hasRole(registry.HANDLER_ROLE(), handler));
    }

    function test_AuthorizeHandler_ZeroAddressReverts() public {
        vm.prank(admin);
        vm.expectRevert(AffiliateRegistry.ZeroAddress.selector);
        registry.authorizeHandler(address(0));
    }

    // ============ ZTD-13: ADMIN_ROLE alone can manage handlers ============

    function test_HandlerHelpers_WorkWithOnlyAdminRole() public {
        bytes32 adminRole = registry.ADMIN_ROLE();
        bytes32 handlerRole = registry.HANDLER_ROLE();
        vm.prank(admin);
        registry.grantRole(adminRole, carol);
        assertFalse(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), carol));

        vm.prank(carol);
        registry.authorizeHandler(bob);
        assertTrue(registry.hasRole(handlerRole, bob));

        vm.prank(carol);
        registry.removeHandler(bob);
        assertFalse(registry.hasRole(handlerRole, bob));
    }

    function test_HandlerHelpers_RejectNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.authorizeHandler(bob);
    }

    // ============ governance: adminTransferCodeOwner ============

    function test_AdminTransferCodeOwner_HappyPath() public {
        vm.prank(alice);
        registry.createAffiliateCode(CODE_ALICE);
        vm.expectEmit(true, true, true, false);
        emit AffiliateCodeOwnerChanged(CODE_ALICE, alice, bob);
        vm.prank(admin); // has DEFAULT_ADMIN_ROLE
        registry.adminTransferCodeOwner(CODE_ALICE, bob);
        assertEq(registry.codeOwnerOf(CODE_ALICE), bob);
    }

    function test_AdminTransferCodeOwner_OnlyDefaultAdmin() public {
        // ADMIN_ROLE ≠ DEFAULT_ADMIN_ROLE — grant only ADMIN_ROLE and expect revert.
        // Use startPrank so both the ADMIN_ROLE() view and the grantRole call run as admin.
        bytes32 adminRole = registry.ADMIN_ROLE();
        vm.startPrank(admin);
        registry.grantRole(adminRole, carol);
        vm.stopPrank();
        vm.prank(carol);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        registry.adminTransferCodeOwner(CODE_ALICE, bob);
    }

    // ============ UUPS upgrade authorization ============

    function test_Upgrade_OnlyDefaultAdmin() public {
        AffiliateRegistry impl2 = new AffiliateRegistry();
        vm.prank(alice);
        vm.expectRevert();
        registry.upgradeToAndCall(address(impl2), "");
    }

    function test_Upgrade_ZeroImplReverts() public {
        vm.prank(admin);
        vm.expectRevert(AffiliateRegistry.ZeroAddress.selector);
        registry.upgradeToAndCall(address(0), "");
    }
}
