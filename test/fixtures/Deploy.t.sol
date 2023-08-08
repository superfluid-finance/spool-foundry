// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
  ISuperfluid,
  ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { PoolV1 } from "../../src/Pool-V1.sol";
import { IPoolV1 } from "../../src/interfaces/IPool-V1.sol";
import { ISuperPoolFactory } from "../../src/interfaces/ISuperPoolFactory.sol";

import { PoolInternalV1 } from "../../src/PoolInternal-V1.sol";

import { PoolStrategyV1 } from "../../src/PoolStrategy-V1.sol";
import { IPoolStrategyV1 } from "../../src/interfaces/IPoolStrategy-V1.sol";
import { ERC20Mintable } from "../../src/interfaces/ERC20Mintable.sol";

import { SuperPoolFactory } from "../../src/SuperPoolFactory.sol";
import { UUPSProxy } from "../../src/upgradability/UUPSProxy.sol";

import { IPool } from "../../src/aave/IPool.sol";

import { IOps } from "../../src/gelato/IOps.sol";

import { DataTypes } from "../../src/libraries/DataTypes.sol";

import { Config } from "./Config.sol";

abstract contract DeployPool is Test, Config {
  PoolV1 poolLogic;

  PoolInternalV1 poolInternalLogic;

  PoolStrategyV1 poolStrategyLogic;

  SuperPoolFactory poolFactoryLogic;

  constructor() { }

  function deploy() public {
    vm.startBroadcast();

    poolLogic = new PoolV1();

    poolInternalLogic = new PoolInternalV1();

    poolStrategyLogic = new PoolStrategyV1();

    DataTypes.SuperPoolFactoryInitializer memory factoryInitialize =
      DataTypes.SuperPoolFactoryInitializer(host, address(poolLogic), address(poolInternalLogic), ops);

    poolFactoryLogic = new SuperPoolFactory(factoryInitialize);

    address poolAddress = ISuperPoolFactory(address(poolFactoryLogic)).createSuperPool(
      DataTypes.CreatePoolInput(address(superToken), address(poolStrategyLogic), token, aavePool, aToken, aaveToken)
    );

    poolProxy = PoolV1(payable(poolAddress));

    strategyProxy = UUPSProxy(payable(poolProxy.poolStrategy()));

    string memory line1 = string(abi.encodePacked('{"pool":"', vm.toString(address(poolProxy)), '"}'));
    vm.writeFile("./test/addresses.json", line1);
    vm.stopBroadcast();

    vm.warp(block.timestamp + 27 seconds);
  }
}
