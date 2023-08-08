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

  ISuperToken superToken = ISuperToken(0x8aE68021f6170E5a766bE613cEA0d75236ECCa9a);
  ERC20Mintable token = ERC20Mintable(0xc94dd466416A7dFE166aB2cF916D3875C049EBB7);

  IPool aavePool = IPool(0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6);
  IERC20 aUSDC = IERC20(0x1Ee669290939f8a8864497Af3BC83728715265FF);
  ERC20Mintable aaveUSDC = ERC20Mintable(0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43);

  function setUp() public { }

  function run() public {
    SuperPoolFactory poolFactoryLogic = SuperPoolFactory(0xD0bfF41F0E12d9dcf116df0DDd84034A7A443609);
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
