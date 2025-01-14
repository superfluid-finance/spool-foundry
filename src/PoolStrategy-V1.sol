// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPoolV1 } from "./interfaces/IPool-V1.sol";
import { IPoolStrategyV1 } from "./interfaces/IPoolStrategy-V1.sol";
import { IPool } from "./aave/IPool.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { UUPSProxiable } from "./upgradability/UUPSProxiable.sol";
import { ERC20Mintable } from "./interfaces/ERC20Mintable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 *
 * @title PoolStrategyV1
 * @dev This contract provides the allocation strategy to be followed by the pool
 *
 *      The addresse of the strategy will be passed to the pool factory by creation of the pool
 *      It can be created n-pools by superToken creating n-different strategies (aave, compounf, etc)
 *      By the pool initialization, the pool approve the strategy contract to operate the supertokens
 *
 *
 */
contract PoolStrategyV1 is Initializable, UUPSProxiable, IPoolStrategyV1 {
  address owner;

  ISuperToken public superToken;
  IPoolV1 public pool;
  /// Pool
  IPool public aavePool; //// aave Pool to deposit
  IERC20 public aToken; //// aToken received

  ///// IN PRODUCTION WE WILL ONLY REQUIRE the token a ERC20
  ///// NOW WE NEED TO SWAP BETWEEN SUPERFLUID and AAVe FAKE TOKEN
  ERC20Mintable public token; // SUPERFLUID Faketoken
  ERC20Mintable public aaveToken; // AAVE Fake token

  function initialize(
    ISuperToken _superToken,
    ERC20Mintable _token,
    IPoolV1 _pool,
    IPool _aavePool,
    IERC20 _aToken,
    ERC20Mintable _aaveToken
  ) external initializer {
    owner = msg.sender;
    superToken = _superToken;
    token = _token;
    pool = _pool;
    aavePool = _aavePool;
    aToken = _aToken;
    aaveToken = _aaveToken;

    aaveToken.approve(address(aavePool), type(uint256).max);
    token.approve(address(superToken), type(uint256).max);
  }

  function balanceOf() public view returns (uint256 balance) {
    balance = aToken.balanceOf(address(this)) * (10 ** 12);
  }

  // #region  ============= ============= ONLY POOL FUNCTIONS  ============= ============= //
  function withdraw(uint256 amount, address _supplier) external onlyPool {
    _withdraw(amount, _supplier);
  }

  function pushToStrategy(uint256 amountToDeposit) external onlyPool {
    if (amountToDeposit > 0) _deposit(amountToDeposit);
  }

  // #endregion  ============= ============= ONLY POOL FUNCTIONS  ============= ============= //

  // #region =========== ================ EMERGENCY =========== ================ //

  function withdrawEmergency() external onlyOwner {
    uint256 balance = aToken.balanceOf(address(this)) * (10 ** 12);
    _withdraw(balance, address(pool));
  }

  // #endregion  =========== ================ EMERGENCY =========== ================ //

  // #region  ============= ============= INTERNAL FUNCTIONS  ============= ============= //

  ////////////// IN PRODUCTIONM REMOVE the 10**12 FACTOR aNR THE MINTING
  function _deposit(uint256 amountToDeposit) internal {
    superToken.transferFrom(address(pool), address(this), uint256(amountToDeposit));

    superToken.downgrade(amountToDeposit);

    uint256 formattedAmountToDeposit = amountToDeposit / (10 ** 12);
    // We are not actually using the streamed in SuperToken's for
    // the Aave pool, so we mint fake tokens to simulate the
    // streamed in tokens
    aaveToken.mint(address(this), formattedAmountToDeposit);

    if (formattedAmountToDeposit > 0) {
      aavePool.deposit(address(aaveToken), formattedAmountToDeposit, address(this), 0);
    }
  }

  ////////////// IN PRODUCTIONM REMOVE the 10**12 FACTOR
  function _withdraw(uint256 amount, address _supplier) internal {
    if (amount / (10 ** 12) > 0) {
      aavePool.withdraw(address(aaveToken), amount / (10 ** 12), address(this));

      uint256 balanceToken = token.balanceOf(address(this));

      if (balanceToken < amount) {
        token.mint(address(this), amount - balanceToken);
      }

      superToken.upgrade(amount);

      IERC20(address(superToken)).transfer(_supplier, amount);
    }
  }

  // #endregion  ============= ============= INTERNAL FUNCTIONS  ============= ============= //

  // #region  ==================  Upgradeable settings  ==================

  function proxiableUUID() public pure override returns (bytes32) {
    return keccak256("org.super-pool.strategy.v2");
  }

  function updateCode(address newAddress) external override onlyOwner {
    return _updateCodeAddress(newAddress);
  }

  // #endregion  ==================  Upgradeable settings  ==================

  // #region   ==================  modifiers  ==================

  modifier onlyOwner() {
    require(msg.sender == owner, "Only Owner");
    _;
  }

  modifier onlyPool() {
    require(msg.sender == address(pool), "Only Pool Allowed");
    _;
  }

  //#endregion modifiers
}
