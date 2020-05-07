pragma solidity ^0.5.8;


import "../collateral/ICollateralManager.sol";

import "../lib/SafeMathLib.sol";
import "../lib/Address.sol";

contract CollateralManager is ICollateralManager {
  using SafeMathLib for uint256;
  using Address for address payable;

  // address of collateralized currency network
  address private _currencyNetwork;
  // loan-to-value (LTV) ratio in percent: 1% => 1, 10% => 10, 100% => 100
  uint64 private _ltv;
  // price of 1 IOU in WEI of TLC
  uint256 private _iouInCollateral;

  bool private _isInitialized;

  uint256 private _totalCollateral;

  mapping(address => uint256) private _collateralOf;

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
    return _collateralOf[payee];
  }

  /**
   * @dev Locks given msg.value as collateral.
   * @param payee The address to lock collateral for.
   */
  function lock(address payee) external payable {
    _collateralOf[payee] = _collateralOf[payee].add(msg.value);

    _totalCollateral = _totalCollateral.add(msg.value);
  }

  /**
    * @dev Unlocks the locked collateral.
    * @param payee The address to unlock collateral for.
    */
  function unlock(address payable payee) external {
    _totalCollateral = _totalCollateral.sub(_collateralOf[payee]);
    payee.sendValue(_collateralOf[payee]);

    _collateralOf[payee] = 0;
  }

  /**
    * @dev Add collateral to given address.
    * @param to The address to add collateral to.
    * @param collateral Amount of collateral to add.
    */
  function fill(address to, uint256 collateral) external {
    _collateralOf[to] = _collateralOf[to].add(collateral);

    _collateralOf[address(this)] = _collateralOf[address(this)].sub(collateral);
  }

  /**
    * @dev Draw collateral from given address.
    * @param from The address to draw collateral from.
    * @param collateral Amount of collateral to draw.
    */
  function draw(address from, uint256 collateral) external {
    _collateralOf[from] = _collateralOf[from].sub(collateral);

    _collateralOf[address(this)] = _collateralOf[address(this)].add(collateral);
  }

  /**
    * @dev Conversion function to determine collateral in IOUs.
    * @param collateral Amount of collateral to convert.
    */
  function collateralToDebt(uint256 collateral) external view returns (uint256) {
    return collateral.mul(_ltv).div(100).div(_iouInCollateral);
  }

  /**
    * @dev Conversion function to determine IOUs in denomination of collateral.
    * @param iou Amount of IOUs to convert.
    */
  function debtToCollateral(uint256 iou) external view returns (uint256) {
    return iou.mul(_iouInCollateral).mul(100).div(_ltv);
  }
}