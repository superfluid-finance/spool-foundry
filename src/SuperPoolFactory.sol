// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
  ISuperfluid,
  ISuperToken,
  ISuperApp,
  SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperPoolFactory } from "./interfaces/ISuperPoolFactory.sol";
import { UUPSProxy } from "./upgradability/UUPSProxy.sol";
import { IPoolV1 } from "./interfaces/IPool-V1.sol";
import { IOps } from "./gelato/IOps.sol";
import { DataTypes } from "./libraries/DataTypes.sol";
import { IPoolStrategyV1 } from "./interfaces/IPoolStrategy-V1.sol";
import { IPool } from "./aave/IPool.sol";

contract SuperPoolFactory is ISuperPoolFactory {
  ISuperfluid public immutable host;
  IOps public ops;
  address public owner;
  address public poolLogic;
  address public poolInternalLogic;

  // pool address => poolInfo
  mapping(address => DataTypes.PoolInfo) public poolAddressToPoolInfo;

  error NOT_OWNER();

  constructor(DataTypes.SuperPoolFactoryInitializer memory factoryInitializer) {
    host = factoryInitializer.host;
    ops = factoryInitializer.ops;
    poolLogic = factoryInitializer.poolLogic;
    poolInternalLogic = factoryInitializer.poolInternalLogic;
    owner = msg.sender;
  }

  function createSuperPool(DataTypes.CreatePoolInput memory poolInput) external override returns (address poolAddress) {
    ISuperToken superToken = ISuperToken(poolInput.superToken);

    UUPSProxy poolProxy = new UUPSProxy();
    poolProxy.initializeProxy(poolLogic);

    UUPSProxy poolStrategyProxy = new UUPSProxy();
    poolStrategyProxy.initializeProxy(poolInput.poolStrategyLogic);
    address poolStrategyProxyAddress = address(poolStrategyProxy);

    poolAddress = address(poolProxy);

    ERC20 token = ERC20(superToken.getUnderlyingToken());

    // initializer Pool
    DataTypes.PoolInitializer memory poolInit;
    poolInit = DataTypes.PoolInitializer({
      name: "USDC Aave Lending",
      symbol: string(abi.encodePacked("sp", token.symbol())),
      host: host,
      superToken: superToken,
      token: token,
      poolInternal: poolInternalLogic,
      poolStrategy: IPoolStrategyV1(poolStrategyProxyAddress),
      ops: ops,
      owner: msg.sender
    });

    IPoolV1(poolAddress).initialize(poolInit);

    // initialize strategy
    IPoolStrategyV1(poolStrategyProxyAddress).initialize(
      superToken, poolInput.token, IPoolV1(poolAddress), poolInput.aavePool, poolInput.aToken, poolInput.aaveToken
    );

    // register super app
    uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
      | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

    host.registerAppByFactory(ISuperApp(poolAddress), configWord);

    // initializer PoolInternal
    DataTypes.PoolInfo memory poolInfo = DataTypes.PoolInfo({
      superToken: poolInput.superToken,
      strategy: poolStrategyProxyAddress,
      poolInternal: poolInternalLogic
    });
    poolAddressToPoolInfo[poolAddress] = poolInfo;
  }

  function getVersion() external pure returns (uint256) {
    return 1.0;
  }

  modifier onlyOwner() {
    if(msg.sender != owner) revert NOT_OWNER();
    _;
  }
}
