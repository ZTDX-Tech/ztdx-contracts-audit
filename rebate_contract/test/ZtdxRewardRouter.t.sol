// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/contracts/core/referral/ZtdxRewardRouter.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") { _mint(msg.sender, 1_000_000_000 ether); }
    function decimals() public pure override returns (uint8) { return 6; }
}

contract ZtdxRewardRouterTest is Test {
    event RewardRedeemed(address indexed user, uint256 amount, uint256 nonce);
    event RewardBatchSettled(uint256 indexed batchId, uint256 totalAmount, uint256 userCount);
    event AuthorizationSignerChanged(address indexed oldSigner, address indexed newSigner);
    event AffiliateRegistryChanged(address indexed oldRegistry, address indexed newRegistry);

    ZtdxRewardRouter router;
    MockUSDT usdt;
    address owner = address(0xA11CE);
    address vaultStub = address(0xBEEF);
    uint256 signerPk = 0xB0BB051;
    address signer;
    address alice = address(0xA11);
    address bob = address(0xB0B);

    string constant DOMAIN_NAME = "ZTDX Reward Router";
    string constant DOMAIN_VERSION = "1";

    function setUp() public {
        signer = vm.addr(signerPk);
        usdt = new MockUSDT();

        ZtdxRewardRouter impl = new ZtdxRewardRouter();
        bytes memory init = abi.encodeCall(
            ZtdxRewardRouter.initialize,
            (address(usdt), vaultStub, signer, address(0), DOMAIN_NAME, DOMAIN_VERSION, owner)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        router = ZtdxRewardRouter(address(proxy));

        // Fund router with USDT so redeem can transfer out.
        usdt.transfer(address(router), 1_000_000 ether);
    }

    // ============ init ============

    function test_Constructor_DisablesInitializersOnImpl() public {
        ZtdxRewardRouter impl = new ZtdxRewardRouter();
        vm.expectRevert();
        impl.initialize(address(usdt), vaultStub, signer, address(0), DOMAIN_NAME, DOMAIN_VERSION, owner);
    }

    function test_Init_SetsState() public view {
        assertEq(address(router.settlementToken()), address(usdt));
        assertEq(address(router.reserveVault()), vaultStub);
        assertEq(router.authorizationSigner(), signer);
        assertEq(router.owner(), owner);
        assertEq(router.domainName(), DOMAIN_NAME);
        assertEq(router.domainVersion(), DOMAIN_VERSION);
        assertTrue(router.domainSeparator() != bytes32(0));
    }

    function test_Init_ZeroUsdtReverts() public {
        ZtdxRewardRouter impl = new ZtdxRewardRouter();
        bytes memory init = abi.encodeCall(
            ZtdxRewardRouter.initialize,
            (address(0), vaultStub, signer, address(0), DOMAIN_NAME, DOMAIN_VERSION, owner)
        );
        vm.expectRevert(ZtdxRewardRouter.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), init);
    }

    function test_Init_EmptyDomainNameReverts() public {
        ZtdxRewardRouter impl = new ZtdxRewardRouter();
        bytes memory init = abi.encodeCall(
            ZtdxRewardRouter.initialize,
            (address(usdt), vaultStub, signer, address(0), "", DOMAIN_VERSION, owner)
        );
        vm.expectRevert(ZtdxRewardRouter.EmptyDomainName.selector);
        new ERC1967Proxy(address(impl), init);
    }

    function test_Init_CannotInitTwice() public {
        vm.expectRevert();
        router.initialize(address(usdt), vaultStub, signer, address(0), DOMAIN_NAME, DOMAIN_VERSION, owner);
    }

    // ============ redeemReward ============

    function _signRedeem(address user, uint256 amount, uint256 nonce, uint256 deadline) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            router.REWARD_TYPEHASH(),
            user, amount, nonce, deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", router.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_RedeemReward_HappyPath() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRedeem(alice, amount, 0, deadline);

        vm.expectEmit(true, false, false, true);
        emit RewardRedeemed(alice, amount, 0);
        vm.prank(alice);
        router.redeemReward(amount, deadline, sig);

        assertEq(usdt.balanceOf(alice), amount);
        assertEq(router.redeemedRewards(alice), amount);
        assertEq(router.rewardNonces(alice), 1);
    }

    function test_RedeemReward_InvalidSignerReverts() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;
        // Sign with a key that is not authorizationSigner.
        uint256 wrongPk = 0xDEAD;
        bytes32 structHash = keccak256(abi.encode(
            router.REWARD_TYPEHASH(),
            alice, amount, uint256(0), deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", router.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(ZtdxRewardRouter.InvalidSignature.selector);
        router.redeemReward(amount, deadline, badSig);
    }

    function test_RedeemReward_ReplayReverts() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRedeem(alice, amount, 0, deadline);
        vm.prank(alice);
        router.redeemReward(amount, deadline, sig);

        // Replay uses nonce=0 signature but on-chain nonce is now 1 → recovers wrong signer.
        vm.prank(alice);
        vm.expectRevert(ZtdxRewardRouter.InvalidSignature.selector);
        router.redeemReward(amount, deadline, sig);
    }

    function test_RedeemReward_ExpiredReverts() public {
        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp; // valid at signing time
        bytes memory sig = _signRedeem(alice, amount, 0, deadline);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(
            ZtdxRewardRouter.SignatureExpired.selector, deadline, block.timestamp
        ));
        router.redeemReward(amount, deadline, sig);
    }

    function test_RedeemReward_ZeroAmountReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRedeem(alice, 0, 0, deadline);
        vm.prank(alice);
        vm.expectRevert(ZtdxRewardRouter.ZeroAmount.selector);
        router.redeemReward(0, deadline, sig);
    }

    function test_RedeemReward_SecondClaimIncrementsNonce() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig1 = _signRedeem(alice, amount1, 0, deadline);
        vm.prank(alice);
        router.redeemReward(amount1, deadline, sig1);

        bytes memory sig2 = _signRedeem(alice, amount2, 1, deadline);
        vm.prank(alice);
        router.redeemReward(amount2, deadline, sig2);

        assertEq(router.redeemedRewards(alice), amount1 + amount2);
        assertEq(router.rewardNonces(alice), 2);
    }

    // ============ batchSettleRewards ============

    function test_BatchSettle_HappyPath_OwnerOnly() public {
        address[] memory users = new address[](2);
        users[0] = alice; users[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether; amounts[1] = 200 ether;

        vm.expectEmit(true, false, false, true);
        emit RewardBatchSettled(42, 300 ether, 2);
        vm.prank(owner);
        router.batchSettleRewards(users, amounts, 42);

        assertEq(usdt.balanceOf(alice), 100 ether);
        assertEq(usdt.balanceOf(bob), 200 ether);
        assertEq(router.redeemedRewards(alice), 100 ether);
        assertEq(router.redeemedRewards(bob), 200 ether);
    }

    function test_BatchSettle_OnlyOwner() public {
        address[] memory u = new address[](1);
        u[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 1 ether;
        vm.prank(alice);
        vm.expectRevert();
        router.batchSettleRewards(u, a, 1);
    }

    function test_BatchSettle_ArrayLengthMismatchReverts() public {
        address[] memory u = new address[](2);
        u[0] = alice; u[1] = bob;
        uint256[] memory a = new uint256[](1);
        a[0] = 1 ether;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZtdxRewardRouter.ArrayLengthMismatch.selector, 2, 1));
        router.batchSettleRewards(u, a, 1);
    }

    function test_BatchSettle_SkipsZeroAmountsAndZeroAddress() public {
        address[] memory u = new address[](3);
        u[0] = address(0); u[1] = alice; u[2] = bob;
        uint256[] memory a = new uint256[](3);
        a[0] = 100 ether; a[1] = 100 ether; a[2] = 0;
        vm.expectEmit(true, false, false, true);
        emit RewardBatchSettled(7, 100 ether, 1);
        vm.prank(owner);
        router.batchSettleRewards(u, a, 7);
        assertEq(usdt.balanceOf(alice), 100 ether);
        assertEq(usdt.balanceOf(bob), 0);
        assertEq(router.redeemedRewards(alice), 100 ether);
    }

    function test_BatchSettle_SameBatchIdReverts() public {
        address[] memory u = new address[](1);
        u[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 1 ether;
        vm.startPrank(owner);
        router.batchSettleRewards(u, a, 9);
        vm.expectRevert(abi.encodeWithSelector(ZtdxRewardRouter.BatchAlreadySettled.selector, 9));
        router.batchSettleRewards(u, a, 9);
        vm.stopPrank();
    }

    // ============ ZTD-09: duplicate recipients rejected ============

    function test_BatchSettle_DuplicateUserReverts() public {
        address[] memory u = new address[](2);
        u[0] = alice; u[1] = alice;
        uint256[] memory a = new uint256[](2);
        a[0] = 1 ether; a[1] = 1 ether;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZtdxRewardRouter.UsersNotStrictlyAscending.selector, 1));
        router.batchSettleRewards(u, a, 1);
    }

    function test_BatchSettle_UnsortedUsersReverts() public {
        address[] memory u = new address[](2);
        u[0] = bob; u[1] = alice;
        uint256[] memory a = new uint256[](2);
        a[0] = 1 ether; a[1] = 1 ether;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZtdxRewardRouter.UsersNotStrictlyAscending.selector, 1));
        router.batchSettleRewards(u, a, 1);
    }

    // ============ ZTD-14: batch settlement invalidates outstanding signatures ============

    function test_BatchSettle_InvalidatesOutstandingRedeemSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRedeem(alice, 100 ether, 0, deadline);

        address[] memory u = new address[](1);
        u[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 100 ether;
        vm.prank(owner);
        router.batchSettleRewards(u, a, 1);
        assertEq(router.rewardNonces(alice), 1);

        vm.prank(alice);
        vm.expectRevert(ZtdxRewardRouter.InvalidSignature.selector);
        router.redeemReward(100 ether, deadline, sig);
        assertEq(usdt.balanceOf(alice), 100 ether);
    }

    // ============ admin ============

    function test_SetAuthorizationSigner_OwnerOnly_EmitsEvent() public {
        address newSigner = address(0xBABE);
        vm.expectEmit(true, true, false, false);
        emit AuthorizationSignerChanged(signer, newSigner);
        vm.prank(owner);
        router.setAuthorizationSigner(newSigner);
        assertEq(router.authorizationSigner(), newSigner);

        vm.prank(alice);
        vm.expectRevert();
        router.setAuthorizationSigner(alice);
    }

    function test_SetAuthorizationSigner_ZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZtdxRewardRouter.ZeroAddress.selector);
        router.setAuthorizationSigner(address(0));
    }

    function test_SetAffiliateRegistry_ZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZtdxRewardRouter.ZeroAddress.selector);
        router.setAffiliateRegistry(address(0));
    }

    function test_SetAffiliateRegistry_OwnerOnly_EmitsEvent() public {
        address newRegistry = address(0xFEED);
        vm.expectEmit(true, true, false, false, address(router));
        emit AffiliateRegistryChanged(address(0), newRegistry);
        vm.prank(owner);
        router.setAffiliateRegistry(newRegistry);
        assertEq(address(router.affiliateRegistry()), newRegistry);

        vm.prank(alice);
        vm.expectRevert();
        router.setAffiliateRegistry(newRegistry);
    }

    // ============ upgrade auth ============

    function test_Upgrade_OnlyOwner() public {
        ZtdxRewardRouter impl2 = new ZtdxRewardRouter();
        vm.prank(alice);
        vm.expectRevert();
        router.upgradeToAndCall(address(impl2), "");
    }

    function test_Upgrade_ZeroImplReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZtdxRewardRouter.ZeroAddress.selector);
        router.upgradeToAndCall(address(0), "");
    }
}
