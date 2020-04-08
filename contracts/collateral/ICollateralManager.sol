pragma solidity ^0.5.8;

/**
 * @title CollateralManager interface
 * @dev Interface contract for managing collateral of a `Gateway` contract.
 */
interface ICollateralManager {
    // address of collateralized currency network
    function currencyNetwork() public view returns (address);

    // loan-to-value (LTV) ratio in percent, 1% => 100, 0.1% => 10, 0.01% => 1
    function ltv() public view returns (uint64);

    // price of one 1 IOU in denomination of collateral
    function iouInCollateral() public view returns (uint256);

    // total deposited collateral
    function totalCollateral() public view returns (uint256);

    // deposited collateral of payee
    function collateralOf(address payee) public view returns (uint256);

    /**
     * @dev Locks given msg.value as collateral.
     * @param payee The address to lock collateral for.
     */
    function lock(address payee) public payable;

    /**
     * @dev Unlocks the locked collateral.
     * @param payee The address to unlock collateral for.
     */
    function unlock(address payable payee) public;

    /**
     * @dev Add collateral to given address.
     * @param to The address to add collateral to.
     * @param collateral Amount of collateral to add.
     */
    function fill(address to, uint256 collateral) public;

    /**
     * @dev Draw collateral from given address.
     * @param from The address to draw collateral from.
     * @param collateral Amount of collateral to draw.
     */
    function draw(address from, uint256 collateral) public;

    /**
     * @dev Conversion function to determine IOUs in denomination of collateral.
     * @param collateral Amount of collateral to convert.
     */
    function convertToIOU(uint256 collateral) public view returns (uint256);

    /**
     * @dev Conversion function to determine collateral in IOUs.
     * @param iou Amount of IOUs to convert.
     */
    function convertFromIOU(uint256 iou) public view returns (uint256);
}
