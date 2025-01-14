// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISuperfluid, ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ERC20Mintable } from "../../src/interfaces/ERC20Mintable.sol";
import { IPool } from "../../src/aave/IPool.sol";
import { DataTypes } from "../../src/libraries/DataTypes.sol";
import { PoolV1 } from "../../src/Pool-V1.sol";
import { IOps } from "../../src/gelato/IOps.sol";
import { Users } from "./Users.t.sol";
import { Gelato } from "./Gelato.t.sol";
import { Config } from "./Config.sol";

abstract contract Report is Test, Users, Gelato {

  function logCurrentPool() internal view returns (DataTypes.Pool memory currentPool) {
    currentPool = poolProxy.getLastPool();
  }

  function calculateUsersTotalBalance() internal view returns (uint256 usersBalance) {
    usersBalance = (poolProxy.balanceOf(user1) / (10 ** 12)) + (poolProxy.balanceOf(user2) / (10 ** 12)) + (poolProxy.balanceOf(user3) / (10 ** 12)) + (poolProxy.balanceOf(user4) / (10 ** 12));
    DataTypes.Pool memory currentPool = poolProxy.getLastPool();
    //  console.log(33, usersBalance);
    //  console.log(currentPool.yieldObject.protocolYield);
    usersBalance = usersBalance + currentPool.yieldObject.protocolYield / (10 ** 12);
    //  console.log(34, usersBalance);
  }

  function calculatePoolTotalBalance() internal view returns (uint256 poolBalance) {
    uint256 superTokenBalance = superToken.balanceOf(address(poolProxy)) / (10 ** 12);
    //  console.log(41,superTokenBalance);
    uint256 aaveBalance = aToken.balanceOf(address(strategyProxy));
    //     console.log(43,aaveBalance );
    uint256 depositUser1 = getFlowDeposit(address(poolProxy), user1) / (10 ** 12);
    uint256 depositUser2 = getFlowDeposit(address(poolProxy), user2) / (10 ** 12);
    uint256 depositUser3 = getFlowDeposit(address(poolProxy), user3) / (10 ** 12);
    uint256 depositUser4 = getFlowDeposit(address(poolProxy), user4) / (10 ** 12);

    // console.log(49,depositUser1, depositUser2);

    uint256 deposit = depositUser1 + depositUser2 + depositUser3 + depositUser4;
    poolBalance = superTokenBalance + aaveBalance + deposit;

    // console.log(51, poolBalance);
  }
}
