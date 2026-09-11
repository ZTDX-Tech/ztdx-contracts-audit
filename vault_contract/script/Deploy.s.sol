// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/core/vault/ZtdxReserveVault.sol";
import "../src/contracts/core/vault/ZtdxSpotVault.sol";

contract DeployReserveVaultSepolia is Script {
    function run() external returns (ZtdxReserveVault reserveVault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address settlementToken = vm.envAddress("USDT_TOKEN_ADDRESS");
        address authorizationSigner = vm.envAddress("SIGNER_ADDRESS");
        address affiliateRegistry = vm.envAddress("AFFILIATE_REGISTRY_ADDRESS");
        string memory domainName = vm.envString("EIP712_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ZtdxReserveVault to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDT:", settlementToken);
        console.log("Backend signer:", authorizationSigner);
        console.log("AffiliateRegistry:", affiliateRegistry);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ZtdxReserveVault implementation = new ZtdxReserveVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxReserveVault.initialize,
                (settlementToken, authorizationSigner, affiliateRegistry, domainName, domainVersion, admin)
            )
        );
        reserveVault = ZtdxReserveVault(address(proxy));
        vm.stopBroadcast();

        console.log("ZtdxReserveVault deployed at:", address(reserveVault));
        console.log("ZtdxReserveVault implementation:", address(implementation));
    }
}

contract DeployReserveVaultMainnet is Script {
    function run() external returns (ZtdxReserveVault reserveVault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address settlementToken = vm.envAddress("MAINNET_USDT_ADDRESS");
        address authorizationSigner = vm.envAddress("SIGNER_ADDRESS");
        address affiliateRegistry = vm.envAddress("MAINNET_AFFILIATE_REGISTRY_ADDRESS");
        string memory domainName = vm.envString("EIP712_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ZtdxReserveVault to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDT:", settlementToken);
        console.log("Backend signer:", authorizationSigner);
        console.log("AffiliateRegistry:", affiliateRegistry);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ZtdxReserveVault implementation = new ZtdxReserveVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxReserveVault.initialize,
                (settlementToken, authorizationSigner, affiliateRegistry, domainName, domainVersion, admin)
            )
        );
        reserveVault = ZtdxReserveVault(address(proxy));
        vm.stopBroadcast();

        console.log("ZtdxReserveVault deployed at:", address(reserveVault));
        console.log("ZtdxReserveVault implementation:", address(implementation));
    }
}

contract UpgradeReserveVault is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address vaultProxy = vm.envAddress("RESERVE_VAULT_ADDRESS");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_VERSION");

        console.log("=== Upgrading ZtdxReserveVault proxy ===");
        console.log("Proxy:", vaultProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));
        console.log("Domain version:", domainVersion);

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new ZtdxReserveVault());
        ZtdxReserveVault(payable(vaultProxy)).upgradeToAndCall(
            implementation,
            abi.encodeCall(ZtdxReserveVault.reinitializeEip712DomainVersion, (domainVersion))
        );
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}

contract DeploySpotVaultSepolia is Script {
    function run() external returns (ZtdxSpotVault spotVault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address authorizationSigner = vm.envAddress("SIGNER_ADDRESS");
        string memory domainName = vm.envString("EIP712_DOMAIN_SPOT_NAME");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_SPOT_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ZtdxSpotVault to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Backend signer:", authorizationSigner);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ZtdxSpotVault implementation = new ZtdxSpotVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxSpotVault.initialize,
                (authorizationSigner, domainName, domainVersion, admin)
            )
        );
        spotVault = ZtdxSpotVault(address(proxy));
        vm.stopBroadcast();

        console.log("ZtdxSpotVault deployed at:", address(spotVault));
        console.log("ZtdxSpotVault implementation:", address(implementation));
    }
}

contract DeploySpotVaultMainnet is Script {
    function run() external returns (ZtdxSpotVault spotVault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address authorizationSigner = vm.envAddress("SIGNER_ADDRESS");
        string memory domainName = vm.envString("EIP712_DOMAIN_SPOT_NAME");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_SPOT_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ZtdxSpotVault to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Backend signer:", authorizationSigner);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ZtdxSpotVault implementation = new ZtdxSpotVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ZtdxSpotVault.initialize,
                (authorizationSigner, domainName, domainVersion, admin)
            )
        );
        spotVault = ZtdxSpotVault(address(proxy));
        vm.stopBroadcast();

        console.log("ZtdxSpotVault deployed at:", address(spotVault));
        console.log("ZtdxSpotVault implementation:", address(implementation));
    }
}

contract UpgradeSpotVault is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address spotVaultProxy = vm.envAddress("SPOT_VAULT_ADDRESS");

        console.log("=== Upgrading ZtdxSpotVault proxy ===");
        console.log("Proxy:", spotVaultProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new ZtdxSpotVault());
        ZtdxSpotVault(payable(spotVaultProxy)).upgradeToAndCall(implementation, "");
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}
