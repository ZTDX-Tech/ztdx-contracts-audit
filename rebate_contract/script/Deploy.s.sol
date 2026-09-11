// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/core/referral/ZtdxRewardRouter.sol";

contract DeployRewardRouterSepolia is Script {
    function run() external returns (ZtdxRewardRouter rebateDistributor) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address settlementToken = vm.envAddress("USDT_TOKEN_ADDRESS");
        address reserveVault = vm.envAddress("RESERVE_VAULT_ADDRESS");
        address authorizationSigner = vm.envAddress("SIGNER_ADDRESS");
        address affiliateRegistry = vm.envAddress("AFFILIATE_REGISTRY_ADDRESS");
        string memory domainName = vm.envString("EIP712_REWARD_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_REWARD_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ZtdxRewardRouter to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDT:", settlementToken);
        console.log("ZtdxReserveVault:", reserveVault);
        console.log("Backend signer:", authorizationSigner);
        console.log("AffiliateRegistry:", affiliateRegistry);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ZtdxRewardRouter implementation = new ZtdxRewardRouter();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxRewardRouter.initialize,
                (settlementToken, reserveVault, authorizationSigner, affiliateRegistry, domainName, domainVersion, admin)
            )
        );
        rebateDistributor = ZtdxRewardRouter(address(proxy));
        vm.stopBroadcast();

        console.log("ZtdxRewardRouter deployed at:", address(rebateDistributor));
        console.log("ZtdxRewardRouter implementation:", address(implementation));
    }
}

contract DeployRewardRouterMainnet is Script {
    function run() external returns (ZtdxRewardRouter rebateDistributor) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address settlementToken = vm.envAddress("MAINNET_USDT_ADDRESS");
        address reserveVault = vm.envAddress("MAINNET_RESERVE_VAULT_ADDRESS");
        address authorizationSigner = vm.envAddress("SIGNER_ADDRESS");
        address affiliateRegistry = vm.envAddress("MAINNET_AFFILIATE_REGISTRY_ADDRESS");
        string memory domainName = vm.envString("EIP712_REWARD_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_REWARD_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ZtdxRewardRouter to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDT:", settlementToken);
        console.log("ZtdxReserveVault:", reserveVault);
        console.log("Backend signer:", authorizationSigner);
        console.log("AffiliateRegistry:", affiliateRegistry);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ZtdxRewardRouter implementation = new ZtdxRewardRouter();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxRewardRouter.initialize,
                (settlementToken, reserveVault, authorizationSigner, affiliateRegistry, domainName, domainVersion, admin)
            )
        );
        rebateDistributor = ZtdxRewardRouter(address(proxy));
        vm.stopBroadcast();

        console.log("ZtdxRewardRouter deployed at:", address(rebateDistributor));
        console.log("ZtdxRewardRouter implementation:", address(implementation));
    }
}

contract UpgradeRewardRouter is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address rebateProxy = vm.envAddress("REWARD_ROUTER_ADDRESS");
        string memory domainVersion = vm.envString("EIP712_REWARD_DOMAIN_VERSION");

        console.log("=== Upgrading ZtdxRewardRouter proxy ===");
        console.log("Proxy:", rebateProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));
        console.log("Domain version:", domainVersion);

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new ZtdxRewardRouter());
        ZtdxRewardRouter(payable(rebateProxy)).upgradeToAndCall(
            implementation,
            abi.encodeCall(
                ZtdxRewardRouter.reinitializeEip712DomainVersion,
                (domainVersion)
            )
        );
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}
