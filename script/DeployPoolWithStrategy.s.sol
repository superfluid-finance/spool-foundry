// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
  ISuperfluid,
  ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperPoolFactory } from "../src/interfaces/ISuperPoolFactory.sol";
import { PoolStrategyV1 } from "../src/PoolStrategy-V1.sol";
import { ERC20Mintable } from "../src/interfaces/ERC20Mintable.sol";
import { SuperPoolFactory } from "../src/SuperPoolFactory.sol";
import { IPool } from "../src/aave/IPool.sol";
import { DataTypes } from "../src/libraries/DataTypes.sol";

contract CreatePoolScript is Script {
  PoolStrategyV1 poolStrategyLogic;

  // the SuperToken that will be streamed/deposited into the pool
  ISuperToken superToken = ISuperToken(0x42bb40bF79730451B11f6De1CbA222F17b87Afd7);

  // the underlying ERC20 token
  ERC20Mintable token = ERC20Mintable(0xbe49ac1EadAc65dccf204D4Df81d650B50122aB2);

  // the LendingPool contract
  IPool aavePool = IPool(0x9198F13B08E299d85E096929fA9781A1E3d5d827);

  // the aave interest bearing token
  IERC20 aUSDC = IERC20(0x2271e3Fef9e15046d09E1d78a8FF038c691E9Cf9);

  // the underlying token to be deposited in exchange for the aToken
  ERC20Mintable aaveUSDC = ERC20Mintable(0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e);

  function setUp() public { }

  function run() public {
    SuperPoolFactory poolFactoryLogic = SuperPoolFactory(0x363aDCAef5Aa628Dd81DCd1db8937217a62883D1);
    // get private key from env file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    poolStrategyLogic = new PoolStrategyV1();

    ISuperPoolFactory(address(poolFactoryLogic)).createSuperPool(
      DataTypes.CreatePoolInput(address(superToken), address(poolStrategyLogic), token, aavePool, aUSDC, aaveUSDC)
    );

    vm.stopBroadcast();
  }
}
