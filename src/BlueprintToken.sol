// SPDX-License-Identifier: Apache-2.0
/*
__________.__                             .__        __   
\______   \  |  __ __   ____ _____________|__| _____/  |_ 
 |    |  _/  | |  |  \_/ __ \\____ \_  __ \  |/    \   __\
 |    |   \  |_|  |  /\  ___/|  |_> >  | \/  |   |  \  |  
 |______  /____/____/  \___  >   __/|__|  |__|___|  /__|  
        \/                 \/|__|                 \/      
*/

pragma solidity 0.8.26;

import {ERC20Upgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract BlueprintToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address treasury) external initializer {
        __ERC20_init("Blueprint", "BP");
        __ERC20Burnable_init();
        __ERC20Permit_init("Blueprint");
        __Ownable_init(treasury);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        uint256 supply = 10_000_000_000 * (10 ** uint256(decimals()));
        _mint(treasury, supply);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
