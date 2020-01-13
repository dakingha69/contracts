pragma solidity ^0.5.8;


import "./CurrencyNetworkBasic.sol";
import "../escrow/Escrow.sol";

import "../lib/SafeMathLib.sol";
import "../lib/Address.sol";


/**
 * CurrencyNetworkGateway
 **/
contract CurrencyNetworkGateway {
    using SafeMathLib for uint256;
    using Address for address payable;

    bool private isInitialized;
    // Specifies the rate user gets his collateral exchanged in max. IOUs.
    // Denominations are GWEI to IOU.
    uint64 public exchangeRate;
    // Escrow contract where deposits are accounted.
    Escrow escrow;
    CurrencyNetworkBasic gatedCurrencyNetwork;

    event ExchangeRateChanged(
        uint64 _changedExchangeRate
    );

    constructor() public {
        escrow = new Escrow();
    }

    function () external payable {}

    function init(
        address _gatedCurrencyNetwork,
        uint64 _initialExchangeRate
    ) public {
        require(!isInitialized, "Already initialized");

        require(_gatedCurrencyNetwork != address(0), "CurrencyNetwork to gateway is 0x address");

        require(_initialExchangeRate > 0, "Exchange rate is 0");

        isInitialized = true;
        gatedCurrencyNetwork = CurrencyNetworkBasic(_gatedCurrencyNetwork);
        exchangeRate = _initialExchangeRate;
    }

    function gatedCurrencyNetworkAddress() external view returns (address) {
        return address(gatedCurrencyNetwork);
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

        gatedCurrencyNetwork.updateTrustline(
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
        int balance = gatedCurrencyNetwork.balance(
            address(this),
            msg.sender
        );
        address[] memory path = new address[](2);

        if (balance > 0) {
            uint64 partialDeposit = uint64(balance) / exchangeRate;
            escrow.withdrawPartial(
                msg.sender,
                partialDeposit
            );
            path[0] = address(this);
            path[1] = msg.sender;
            gatedCurrencyNetwork.transfer(
                uint64(balance),
                0,
                path,
                ""
            );
        } else if (balance < 0) {
            uint64 partialDeposit = uint64(balance * -1) / exchangeRate;
            escrow.withdrawPartial(
                msg.sender,
                uint256(partialDeposit)
            );
            path[0] = msg.sender;
            path[1] = address(this);
            gatedCurrencyNetwork.transferFrom(
                uint64(balance * -1),
                0,
                path,
                ""
            );
        } else {
            escrow.withdrawWithGas(msg.sender);
        }
        gatedCurrencyNetwork.closeTrustline(msg.sender);
    }

    function depositsOf(address payee) external view returns (uint256) {
        return escrow.depositsOf(payee);
    }

    function totalDeposit() external view returns (uint256) {
        return escrow.totalDeposit();
    }

    function escrowAddress() external view returns (address) {
        return address(escrow);
    }
}
