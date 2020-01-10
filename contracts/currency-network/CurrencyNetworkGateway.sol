pragma solidity ^0.5.8;


import "./DebtTracking.sol";
import "./Onboarding.sol";
import "./CurrencyNetworkBasic.sol";
import "../escrow/Escrow.sol";

import "../lib/SafeMathLib.sol";
import "../lib/Address.sol";


/**
 * CurrencyNetworkGateway
 **/
contract CurrencyNetworkGateway {
    using SafeMathLib for uint256;

    address public gatedCurrencyNetwork;
    // Specifies the rate user gets his collateral exchanged in max. IOUs.
    // Denominations are GWEI to IOU.
    uint64 public exchangeRate;
    // Escrow contract where deposits are accounted.
    Escrow escrow;

    event ExchangeRateChanged(
        uint64 _changedExchangeRate
    );

    constructor(
        address _gatedCurrencyNetwork,
        uint64 _initialExchangeRate
    ) public {
        require(_gatedCurrencyNetwork != address(0), "CurrencyNetwork to gateway is 0x address");

        require(_initialExchangeRate > 0, "Exchange rate is 0");

        gatedCurrencyNetwork = _gatedCurrencyNetwork;
        exchangeRate = _initialExchangeRate;
        escrow = new Escrow();
    }

    function setExchangeRate(
        uint64 _exchangeRate
    )
        external
    {
        require(_exchangeRate > 0, "Exchange rate is 0");
        exchangeRate = _exchangeRate;
        emit ExchangeRateChanged(exchangeRate);
    }

    function openCollateralizedTrustline(
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

        CurrencyNetworkBasic currencyNetwork = CurrencyNetworkBasic(gatedCurrencyNetwork);
        currencyNetwork.updateTrustline(
            msg.sender,
            creditlineReceivedFromGateway,
            _creditlineGivenToGateway,
            0,
            0,
            false
        );
    }

    function closeCollateralizedTrustline()
        payable
        external 
    {
        CurrencyNetworkBasic currencyNetwork = CurrencyNetworkBasic(gatedCurrencyNetwork);
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

    function depositsOf(address payee) external view returns (uint256) {
        return escrow.depositsOf(payee);
    }

    function escrowAddress() external view returns (address) {
        return address(escrow);
    }
}
