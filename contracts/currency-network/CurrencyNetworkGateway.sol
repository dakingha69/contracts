pragma solidity ^0.5.8;


import "./DebtTracking.sol";
import "./Onboarding.sol";
import "./CurrencyNetworkBasic.sol";
import "../escrow/Escrow.sol";

import "../lib/math/SafeMath.sol";
import "../lib/Address.sol";


/**
 * CurrencyNetworkGateway
 **/
contract CurrencyNetworkGateway {
    // Specifies the rate user gets his collateral exchanged in max. IOUs.
    // Denominations are GWEI to IOU.
    // For simplicity and testing we set a rate of 1.
    uint64 constant EXCHANGE_RATE = 1;

    using SafeMath for uint256;

    uint64 private exchangeRate;
    Escrow escrow;

    constructor() public {
        // Currently setting a hard coded exchange rate.
        // Should be dynamic though, with Oracles for example.
        exchangeRate = EXCHANGE_RATE;
        escrow = new Escrow();
    }

    function openCollateralizedTrustline(
        address _currencyNetwork,
        uint64 _creditlineGivenToGateway
    )
        payable 
        external
    {
        // Deposit msg.value in escrow
        escrow.deposit.value(msg.value)(msg.sender);

        // TODO: Handle casting properly
        uint64 collateral = uint64(msg.value);
        uint64 creditlineReceivedFromGateway = exchangeRate * collateral;

        CurrencyNetworkBasic currencyNetwork = CurrencyNetworkBasic(_currencyNetwork);
        currencyNetwork.updateTrustline(
            msg.sender,
            creditlineReceivedFromGateway,
            _creditlineGivenToGateway,
            0,
            0,
            false
        );
    }

    function closeCollateralizedTrustline(
        address _currencyNetwork
    )
        payable
        external 
    {
        CurrencyNetworkBasic currencyNetwork = CurrencyNetworkBasic(_currencyNetwork);
        int balance = currencyNetwork.balance(
            address(this),
            msg.sender
        );
        uint64 deposit = uint64(escrow.depositsOf(msg.sender));

        if (balance > 0) {
            uint64 delta = deposit - uint64(balance) / exchangeRate;
            escrow.transferDeposit(msg.sender, address(uint160(address(this))), uint256(delta));
        } else if (balance < 0) {
            uint64 delta = deposit - uint64(balance * -1) / exchangeRate;
            escrow.transferDeposit(address(uint160(address(this))), msg.sender, uint256(delta));
        }
        escrow.withdrawWithGas(msg.sender);
    }

    function depositsOf(address payee) public view returns (uint256) {
        return escrow.depositsOf(payee);
    }
}
