// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolInternalV1 {
  function initialize() external;
  // #region  ============= =============  Pool Events (supplier interaction) ============= ============= //

  function _tokensReceived(address from, uint256 amount) external;

  function _redeemDeposit(address _supplier, uint256 redeemAmount) external;

  function _redeemFlowX(int96 _outFlowRate, address _supplier) external;

  function _redeemFlowStop(address _supplier) external;

  // #endregion User Interaction PoolEvents

  function _getSupplierBalance(address _supplier) external view returns (uint256 realtimeBalance);

  // #region =========== =============  PUBLIC VIEW FUNCTIONS  ============= ============= //

  function totalYieldEarnedSupplier(address _supplier, uint256 currentYieldSnapshot) external view returns (uint256 yieldSupplier);

  function getVersion() external pure returns (uint256);

  // #endregion =========== =============  PUBLIC VIEW FUNCTIONS  ============= ============= //

  function withdrawStep(address _receiver) external;

  function transferSTokens(address _sender, address _receiver, uint256 amount) external;
}
