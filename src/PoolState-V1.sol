// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
  ISuperfluid,
  ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IConstantFlowAgreementV1 } from
  "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { IOps } from "./gelato/IOps.sol";
import { DataTypes } from "./libraries/DataTypes.sol";

contract PoolStateV1 {
  bool emergency = false;

  //ERC20

  mapping(address => uint256) public _balances;

  mapping(address => mapping(address => uint256)) public _allowances;

  uint256 public _totalSupply;

  string public _name;
  string public _symbol;

  // #region pool state

  address public owner;
  address public poolFactory;

  uint256 public lastPoolTimestamp;
  uint256 public lastExecution;
  //// TOKENS
  ISuperToken public superToken;
  IERC20 public token;

  //// SUPERFLUID

  //// GELATO
  IOps public ops;
  address payable public gelato;
  address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  bytes32 public balanceTreasuryTask;

  //// PARAMETERS

  uint256 public constant PRECISION = 1_000_000;

  uint256 public constant SUPERFLUID_DEPOSIT = 4 * 3600;
  uint256 public constant POOL_BUFFER = 3600; // buffer to keep in the pool (outstream 4hours deposit) + outstream partial deposits
  uint256 public constant MIN_OUTFLOW_ALLOWED = 24 * 3600; // 1 hour minimum flow == Buffer

  uint256 public constant DEPOSIT_TRIGGER_AMOUNT = 100 ether;
  uint256 public constant BALANCE_TRIGGER_TIME = 24 * 3600;

  uint256 public constant PROTOCOL_FEE = 3;

  address public poolStrategy;
  address public poolInternal;

  /// POOL STATE

  uint256 public poolId;
  uint256 public supplierId;

  mapping(address => DataTypes.Supplier) public suppliersByAddress;

  mapping(uint256 => DataTypes.Pool) public poolByTimestamp;

  ISuperfluid public host; // host
  IConstantFlowAgreementV1 public cfa; // the stored constant flow agreement class address
}
