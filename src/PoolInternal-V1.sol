// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IOps } from "./gelato/IOps.sol";
import { LibDataTypes } from "./gelato/LibDataTypes.sol";
import { IPoolStrategyV1 } from "./interfaces/IPoolStrategy-V1.sol";
import { IPoolV1 } from "./interfaces/IPool-V1.sol";
import { DataTypes } from "./libraries/DataTypes.sol";
import { Events } from "./libraries/Events.sol";
import { PoolStateV1 } from "./PoolState-V1.sol";

contract PoolInternalV1 is PoolStateV1 {
  using SuperTokenV1Library for ISuperToken;
  
  error NOT_ENOUGH_BALANCE();
  error NOT_ENOUGH_BALANCE_WITH_OUTFLOW();

  // #region =========== =============  Pool Events (supplier interaction) ============= ============= //

  function _tokensReceived(address _supplier, uint256 amount) external {
    ///// suppler config updated && pool
    _updateSupplierDeposit(_supplier, amount, 0);
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];
    poolByTimestamp[block.timestamp] = _balanceTreasury(pool);
  }

  function _redeemDeposit(address _supplier, uint256 redeemAmount) external {
    uint256 balance = _getSupplierBalance(_supplier) / PRECISION;
    require(balance >= redeemAmount, "NOT_ENOUGH_BALANCE");

    _updateSupplierDeposit(_supplier, 0, redeemAmount);
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];
    poolByTimestamp[block.timestamp] = _withdrawTreasury(_supplier, _supplier, redeemAmount, pool);
  }

  function _redeemFlow(address _supplier, int96 _outFlowRate) external {
    _updateSupplierFlow(_supplier, 0, _outFlowRate, new bytes(0));
  }

  function _redeemFlowStop(address _supplier) public {
    _updateSupplierFlow(_supplier, 0, 0, new bytes(0));
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];
    poolByTimestamp[block.timestamp] = _balanceTreasury(pool);
  }

  function _closeAccount(address _supplier) external {
    DataTypes.Supplier memory supplier = suppliersByAddress[_supplier];
    if (supplier.outStream.flow > 0) {
      _redeemFlowStop(_supplier);
    } else if (supplier.inStream > 0) {
      superToken.deleteFlow(_supplier, address(this));
      _updateSupplierFlow(_supplier, 0, 0, new bytes(0));
    }

    uint256 balance = _getSupplierBalance(_supplier) / PRECISION;
    _updateSupplierDeposit(_supplier, 0, balance);
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];
    poolByTimestamp[block.timestamp] = _withdrawTreasury(_supplier, _supplier, balance, pool);
  }

  // #endregion User Interaction PoolEvents

  // #region =========== =============  PUBLIC VIEW FUNCTIONS  ============= ============= //

  function getVersion() external pure returns (uint256) {
    return 1.0;
  }

  // #endregion =========== =============  PUBLIC VIEW FUNCTIONS  ============= ============= //

  // #region =========== =============  POOL UPDATE ============= ============= //

  /**
   *
   * Pool Update
   *
   *
   */
  function _poolUpdate() public {
    DataTypes.Pool memory lastPool = poolByTimestamp[lastPoolTimestamp];
    uint256 periodSpan = block.timestamp - lastPool.timestamp;

    if (periodSpan <= 0) {
      return;
    }

    poolId++;
    DataTypes.Pool memory pool = DataTypes.Pool(
      poolId,
      block.timestamp,
      supplierId, // nrSuppliers
      lastPool.deposit,
      uint96(lastPool.inFlowRate) * PRECISION * periodSpan + lastPool.depositFromInFlowRate, // depositFromInFlowRate
      uint96(lastPool.outFlowRate) * PRECISION * periodSpan + lastPool.depositFromOutFlowRate, // depositFromOutFlowRate
      lastPool.inFlowRate,
      lastPool.outFlowRate,
      lastPool.outFlowBuffer,
      DataTypes.Yield(0, 0, 0, 0, 0, 0, 0)
    );

    pool.yieldObject.yieldSnapshot = IPoolStrategyV1(poolStrategy).balanceOf();
    uint256 periodAccrued = pool.yieldObject.yieldSnapshot - lastPool.yieldObject.yieldSnapshot;
    pool.yieldObject.protocolYield = lastPool.yieldObject.protocolYield + ((periodAccrued * PROTOCOL_FEE) / 100);
    pool.yieldObject.yieldAccrued = (periodAccrued * (100 - PROTOCOL_FEE)) / 100;
    pool.yieldObject.totalYield = lastPool.yieldObject.totalYield + pool.yieldObject.yieldAccrued;
    (pool.yieldObject.yieldTokenIndex, pool.yieldObject.yieldInFlowRateIndex, pool.yieldObject.yieldOutFlowRateIndex) = _calculateIndexes(pool.yieldObject.yieldAccrued, lastPool);
    pool.yieldObject.yieldTokenIndex += lastPool.yieldObject.yieldTokenIndex;
    pool.yieldObject.yieldInFlowRateIndex += lastPool.yieldObject.yieldInFlowRateIndex;
    pool.yieldObject.yieldOutFlowRateIndex += lastPool.yieldObject.yieldOutFlowRateIndex;

    poolByTimestamp[block.timestamp] = pool;
    lastPoolTimestamp = block.timestamp;
  }

  // #endregion POOL UPDATE

  // #region =========== =============  Internal Supplier Update ============= ============= //

  function _getSupplier(address _supplier) internal returns (DataTypes.Supplier memory supplier) {
    supplier = suppliersByAddress[_supplier];

    if (supplier.timestamp == 0) {
      supplier.supplier = _supplier;
      supplier.timestamp = block.timestamp;
      supplierId = supplierId + 1;
      supplier.id = supplierId;
      poolByTimestamp[block.timestamp].nrSuppliers++;
      suppliersByAddress[_supplier] = supplier;
    }
  }

  function _getSupplierBalance(address _supplier) public view returns (uint256 realtimeBalance) {
    DataTypes.Supplier memory supplier = suppliersByAddress[_supplier];
    uint256 yieldSupplier = totalYieldEarnedSupplier(_supplier, IPoolStrategyV1(poolStrategy).balanceOf());
    int96 netFlow = supplier.inStream - supplier.outStream.flow;
    uint96 netFlowAbs = netFlow >= 0 ? uint96(netFlow) : uint96(-netFlow);
    uint256 flowProduct = netFlowAbs * (block.timestamp - supplier.timestamp) * PRECISION;
    return netFlow >= 0 ? yieldSupplier + supplier.deposit + flowProduct : yieldSupplier + supplier.deposit - flowProduct;
  }

  /**
   * @notice Update the supplier to the current state (happens after interaction)
   * @param _supplier supplier's address
   *
   * @dev  it calculates the yield, adds the inflow inbetween if any and update the values
   *       when outflow (receidurationving flow) there is no update on the deposit as is diccounted
   *
   */
  function _supplierUpdateCurrentState(address _supplier) internal {
    DataTypes.Supplier memory supplier = _getSupplier(_supplier);

    if (supplier.timestamp >= block.timestamp) {
      return;
    }

    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];
    uint256 yieldSupplier = totalYieldEarnedSupplier(_supplier, IPoolStrategyV1(poolStrategy).balanceOf());
    uint256 flow;
    uint256 multiplier = PRECISION * (block.timestamp - supplier.timestamp);

      if (supplier.inStream > 0) {
        flow = uint96(supplier.inStream) * multiplier;
        pool.depositFromInFlowRate -= flow;
        pool.deposit += flow;
        supplier.deposit += flow;
      } else if (supplier.outStream.flow > 0) {
        flow = uint96(supplier.outStream.flow) * multiplier;
        pool.depositFromOutFlowRate -= flow;
        pool.deposit -= flow;
        supplier.deposit -= flow;
      }

      pool.deposit += yieldSupplier;
      supplier.deposit += yieldSupplier;
      supplier.timestamp = block.timestamp;
      poolByTimestamp[block.timestamp] = pool;
      suppliersByAddress[_supplier] = supplier;
  }

  /**
   * @notice Update fo the pool when a supplier deposit via erc777 send i¡or withdraw via redeemDeposit()
   *
   * @param _supplier supplier's address
   * @param inDeposit supplier's depositing amount or
   * @param outDeposit supplier's withdrawal amount
   *
   * @dev  it update the pool, update the suppleir record and apply the changes to the pool
   *
   */
  function _updateSupplierDeposit(address _supplier, uint256 inDeposit, uint256 outDeposit) internal {
    _poolUpdate();

    _supplierUpdateCurrentState(_supplier);

    DataTypes.Supplier memory supplier = _getSupplier(_supplier);

    if (supplier.outStream.flow > 0) {
      cancelTask(supplier.outStream.cancelWithdrawId);
      uint96 flow = uint96(supplier.outStream.flow);
      if (outDeposit > 0) {
        uint256 balance = _getSupplierBalance(_supplier) / PRECISION - outDeposit;
        uint256 outFlowBuffer = POOL_BUFFER * flow;
        uint256 initialWithdraw = SUPERFLUID_DEPOSIT * flow;
        uint256 streamDuration =  (balance - (outFlowBuffer + initialWithdraw)) / flow;

        require(streamDuration >= 24 * 3600, "NOT_ENOUGH_BALANCE_WITH_OUTFLOW");

        supplier.outStream.streamDuration = streamDuration;
        supplier.outStream.streamInit = block.timestamp;
        supplier.outStream.cancelWithdrawId = _createCloseStreamTask(_supplier, streamDuration);

      } else if (inDeposit > 0) {
        uint256 currentEndTime = supplier.outStream.streamInit + supplier.outStream.streamDuration;
        uint256 addTime = inDeposit / flow;
        supplier.outStream.streamDuration = supplier.outStream.streamDuration + addTime;
        supplier.outStream.cancelWithdrawId = _createCloseStreamTask(_supplier, currentEndTime + addTime - block.timestamp);
      }
    }

    supplier.deposit = supplier.deposit + inDeposit * PRECISION - outDeposit * PRECISION;
    suppliersByAddress[_supplier] = supplier;
    poolByTimestamp[block.timestamp].deposit = poolByTimestamp[block.timestamp].deposit + inDeposit * PRECISION - outDeposit * PRECISION;
  }

  /**
   * @notice Update fo the pool when an stream event happened
   *
   * @param _supplier supplier's address
   * @param inFlow supplier's new Inflow
   * @param outFlow supplier's new Outflow
   * @param _ctx of the super app callback
   *
   * @dev  this method acts upon the changes in the streams:
   *       1) user send a stream ----> create the stream record nad update pool
   *       2) user update sending stream ----> update the stream record in the pool
   *       3) user stop sending stream ----> update the stream record
   *       4) user redeem flow (receiving stream):
   *              a) create stream record (_outstreamhaschanged() and creatOutStream())
   *              b) ensure Supertokens are available to cover the step in the pool, if not _withdrawTreasury()
   *                 will withdraw tokens from the strategy pool (in example is aave)
   *              c) create the Gelato task that will transfer after every step to ensure enough supertokens are available
   *              d) create the Superfluid stream from the superpool to the user
   *       5) user updates a receiving flow:
   *              a) update the stream record ---> if with the new flowrate there is no mminimal balance,
   *                 the stream will be stopped and the funds returned
   *              b,c,d) as case 4
   *       6) user stops redeeming flow --> update record and stop the superfluid stream
   *
   */
  function _updateSupplierFlow(address _supplier, int96 inFlow, int96 outFlow, bytes memory _ctx) public returns (bytes memory newCtx) {
    newCtx = _ctx;
    _poolUpdate();
    _supplierUpdateCurrentState(_supplier);

    DataTypes.Supplier memory supplier = suppliersByAddress[_supplier];
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];

    int96 currentNetFlow = supplier.inStream - supplier.outStream.flow;
    int96 newNetFlow = inFlow - outFlow;

    if (currentNetFlow < 0) {
      /// PREVIOUS FLOW NEGATIVE AND CURRENT FLOW POSITIVE

      if (newNetFlow >= 0) {
        pool.outFlowRate += currentNetFlow;

        pool.inFlowRate += newNetFlow;

        ///// refactor logic
        if (newNetFlow == 0) {
          superToken.deleteFlow(address(this), _supplier);
        } else {
          newCtx = superToken.deleteFlowWithCtx(address(this), _supplier, _ctx);
        }

        _cancelTask(supplier.outStream.cancelWithdrawId);
        uint256 oldOutFlowBuffer = POOL_BUFFER * uint96(-currentNetFlow);
        pool.outFlowBuffer -= oldOutFlowBuffer;
        supplier.outStream = DataTypes.OutStream(0, 0, 0, bytes32(0));
        pool = _balanceTreasury(pool);
      } else {
        pool.outFlowRate = pool.outFlowRate + currentNetFlow - newNetFlow;
        (pool, supplier) = _outStreamHasChanged(supplier, -newNetFlow, pool);
      }
    } else {
      /// PREVIOUS FLOW NOT EXISTENT OR POSITIVE AND CURRENT FLOW THE SAME
      if (newNetFlow >= 0) {
        pool.inFlowRate = pool.inFlowRate - currentNetFlow + inFlow;

        pool = _balanceTreasury(pool);
      } else {
        /// PREVIOUS FLOW NOT EXISTENT OR POSITIVE AND CURRENT FLOW NEGATIVE

        if (currentNetFlow > 0) {
          superToken.deleteFlow(_supplier, address(this));
        }

        pool.outFlowRate += -newNetFlow;
        pool.inFlowRate -= currentNetFlow;
        (pool, supplier) = _outStreamHasChanged(supplier, -newNetFlow, pool);
      }
    }

    supplier.inStream = inFlow;
    supplier.outStream.flow = outFlow;
    suppliersByAddress[_supplier] = supplier;
    poolByTimestamp[block.timestamp] = pool;
  }

  // #endregion

  // #region  ========== =============  TREASURY ============= ============= //

  function _createBalanceTreasuryTask() external returns (bytes32 taskId) {
    bytes memory resolverData = abi.encodeWithSelector(IPoolV1.checkerLastExecution.selector);

    bytes memory resolverArgs = abi.encode(address(this), resolverData);

    LibDataTypes.Module[] memory modules = new LibDataTypes.Module[](1);

    modules[0] = LibDataTypes.Module.RESOLVER;

    bytes[] memory args = new bytes[](1);

    args[0] = resolverArgs;

    LibDataTypes.ModuleData memory moduleData = LibDataTypes.ModuleData(modules, args);
    taskId = IOps(ops).createTask(address(this), abi.encodePacked(IPoolV1.balanceTreasury.selector), moduleData, ETH);
  }

  function _balanceTreasuryFromGelato() public {
    DataTypes.Pool memory pool = poolByTimestamp[lastPoolTimestamp];
    pool = _balanceTreasury(pool);
    poolByTimestamp[lastPoolTimestamp] = pool;
  }

  function _balanceTreasury(DataTypes.Pool memory currentPool) public returns (DataTypes.Pool memory) {
    lastExecution = block.timestamp;

    (int256 balance,,,) = superToken.realtimeBalanceOfNow(address(this));

    uint256 currentThreshold = currentPool.outFlowBuffer;

    int96 netFlow = currentPool.inFlowRate - currentPool.outFlowRate;
    if (netFlow < 0) {
      currentThreshold = currentThreshold + ((BALANCE_TRIGGER_TIME)) * uint96(-netFlow);
    }

    if (uint256(balance) > currentThreshold) {
      uint256 toDeposit = uint256(balance) - currentThreshold;

      IPoolStrategyV1(poolStrategy).pushToStrategy(toDeposit);
      currentPool.yieldObject.yieldSnapshot += toDeposit;
    } else if (currentThreshold > uint256(balance)) {
      uint256 amountToWithdraw = currentThreshold - uint256(balance);

      uint256 balanceAave = IPoolStrategyV1(poolStrategy).balanceOf();

      if (amountToWithdraw > balanceAave) {
        amountToWithdraw = balanceAave;
      }

      IPoolStrategyV1(poolStrategy).withdraw(amountToWithdraw, address(this));

      currentPool.yieldObject.yieldSnapshot -= amountToWithdraw;
    }
    return currentPool;
  }

  /**
   * @notice internal withdrawal dispatcher when tokens movments are required,
   * can be to a supplier or from the pool strategy to the superpol
   *
   * @param _supplier supplier's address
   * @param _receiver the reciever addrss (can be the pool contract or the suppleir)
   * @param withdrawAmount  amount to withdraw
   *
   * @dev  if (_suppleir == _reciever) means the tokens must e transfered to the supplier
   *       else if (_supplier != _receiver) the tokens are transferred to the superpool to ensure the out flows
   *
   */
  function _withdrawTreasury(address _supplier, address _receiver, uint256 withdrawAmount, DataTypes.Pool memory pool) internal returns (DataTypes.Pool memory) {
    lastExecution = block.timestamp;
    // DataTypes.Pool storage pool = poolByTimestamp[block.timestamp];

    uint256 currentThreshold = pool.outFlowBuffer;
    uint256 outFlowBuffer = 0;

    int96 netFlow = pool.inFlowRate - pool.outFlowRate;

    if (netFlow < 0) {
      outFlowBuffer = (BALANCE_TRIGGER_TIME) * uint96(-netFlow);
    }
    //// calculate if any remaining balance of supertokens is inthe pool (push to strategy not yet ran)
    uint256 poolAvailable = 0;

    if (superToken.balanceOf(address(this)) > (currentThreshold)) {
      poolAvailable = superToken.balanceOf(address(this)) - (currentThreshold);
    }

    //// if enough in the pool is available then not go to the pool strategy
    if (poolAvailable >= withdrawAmount + outFlowBuffer) {
      //// if the withdrawal is to supplier then we must transfer

      if (_supplier == _receiver) {
        IERC20(address(superToken)).transfer(_receiver, withdrawAmount);
      }

      if (poolAvailable > withdrawAmount + outFlowBuffer) {
        IPoolStrategyV1(poolStrategy).pushToStrategy(poolAvailable - (withdrawAmount + outFlowBuffer));

        pool.yieldObject.yieldSnapshot += poolAvailable - (withdrawAmount + outFlowBuffer);
      }

      //// in the case the withdraw receiver is the pool, we don0t have to do anything as there is enoguh balance
    } else {
      //// not enough balance then we must withdraw from gtrategy

      uint256 balance = IPoolStrategyV1(poolStrategy).balanceOf();

      uint256 fromStrategy = (withdrawAmount + outFlowBuffer) - poolAvailable;

      uint256 correction;
      if (fromStrategy > balance) {
        correction = fromStrategy - balance;

        if (balance > 0) {
          IPoolStrategyV1(poolStrategy).withdraw(balance, _receiver);

          pool.yieldObject.yieldSnapshot = pool.yieldObject.yieldSnapshot - balance;
        }

        if (_supplier == _receiver) {
          IERC20(address(superToken)).transfer(_receiver, correction);
        }
      } else {
        IPoolStrategyV1(poolStrategy).withdraw(fromStrategy, _receiver);

        pool.yieldObject.yieldSnapshot = pool.yieldObject.yieldSnapshot - fromStrategy;
        if (_supplier == _receiver) {
          IERC20(address(superToken)).transfer(_receiver, poolAvailable);
        }
      }
    }
    return pool;
  }

  // #endregion  ============= =============  TREASURY ============= ============= //

  // #region  ========== =============  Internal Stream Functions ============= ============= //

  /**
   * @notice internal call from updteSupplierFlow() when a redeemflow has been started or updated
   *
   * @param supplier supplier
   * @param newOutFlow supplier's new Outflow
   *
   * @dev  if the outflow does not exist, will be created, if does, will be updted
   */
  function _outStreamHasChanged(DataTypes.Supplier memory supplier, int96 newOutFlow, DataTypes.Pool memory pool) internal returns (DataTypes.Pool memory, DataTypes.Supplier memory) {
    uint256 userBalance = _getSupplierBalance(supplier.supplier) / PRECISION;

    uint256 outFlowBuffer = POOL_BUFFER * uint96(newOutFlow);

    uint256 initialWithdraw = SUPERFLUID_DEPOSIT * uint96(newOutFlow);
    uint256 streamDuration =  (userBalance - (outFlowBuffer + initialWithdraw)) / uint96(newOutFlow);

    if (supplier.outStream.flow == 0) {
      if (streamDuration < 24 * 3600) {
        revert("INSUFFICIENT_FUNDS");
      }

      pool.outFlowBuffer += outFlowBuffer;

      supplier.outStream.cancelWithdrawId = _createCloseStreamTask(supplier.supplier, streamDuration);

      supplier.outStream.streamInit = block.timestamp;

      pool = _withdrawTreasury(supplier.supplier, address(this), initialWithdraw, pool);

      supplier.outStream.streamDuration = streamDuration;

      superToken.createFlow(supplier.supplier, newOutFlow);

      // uint256 bal = superToken.balanceOf(address(this));
      //(int256 realBal, uint256 deposit,,) = superToken.realtimeBalanceOfNow(address(this));
    } else if (supplier.outStream.flow > 0 && supplier.outStream.flow != newOutFlow) {
      if (streamDuration < 24 * 3600) {
        revert("No sufficent funds");
      }
      _cancelTask(supplier.outStream.cancelWithdrawId);

      supplier.outStream.cancelWithdrawId = _createCloseStreamTask(supplier.supplier, streamDuration);
      supplier.outStream.streamDuration = streamDuration;
      supplier.outStream.streamInit = block.timestamp;

      if (supplier.outStream.flow > newOutFlow) {
        uint256 decreaseBuffer = POOL_BUFFER * uint96(supplier.outStream.flow - newOutFlow);

        pool.outFlowBuffer -= decreaseBuffer;
        pool = _balanceTreasury(pool);
      } else {
        uint256 increaseBuffer = POOL_BUFFER * uint96(newOutFlow - supplier.outStream.flow);
        pool.outFlowBuffer += increaseBuffer;
        uint256 oldInitialWithdraw = SUPERFLUID_DEPOSIT * uint96(supplier.outStream.flow);
        uint256 toWithDraw = increaseBuffer + initialWithdraw - oldInitialWithdraw;

        pool = _withdrawTreasury(supplier.supplier, address(this), toWithDraw, pool);
        //To DO REBALANCE
      }

      superToken.updateFlow(supplier.supplier, newOutFlow);
    }
    return (pool, supplier);
  }

  function _createCloseStreamTask(address _supplier, uint256 streamDuration) internal returns (bytes32 taskId) {
    bytes memory timeArgs = abi.encode(uint128(block.timestamp + streamDuration), streamDuration);

    bytes memory execData = abi.encodeWithSelector(IPoolV1.taskClose.selector, _supplier);

    LibDataTypes.Module[] memory modules = new LibDataTypes.Module[](2);

    modules[0] = LibDataTypes.Module.TIME;
    modules[1] = LibDataTypes.Module.SINGLE_EXEC;

    bytes[] memory args = new bytes[](1);

    args[0] = timeArgs;

    LibDataTypes.ModuleData memory moduleData = LibDataTypes.ModuleData(modules, args);

    taskId = IOps(ops).createTask(address(this), execData, moduleData, ETH);
  }

  /**
   * @notice internal call from updteSupplierFlow() when a redeemflow has been started or updated
   *
   * @param _supplier supplier's address
   *
   * @dev  the outstream will be cancel when the withdrawset gelato task is in the last step
   *       or when the redeem flow has been updated and there is no wnough minimal balance
   */
  function closeStreamFlow(address _supplier) external {
    _poolUpdate();
    _supplierUpdateCurrentState(_supplier);

    DataTypes.Supplier memory supplier = suppliersByAddress[_supplier];
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];

    //// TODO clsoe stream transfer yield accrued while dscending
    uint256 userBalance = _getSupplierBalance(_supplier) / PRECISION;

    uint256 oldOutFlowBuffer = POOL_BUFFER * uint96(supplier.outStream.flow);
    pool.outFlowBuffer -= oldOutFlowBuffer;
    pool.outFlowRate -= supplier.outStream.flow;
    pool.deposit -= supplier.deposit;

    supplier.deposit = 0;
    supplier.outStream = DataTypes.OutStream(0, 0, 0, bytes32(0));

    superToken.deleteFlow(address(this), _supplier);
    suppliersByAddress[_supplier] = supplier;
    pool = _withdrawTreasury(_supplier, _supplier, userBalance, pool);
    poolByTimestamp[block.timestamp] = pool;
  }

  // #endregion  ============= =============  Internal Stream Functions ============= ============= //

  // #region  ============= =============  ERC20  ============= ============= //
  function transferSPTokens(address _sender, address _receiver, uint256 amount) external {
    _poolUpdate();
    _supplierUpdateCurrentState(_sender);
    DataTypes.Supplier memory sender = _getSupplier(_sender);
    _supplierUpdateCurrentState(_receiver);
    DataTypes.Supplier memory receiver = _getSupplier(_receiver);

    // sender.deposit = sender.deposit.sub(amount.mul(PRECISION));
    // receiver.deposit = receiver.deposit.add(amount.mul(PRECISION));
    suppliersByAddress[_sender].deposit = sender.deposit - amount * PRECISION;
    suppliersByAddress[_receiver].deposit = receiver.deposit + amount * PRECISION;
    DataTypes.Pool memory pool = poolByTimestamp[block.timestamp];
    pool = _balanceTreasury(pool);
    poolByTimestamp[block.timestamp] = pool;
  }

  // #endregion  ============= =============  ERC20  ============= ============= //

  // #region ====================  Gelato Cancel  ====================

  function cancelTask(bytes32 _taskId) public {
    IOps(ops).cancelTask(_taskId);
  }

  function _cancelTask(bytes32 taskId) internal {
    IOps(ops).cancelTask(taskId);
  }

  // #endregion ====================  Gelato Cancel ====================

  //// TO BE REFACTOR SO FAR REDUNDANT

  /**
   * @notice Calculate the yield earned by the suplier
   * @param _supplier supplier's address
   * @return yieldSupplier uint256 yield erarnd
   *
   * @dev  it calculates the yield between the last pool update and the last supplier interaction
   *       it uses two indexes (per deosit and flow), the yield is (timespan)(diff index's)
   */
  function _calculateYieldSupplier(address _supplier) public view returns (uint256 yieldSupplier) {
    DataTypes.Supplier memory supplier = suppliersByAddress[_supplier];

    DataTypes.Pool memory lastPool = poolByTimestamp[lastPoolTimestamp];
    DataTypes.Pool memory supplierPool = poolByTimestamp[supplier.timestamp];

    ///// Yield from deposit

    uint256 yieldFromDeposit = (supplier.deposit * (lastPool.yieldObject.yieldTokenIndex - supplierPool.yieldObject.yieldTokenIndex)) / PRECISION;
    uint256 yieldFromFlow = 0;
    uint256 yieldFromOutFlow = 0;

    yieldSupplier = yieldFromDeposit;
    if (supplier.inStream > 0) {
      ///// Yield from flow
      yieldFromFlow = uint96(supplier.inStream) * (lastPool.yieldObject.yieldInFlowRateIndex - supplierPool.yieldObject.yieldInFlowRateIndex);
    }

    if (supplier.outStream.flow > 0) {
      ///// Yield from flow
      yieldFromOutFlow = uint96(supplier.outStream.flow) * (lastPool.yieldObject.yieldOutFlowRateIndex - supplierPool.yieldObject.yieldOutFlowRateIndex);
    }

    yieldSupplier = yieldSupplier + yieldFromFlow - yieldFromOutFlow;
  }

  function _calculateIndexes(uint256 yieldPeriod, DataTypes.Pool memory lastPool) public view returns (uint256 periodYieldTokenIndex, uint256 periodYieldInFlowRateIndex, uint256 periodYieldOutFlowRateIndex) {
    uint256 periodSpan = block.timestamp - lastPool.timestamp;

    uint256 dollarSecondsDeposit = lastPool.deposit * periodSpan;
    uint256 dollarSecondsInFlow = ((uint96(lastPool.inFlowRate) * (periodSpan ** 2)) * PRECISION) / 2 + lastPool.depositFromInFlowRate * periodSpan;
    uint256 dollarSecondsOutFlow = ((uint96(lastPool.outFlowRate) * (periodSpan ** 2)) * PRECISION) / 2 + lastPool.depositFromOutFlowRate * periodSpan;
    uint256 totalAreaPeriod = dollarSecondsDeposit + dollarSecondsInFlow - dollarSecondsOutFlow;

    /// we ultiply by PRECISION

    if (totalAreaPeriod != 0 && yieldPeriod != 0) {
      uint256 inFlowContribution = (dollarSecondsInFlow * PRECISION);
      uint256 outFlowContribution = (dollarSecondsOutFlow * PRECISION);
      uint256 depositContribution = (dollarSecondsDeposit * PRECISION * PRECISION);
      if (lastPool.deposit != 0) {
        periodYieldTokenIndex = (depositContribution * yieldPeriod) / (lastPool.deposit * totalAreaPeriod);
      }
      if (lastPool.inFlowRate != 0) {
        periodYieldInFlowRateIndex = (inFlowContribution * yieldPeriod) / (uint96(lastPool.inFlowRate) * totalAreaPeriod);
      }
      if (lastPool.outFlowRate != 0) {
        periodYieldOutFlowRateIndex = (outFlowContribution * yieldPeriod) / (uint96(lastPool.outFlowRate) * totalAreaPeriod);
      }
    }
  }

  function totalYieldEarnedSupplier(address _supplier, uint256 currentYieldSnapshot) public view returns (uint256 yieldSupplier) {
    uint256 yieldTilllastPool = _calculateYieldSupplier(_supplier);
    DataTypes.Pool memory lastPool = poolByTimestamp[lastPoolTimestamp];

    uint256 yieldAccruedSincelastPool = 0;
    if (currentYieldSnapshot > lastPool.yieldObject.yieldSnapshot) {
      yieldAccruedSincelastPool = currentYieldSnapshot - lastPool.yieldObject.yieldSnapshot;
    }
    yieldAccruedSincelastPool = (yieldAccruedSincelastPool * (100 - PROTOCOL_FEE)) / 100;
    (uint256 yieldTokenIndex, uint256 yieldInFlowRateIndex, uint256 yieldOutFlowRateIndex) = _calculateIndexes(yieldAccruedSincelastPool, lastPool);

    DataTypes.Supplier memory supplier = suppliersByAddress[_supplier];

    uint256 yieldDeposit = yieldTokenIndex * supplier.deposit / PRECISION;
    uint256 yieldInFlow = uint96(supplier.inStream) * yieldInFlowRateIndex;
    uint256 yieldOutFlow = uint96(supplier.outStream.flow) * yieldOutFlowRateIndex;

    yieldSupplier = yieldTilllastPool + yieldDeposit + yieldInFlow - yieldOutFlow;
  }
}
