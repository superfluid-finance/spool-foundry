// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISuperfluid, ISuperToken, ISuperApp, SuperAppDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { UUPSProxy } from "./upgradability/UUPSProxy.sol";
import { UUPSProxiable } from "./upgradability/UUPSProxiable.sol";
import { IUUPSProxiable } from "./upgradability/IUUPSProxiable.sol";
import { IPoolV1 } from "./interfaces/IPool-V1.sol";
import { PoolV1 } from "./Pool-V1.sol";
import { IOps } from "./gelato/IOps.sol";
import { DataTypes } from "./libraries/DataTypes.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IPoolStrategyV1 } from "./interfaces/IPoolStrategy-V1.sol";
import { ERC20mintable } from "./interfaces/ERC20mintable.sol";
import { IPool } from "./aave/IPool.sol";


contract SuperPoolFactory is Initializable, UUPSProxiable {

  uint256 public nrPools;

  ISuperfluid host;
  IOps ops;
  address owner;
  address poolImpl;
  address poolInternalImpl;

  mapping(address => mapping(address => uint256)) public poolIdBySuperTokenStrategy;

  mapping(address => uint256) nrStrategiesPerSuperToken;

  mapping(address => mapping(uint256 => uint256)) public poolIdBySuperTokenAndId;

  mapping(uint256 => DataTypes.PoolInfo) public poolInfoById;

  /**
   * @notice initializer of the Pool Factory
   */
  function initialize(DataTypes.SuperPoolFactoryInitializer memory factoryInitializer) external initializer {
    
    host = factoryInitializer.host;
    ops = factoryInitializer.ops;
    poolImpl = factoryInitializer.poolImpl;
    poolInternalImpl = factoryInitializer.poolInternalImpl;
    owner = msg.sender;
  }

  function createSuperPool(
    DataTypes.CreatePoolInput memory poolInput
  ) external {
    DataTypes.PoolInfo memory existsPool = poolInfoById[poolIdBySuperTokenStrategy[poolInput.superToken][poolInput.poolStrategy]];
    require(existsPool.pool == address(0), "POOL_EXISTS");
    nrPools++;
    nrStrategiesPerSuperToken[poolInput.superToken] = nrStrategiesPerSuperToken[poolInput.superToken] + 1;

    uint256 poolNrBysuperToken = nrStrategiesPerSuperToken[poolInput.superToken];


    ISuperToken superToken = ISuperToken(poolInput.superToken);
    ERC20 token = ERC20(superToken.getUnderlyingToken());
    string memory tokenName = token.name();
    string memory symbol = token.symbol();
  
    UUPSProxy poolProxy = new UUPSProxy();
    poolProxy.initializeProxy(poolImpl);

    // initializer Pool
    DataTypes.PoolInitializer memory poolInit;
    poolInit = DataTypes.PoolInitializer({
      id: nrPools,
      name: string(abi.encodePacked("Super Pool ", tokenName)),
      symbol: string(abi.encodePacked("sp", symbol)),
      host: host,
      superToken: ISuperToken(poolInput.superToken),
      token: token,
      poolInternal: poolInternalImpl,
      poolStrategy: IPoolStrategyV1(poolInput.poolStrategy),
      ops: ops,
      owner: msg.sender
    });

    IPoolV1(address(poolProxy)).initialize(poolInit);

    // initialize strategy
    IPoolStrategyV1(poolInput.poolStrategy).initialize(
      ISuperToken(poolInput.superToken),
      poolInput._token,
      IPoolV1(address(poolProxy)),
      poolInput._aavePool,
      poolInput._aToken,
      poolInput._aaveToken
    );

    uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL | 
      SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP | 
      SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP | 
      SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

    host.registerAppByFactory(ISuperApp(address(poolProxy)), configWord);

    // initializer PoolInternal
    DataTypes.PoolInfo memory poolInfo = DataTypes.PoolInfo({
      id: nrPools,
      idPerSupertoken: poolNrBysuperToken,
      superToken: poolInput.superToken,
      strategy: poolInput.poolStrategy,
      pool: address(poolProxy), poolInternal: poolInternalImpl
    });
    poolInfoById[poolInfo.id] = poolInfo;
    poolIdBySuperTokenStrategy[poolInput.superToken][poolInput.poolStrategy] = poolInfo.id;
    poolIdBySuperTokenAndId[poolInput.superToken][poolNrBysuperToken] = poolInfo.id;
  }


  function changePoolImplementation(address newImpl, address superToken, address poolStrategy) external onlyOwner {
    uint256 poolId = poolIdBySuperTokenStrategy[superToken][poolStrategy];
    DataTypes.PoolInfo memory poolInfo = poolInfoById[poolId];
    IUUPSProxiable(poolInfo.pool).updateCode(newImpl);
    poolImpl = newImpl;
  }

  function changePoolInternalImplementation(address newImpl, address superToken, address poolStrategy) external onlyOwner {
    uint256 poolId = poolIdBySuperTokenStrategy[superToken][poolStrategy];
    DataTypes.PoolInfo memory poolInfo = poolInfoById[poolId];
    IUUPSProxiable(poolInfo.poolInternal).updateCode(newImpl);
    poolInternalImpl = newImpl;
  }

  function proxiableUUID() public pure override returns (bytes32) {
    return keccak256("org.super-pool.pool-factory.v2");
  }

  function updateCode(address newAddress) external override {
    require(msg.sender == owner, "only owner can update code");
    return _updateCodeAddress(newAddress);
  }

  function getRecordBySuperTokenAddress(address _superToken, address _poolStrategy) external view returns (DataTypes.PoolInfo memory poolInfo) {
    uint256 poolId = poolIdBySuperTokenStrategy[_superToken][_poolStrategy];
    poolInfo = poolInfoById[poolId];
  }

  function getVersion() external pure returns (uint256) {
    return 1.0;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "Only Owner");
    _;
  }
}
