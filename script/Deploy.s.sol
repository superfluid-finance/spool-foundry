// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
  ISuperfluid,
  ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { PoolV1 } from "../src/Pool-V1.sol";
import { IPoolV1 } from "../src/interfaces/IPool-V1.sol";
import { ISuperPoolFactory } from "../src/interfaces/ISuperPoolFactory.sol";
import { PoolInternalV1 } from "../src/PoolInternal-V1.sol";
import { PoolStrategyV1 } from "../src/PoolStrategy-V1.sol";
import { IPoolStrategyV1 } from "../src/interfaces/IPoolStrategy-V1.sol";
import { SuperPoolFactory } from "../src/SuperPoolFactory.sol";
import { IPool } from "../src/aave/IPool.sol";
import { IOps } from "../src/gelato/IOps.sol";
import { DataTypes } from "../src/libraries/DataTypes.sol";

contract DeployScript is Script {
  ISuperfluid host = ISuperfluid(0xEB796bdb90fFA0f28255275e16936D25d3418603);
  IOps ops = IOps(0xB3f5503f93d5Ef84b06993a1975B9D21B962892F);

  PoolV1 poolLogic;

  PoolInternalV1 poolInternalLogic;

  PoolStrategyV1 poolStrategyLogic;

  SuperPoolFactory poolFactoryLogic;

  function setUp() public { }

  function run() public {
    // get private key from env file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    // deploy pool logic
    poolLogic = new PoolV1();

    // deplloy pool internal logic
    poolInternalLogic = new PoolInternalV1();

    // deploy pool strategy logic
    // poolStrategyLogic = new PoolStrategyV1();

    // deploy super pool factory
    DataTypes.SuperPoolFactoryInitializer memory factoryInitialize =
      DataTypes.SuperPoolFactoryInitializer(host, address(poolLogic), address(poolInternalLogic), ops);
    poolFactoryLogic = new SuperPoolFactory(factoryInitialize);

    vm.stopBroadcast();
  }
}
