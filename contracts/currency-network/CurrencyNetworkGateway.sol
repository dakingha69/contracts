pragma solidity ^0.5.8;


import "./CurrencyNetworkBasic.sol";
import "../collateral/ICollateralManager.sol";

import "../lib/SafeMathLib.sol";
import "../lib/Address.sol";


/**
 * CurrencyNetworkGateway
 **/
contract CurrencyNetworkGateway {
    using SafeMathLib for uint256;
    using Address for address payable;

    bool private isInitialized;

    ICollateralManager collateralManager;
    CurrencyNetworkBasic currencyNetwork;

    function () external payable {}

    function init(
        address _currencyNetwork,
        address _collateralManager
    ) public {
        require(!isInitialized, "Already initialized");

        require(_currencyNetwork != address(0), "CurrencyNetwork to gate is 0x address");

        require(_collateralManager != address(0), "CollateralManager is 0x address");

        isInitialized = true;
        currencyNetwork = CurrencyNetworkBasic(_currencyNetwork);
        collateralManager = ICollateralManager(_collateralManager);
    }

    function getCurrencyNetwork() external view returns (address) {
        return address(currencyNetwork);
    }

    function getCollateralManager() external view returns (address) {
        return address(collateralManager);
    }

    function openCollateralizedTrustline(
        uint64 _creditlineGivenToGateway
    )
        external
        payable
    {
        // Lock msg.value in collateralManager
        collateralManager.lock.value(msg.value)(msg.sender);

        // Convert msg.value to IOU
        uint256 creditlineReceivedFromGateway = collateralManager.convertToIOU(msg.value);

        currencyNetwork.updateTrustline(
            msg.sender,
            creditlineReceivedFromGateway,
            _creditlineGivenToGateway,
            0,
            0,
            false
        );
    }

    function claim(uint64 value)
        external
    {
        int balance = currencyNetwork.balance(
            msg.sender,
            address(this)
        );

        require(balance > 0, "No claimable IOUs");
        require(value > 0, "IOUs to claim is 0");
        require(balance >= value, "IOUs to claim exceed balance");

        uint256 claimInCollateral = collateralManager.convertFromIOU(uint256(value));
        collateralManager.fill(msg.sender, claimInCollateral);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = msg.sender;
        currencyNetwork.transfer(
            balance,
            0,
            path,
            ""
        );
    }

    function payOff(uint64 value)
        external
    {
        int balance = currencyNetwork.balance(
            address(this),
            msg.sender
        );

        require(balance > 0, "No payable IOUs");
        require(value > 0, "IOUs to pay is 0");
        require(balance >= value, "IOUs to pay exceed balance");

        uint256 payOffInCollateral = collateralManager.convertFromIOU(uint256(value));
        collateralManager.draw(msg.sender, payOffInCollateral);

        address[] memory path = new address[](2);
        path[0] = msg.sender;
        path[1] = address(this);
        currencyNetwork.transferFrom(
            value,
            0,
            path,
            ""
        );
    }

    function closeCollateralizedTrustline()
        external
    {
        collateralManager.unlock(msg.sender);

        currencyNetwork.closeTrustline(msg.sender);
    }

    function collateralOf(address payee) external view returns (uint256) {
        return collateralManager.collateralOf(payee);
    }

    function totalCollateral() external view returns (uint256) {
        return collateralManager.totalCollateral();
    }
}
