// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { DataTypes } from "../libraries/DataTypes.sol";

interface ISuperPoolFactory {
  // #region ===================== Supplier interaction Pool Events  ===========================

  function createSuperPool(DataTypes.CreatePoolInput memory poolInput) external returns (address poolAddress);
}
