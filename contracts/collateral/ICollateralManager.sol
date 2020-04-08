pragma solidity ^0.5.8;

/**
 * @title CollateralManager interface
 * @dev Interface contract for managing collateral of a `Gateway` contract.
 */
interface ICollateralManager {
    // address of collateralized currency network
    function currencyNetwork() external view returns (address);

    // total deposited collateral
    function totalCollateral() external view returns (uint256);

    // deposited collateral of payee
    function collateralOf(address payee) external view returns (uint256);

    /**
     * @dev Locks given msg.value as collateral.
     * @param payee The address to lock collateral for.
     */
    function lock(address payee) external payable;

    /**
     * @dev Unlocks the locked collateral.
     * @param payee The address to unlock collateral for.
     */
    function unlock(address payable payee) external;

    /**
     * @dev Add collateral to given address.
     * @param to The address to add collateral to.
     * @param collateral Amount of collateral to add.
     */
    function fill(address to, uint256 collateral) external;

    /**
     * @dev Draw collateral from given address.
     * @param from The address to draw collateral from.
     * @param collateral Amount of collateral to draw.
     */
    function draw(address from, uint256 collateral) external;

    /**
     * @dev Converts collateral to debt.
     * @param collateral Amount of collateral to convert.
     */
    function collateralToDebt(uint256 collateral) external view returns (uint256);

    /**
     * @dev Converts debt to collateral.
     * @param iou Amount of IOUs to convert.
     */
    function debtToCollateral(uint256 iou) external view returns (uint256);
}
