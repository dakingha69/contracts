pragma solidity ^0.5.8;


import "../collateral/ICollateralManager.sol";

import "../lib/SafeMathLib.sol";
import "../lib/Address.sol";

contract CollateralManager is ICollateralManager {
  using SafeMathLib for uint256;
  using Address for address payable;

  // address of collateralized currency network
  address private _currencyNetwork;
  // loan-to-value (LTV) ratio in percent, 1% => 1
  uint64 private _ltv;
  // price of one 1 IOU in denomination of collateral
  uint256 private _iouInCollateral;

  bool private _isInitialized;

  uint256 private _totalCollateral;

  mapping(address => uint256) private _collaterals;

  /**
   * @dev Initializes the contract.
   */
  function init(
    address currencyNetwork,
    uint64 ltv,
    uint256 iouInCollateral
  ) external {
    require(!_isInitialized, "CollateralManager is already initialized");
    _isInitialized = true;
    _currencyNetwork = currencyNetwork;
    _ltv = ltv;
    _iouInCollateral = iouInCollateral;
    _totalCollateral = 0;
  }

  function currencyNetwork() external view returns (address) {
    return _currencyNetwork;
  }

  function ltv() external view returns (uint64) {
    return _ltv;
  }

  function iouInCollateral() external view returns (uint256) {
    return _iouInCollateral;
  }

  function totalCollateral() external view returns (uint256) {
    return _totalCollateral;
  }

  function collateralOf(address payee) external view returns (uint256) {
    return _collaterals[payee];
  }

  /**
   * @dev Locks given msg.value as collateral.
   * @param payee The address to lock collateral for.
   */
  function lock(address payee) external payable {
    _collaterals[payee] = _collaterals[payee].add(msg.value);

    _totalCollateral = _totalCollateral + msg.value;
  }

  /**
    * @dev Unlocks the locked collateral.
    * @param payee The address to unlock collateral for.
    */
  function unlock(address payable payee) external {
    _collaterals[payee] = 0;

    payee.sendValue(_collaterals[payee]);

    _totalCollateral = _totalCollateral.sub(_collaterals[payee]);
  }

  /**
    * @dev Add collateral to given address.
    * @param to The address to add collateral to.
    * @param collateral Amount of collateral to add.
    */
  function fill(address to, uint256 collateral) external {
    _collaterals[address(this)] = _collaterals[address(this)].sub(collateral);

    _collaterals[to] = _collaterals[to].add(collateral);
  }

  /**
    * @dev Draw collateral from given address.
    * @param from The address to draw collateral from.
    * @param collateral Amount of collateral to draw.
    */
  function draw(address from, uint256 collateral) external {
    _collaterals[from] = _collaterals[from].sub(collateral);

    _collaterals[address(this)] = _collaterals[from].add(collateral);
  }

  /**
    * @dev Conversion function to determine IOUs in denomination of collateral.
    * @param collateral Amount of collateral to convert.
    */
  function collateralToDebt(uint256 collateral) external view returns (uint256) {
    return collateral.mul(_ltv).div(100).div(_iouInCollateral);
  }

  /**
    * @dev Conversion function to determine collateral in IOUs.
    * @param iou Amount of IOUs to convert.
    */
  function debtToCollateral(uint256 iou) external view returns (uint256) {
    return iou.mul(_iouInCollateral).div(_ltv).div(100);
  }
}