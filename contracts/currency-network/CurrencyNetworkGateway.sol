pragma solidity ^0.5.8;


import "./CurrencyNetworkBasic.sol";
import "../Escrow.sol";

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
    CurrencyNetworkBasic currencyNetwork;

    event ExchangeRateChanged(
        uint64 _changedExchangeRate
    );

    constructor() public {
        escrow = new Escrow();
    }

    function () external payable {}

    function init(
        address _currencyNetwork,
        uint64 _initialExchangeRate
    ) public {
        require(!isInitialized, "Already initialized");

        require(_currencyNetwork != address(0), "CurrencyNetwork to gateway is 0x address");

        require(_initialExchangeRate > 0, "Exchange rate is 0");

        isInitialized = true;
        currencyNetwork = CurrencyNetworkBasic(_currencyNetwork);
        exchangeRate = _initialExchangeRate;
    }

    function getCurrencyNetwork() external view returns (address) {
        return address(currencyNetwork);
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
        external
        payable
    {
        // Deposit msg.value in escrow
        escrow.deposit.value(msg.value)(msg.sender);

        // TODO: Handle casting properly
        uint64 collateral = uint64(msg.value);
        // TODO: top up existing creditline
        uint64 creditlineReceivedFromGateway = exchangeRate * collateral;

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
        external
        payable
    {
        int balance = currencyNetwork.balance(
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
            currencyNetwork.transfer(
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
            currencyNetwork.transferFrom(
                uint64(balance * -1),
                0,
                path,
                ""
            );
        } else {
            escrow.withdrawWithGas(msg.sender);
        }
        currencyNetwork.closeTrustline(msg.sender);
    }

    function depositsOf(address payee) external view returns (uint256) {
        return escrow.depositsOf(payee);
    }

    function totalDeposit() external view returns (uint256) {
        return escrow.totalDeposit();
    }

    function getEscrow() external view returns (address) {
        return address(escrow);
    }
}
