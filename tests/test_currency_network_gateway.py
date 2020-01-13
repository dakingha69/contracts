#! pytest

import pytest
from eth_tester import EthereumTester
from tldeploy.core import (
    deploy_network,
    deploy_network_gateway
)
import eth_tester.exceptions

from .conftest import EXTRA_DATA, EXPIRATION_TIME, MAX_UINT_64, CurrencyNetworkAdapter

MAX_CREDITLINE = MAX_UINT_64

COLLATERAL = 100
CL_GIVEN_TO_GW = 50

NETWORK_SETTING = {
    "name": "TestCoin",
    "symbol": "T",
    "decimals": 0,
    "fee_divisor": 0,
    "default_interest_rate": 0,
    "custom_interests": False,
    "currency_network_contract_name": "TestCurrencyNetwork",
    "expiration_time": EXPIRATION_TIME,
}

@pytest.fixture(scope="session")
def gateway_contract_and_escrow_address(web3):
    return deploy_network_gateway(web3)

@pytest.fixture(scope="session")
def gateway_contract(gateway_contract_and_escrow_address):
    return gateway_contract_and_escrow_address[0]

@pytest.fixture(scope="session")
def escrow_address(gateway_contract_and_escrow_address):
    return gateway_contract_and_escrow_address[1]

@pytest.fixture(scope="session")
def currency_network_contract(web3, gateway_contract):
    return deploy_network(web3, gateway_contract=gateway_contract, **NETWORK_SETTING)

@pytest.fixture(scope="session")
def gateway_contract_with_opened_trustlines(
    gateway_contract,
    currency_network_contract,
    accounts
):
    gateway_contract.functions.openCollateralizedTrustline(CL_GIVEN_TO_GW).transact({
        "from": accounts[0],
        "value": COLLATERAL
    })
    exchange_rate = gateway_contract.functions.exchangeRate().call()
    currency_network_contract.functions.updateTrustline(
        gateway_contract.address,
        CL_GIVEN_TO_GW,
        exchange_rate * COLLATERAL,
        0,
        0,
        False
    ).transact({ "from": accounts[0] })

    gateway_contract.functions.openCollateralizedTrustline(CL_GIVEN_TO_GW).transact({
        "from": accounts[1],
        "value": COLLATERAL
    })
    exchange_rate = gateway_contract.functions.exchangeRate().call()
    currency_network_contract.functions.updateTrustline(
        gateway_contract.address,
        CL_GIVEN_TO_GW,
        exchange_rate * COLLATERAL,
        0,
        0,
        False
    ).transact({ "from": accounts[1] })
    return gateway_contract

@pytest.fixture(scope="session")
def exchange_rate(gateway_contract):
    return gateway_contract.functions.exchangeRate().call()

def test_escrow_address(gateway_contract, escrow_address):
    assert(gateway_contract.functions.escrowAddress().call() == escrow_address)

def test_gated_currency_network_address(
    currency_network_contract,
    gateway_contract
):
    assert(gateway_contract.functions.gatedCurrencyNetworkAddress().call() == currency_network_contract.address)

def test_default_exchange_rate(exchange_rate):
    assert(exchange_rate == 1)

def test_gateway_global_authorized(
    currency_network_contract,
    gateway_contract
):
    assert(currency_network_contract.functions.globalAuthorized(gateway_contract.address).call())

def test_set_exchange_rate(gateway_contract):
    gateway_contract.functions.setExchangeRate(2).transact()

    exchange_rate = gateway_contract.functions.exchangeRate().call()
    assert(exchange_rate == 2)

def test_empty_deposits_of(gateway_contract, accounts):
    deposit = gateway_contract.functions.depositsOf(accounts[0]).call()
    assert(deposit == 0)

def test_open_collateralized_trustline(
    gateway_contract_with_opened_trustlines,
    escrow_address,
    currency_network_contract,
    exchange_rate,
    accounts
):
    creditline_given_to_gateway = currency_network_contract.functions.creditline(
        accounts[0],
        gateway_contract_with_opened_trustlines.address
    ).call()
    creditline_received_from_gateway = currency_network_contract.functions.creditline(
        gateway_contract_with_opened_trustlines.address,
        accounts[0]
    ).call()
    
    assert(creditline_given_to_gateway == CL_GIVEN_TO_GW)
    assert(creditline_received_from_gateway == exchange_rate * COLLATERAL)
    assert(gateway_contract_with_opened_trustlines.functions.totalDeposit().call() == COLLATERAL * 2)

def test_close_collateralized_trustline_positive_balance(
    gateway_contract_with_opened_trustlines,
    escrow_address,
    currency_network_contract,
    exchange_rate,
    accounts
):
    transfer_value = 10
    currency_network_contract.functions.transfer(
        transfer_value,
        0,
        [accounts[0], gateway_contract_with_opened_trustlines.address],
        ""
    ).transact({ "from": accounts[0] })

    deposit_before_close = gateway_contract_with_opened_trustlines.functions.depositsOf(accounts[0]).call()
    total_deposit_before_close = gateway_contract_with_opened_trustlines.functions.totalDeposit().call()

    gateway_contract_with_opened_trustlines.functions.closeCollateralizedTrustline().transact({
        "from": accounts[0]
    })

    deposit_after_close = gateway_contract_with_opened_trustlines.functions.depositsOf(accounts[0]).call()
    total_deposit_after_close = gateway_contract_with_opened_trustlines.functions.totalDeposit().call()
    creditline_after_close = currency_network_contract.functions.creditline(accounts[0], gateway_contract_with_opened_trustlines.address).call()

    assert(deposit_before_close == COLLATERAL)
    assert(deposit_after_close == 0)
    assert(total_deposit_before_close == COLLATERAL * 2)
    assert(total_deposit_after_close == COLLATERAL * 2 - (deposit_before_close - transfer_value / exchange_rate))
    assert(creditline_after_close == 0)

def test_close_collateralized_trustline_negative_balance(
    gateway_contract_with_opened_trustlines,
    escrow_address,
    currency_network_contract,
    exchange_rate,
    accounts
):
    transfer_value = 10
    currency_network_contract.functions.transfer(
        transfer_value,
        0,
        [
            accounts[0],
            gateway_contract_with_opened_trustlines.address,
            accounts[1]
        ],
        ""
    ).transact({ "from": accounts[0] })

    deposit_before_close = gateway_contract_with_opened_trustlines.functions.depositsOf(accounts[1]).call()
    total_deposit_before_close = gateway_contract_with_opened_trustlines.functions.totalDeposit().call()

    gateway_contract_with_opened_trustlines.functions.closeCollateralizedTrustline().transact({
        "from": accounts[1]
    })

    deposit_after_close = gateway_contract_with_opened_trustlines.functions.depositsOf(accounts[1]).call()
    total_deposit_after_close = gateway_contract_with_opened_trustlines.functions.totalDeposit().call()
    creditline_after_close = currency_network_contract.functions.creditline(accounts[1], gateway_contract_with_opened_trustlines.address).call()

    assert(deposit_before_close == COLLATERAL)
    assert(deposit_after_close == 0)
    assert(total_deposit_before_close == COLLATERAL * 2)
    assert(total_deposit_after_close == COLLATERAL * 2 - (deposit_before_close - transfer_value / exchange_rate))
    assert(creditline_after_close == 0)
