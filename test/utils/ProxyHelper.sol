// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ProxyHelper
 * @notice Helper contract for testing upgradeable contracts with proxies
 */
contract ProxyHelper {
    /**
     * @notice Deploy an implementation contract behind a proxy
     * @param implementation The address of the implementation contract
     * @param data The initialization data to call on the proxy
     * @return proxy The address of the deployed proxy
     */
    function deployProxy(address implementation, bytes memory data) public returns (address proxy) {
        // Deploy an ERC1967 proxy with the given implementation and initialization data
        proxy = address(new ERC1967Proxy(implementation, data));
        return proxy;
    }
} 