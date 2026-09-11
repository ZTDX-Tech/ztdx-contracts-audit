// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/referral/AffiliateRegistry.sol";

contract DeployAffiliateRegistrySepolia is Script {
    function run() external returns (AffiliateRegistry affiliateRegistry) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying AffiliateRegistry to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);

        vm.startBroadcast(deployerPrivateKey);
        AffiliateRegistry implementation = new AffiliateRegistry();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(AffiliateRegistry.initialize, (admin))
        );
        affiliateRegistry = AffiliateRegistry(address(proxy));
        vm.stopBroadcast();

        console.log("AffiliateRegistry deployed at:", address(affiliateRegistry));
        console.log("AffiliateRegistry implementation:", address(implementation));
    }
}

contract DeployAffiliateRegistryMainnet is Script {
    function run() external returns (AffiliateRegistry affiliateRegistry) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying AffiliateRegistry to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);

        vm.startBroadcast(deployerPrivateKey);
        AffiliateRegistry implementation = new AffiliateRegistry();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(AffiliateRegistry.initialize, (admin))
        );
        affiliateRegistry = AffiliateRegistry(address(proxy));
        vm.stopBroadcast();

        console.log("AffiliateRegistry deployed at:", address(affiliateRegistry));
        console.log("AffiliateRegistry implementation:", address(implementation));
    }
}

contract GrantAffiliateHandlers is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address referralStorageAddress = vm.envAddress("AFFILIATE_REGISTRY_ADDRESS");
        address reserveVault = vm.envAddress("RESERVE_VAULT_ADDRESS");
        address rebateDistributor = vm.envAddress("REWARD_ROUTER_ADDRESS");

        console.log("=== Granting handler roles ===");
        console.log("AffiliateRegistry:", referralStorageAddress);
        console.log("ZtdxReserveVault:", reserveVault);
        console.log("ZtdxRewardRouter:", rebateDistributor);

        vm.startBroadcast(adminPrivateKey);

        AffiliateRegistry affiliateRegistry = AffiliateRegistry(referralStorageAddress);
        affiliateRegistry.authorizeHandler(reserveVault);
        affiliateRegistry.authorizeHandler(rebateDistributor);

        vm.stopBroadcast();

        console.log("Handler roles granted.");
    }
}

contract UpgradeAffiliateRegistry is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address referralStorageProxy = vm.envAddress("AFFILIATE_REGISTRY_ADDRESS");

        console.log("=== Upgrading AffiliateRegistry proxy ===");
        console.log("Proxy:", referralStorageProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new AffiliateRegistry());
        AffiliateRegistry(payable(referralStorageProxy)).upgradeToAndCall(implementation, bytes(""));
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}
