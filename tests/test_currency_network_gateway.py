#! pytest

import pytest
from eth_tester import EthereumTester
from tldeploy.core import (
    deploy_network,
    deploy_network_gateway,
    deploy_collateral_manager,
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
def collateral_manager_contract(web3):
    return deploy_collateral_manager(web3)

@pytest.fixture(scope="session")
def gateway_contract(web3):
    return deploy_network_gateway(web3)

@pytest.fixture(scope="session")
def currency_network_contract(web3, gateway_contract, collateral_manager_contract):
    return deploy_network(
        web3,
        gateway_contract=gateway_contract,
        collateral_manager_contract=collateral_manager_contract,
        **NETWORK_SETTING
    )

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
    currency_network_contract.functions.updateTrustline(
        gateway_contract.address,
        CL_GIVEN_TO_GW,
        COLLATERAL,
        0,
        0,
        False
    ).transact({ "from": accounts[0] })

    gateway_contract.functions.openCollateralizedTrustline(CL_GIVEN_TO_GW).transact({
        "from": accounts[1],
        "value": COLLATERAL
    })
    currency_network_contract.functions.updateTrustline(
        gateway_contract.address,
        CL_GIVEN_TO_GW,
        COLLATERAL,
        0,
        0,
        False
    ).transact({ "from": accounts[1] })
    return gateway_contract

def test_get_collateral_manager(
    currency_network_contract,
    collateral_manager_contract,
    gateway_contract
):
    assert(gateway_contract.functions.getCollateralManager().call() == collateral_manager_contract.address)

def test_get_currency_network(
    currency_network_contract,
    gateway_contract
):
    assert(gateway_contract.functions.getCurrencyNetwork().call() == currency_network_contract.address)

def test_gateway_global_authorized(
    currency_network_contract,
    gateway_contract
):
    assert(currency_network_contract.functions.globalAuthorized(gateway_contract.address).call())

def test_empty_collateral_of(gateway_contract, accounts):
    deposit = gateway_contract.functions.collateralOf(accounts[0]).call()
    assert(deposit == 0)

def test_open_collateralized_trustline(
    gateway_contract_with_opened_trustlines,
    currency_network_contract,
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
    assert(creditline_received_from_gateway == COLLATERAL)
    assert(gateway_contract_with_opened_trustlines.functions.totalCollateral().call() == COLLATERAL * 2)

def test_ltv(
    collateral_manager_contract,
): 
    ltv = collateral_manager_contract.functions.ltv().call()
    assert(ltv == 100)

def test_price(
    collateral_manager_contract,
): 
    price = collateral_manager_contract.functions.iouInCollateral().call()
    assert(price == 1)

def test_convert_to_collateral(
    currency_network_contract,
    collateral_manager_contract,
    gateway_contract_with_opened_trustlines,
): 
    converted = collateral_manager_contract.functions.debtToCollateral(10).call()
    assert(converted == 10)

def test_convert_to_debt(
    currency_network_contract,
    collateral_manager_contract,
    gateway_contract_with_opened_trustlines,
): 
    converted = collateral_manager_contract.functions.collateralToDebt(10).call()
    assert(converted == 10)

def test_pay_off(
    gateway_contract_with_opened_trustlines,
    currency_network_contract,
    accounts
):
    transfer_value = 10
    currency_network_contract.functions.transfer(
        transfer_value,
        0,
        [
            accounts[0],
            gateway_contract_with_opened_trustlines.address
        ],
        ""
    ).transact({ "from": accounts[0] })

    collateral_before_pay_off = gateway_contract_with_opened_trustlines.functions.collateralOf(accounts[0]).call()
    total_collateral_before_pay_off = gateway_contract_with_opened_trustlines.functions.totalCollateral().call()
    balance_before_pay_off = currency_network_contract.functions.balance(accounts[0], gateway_contract_with_opened_trustlines.address).call()

    gateway_contract_with_opened_trustlines.functions.payOff(transfer_value).transact({
        "from": accounts[0]
    })

    collateral_after_pay_off = gateway_contract_with_opened_trustlines.functions.collateralOf(accounts[0]).call()
    total_collateral_after_pay_off = gateway_contract_with_opened_trustlines.functions.totalCollateral().call()
    balance_after_pay_off = currency_network_contract.functions.balance(accounts[0], gateway_contract_with_opened_trustlines.address).call()

    assert(balance_before_pay_off == -transfer_value)
    assert(balance_after_pay_off == 0)

    assert(collateral_before_pay_off == COLLATERAL)
    assert(collateral_after_pay_off == COLLATERAL - transfer_value)

    assert(total_collateral_before_pay_off == COLLATERAL * 2)
    assert(total_collateral_after_pay_off == total_collateral_before_pay_off)


def test_claim_with_previous_draw(
    gateway_contract_with_opened_trustlines,
    currency_network_contract,
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
    gateway_contract_with_opened_trustlines.functions.payOff(transfer_value).transact({
        "from": accounts[0]
    })

    collateral_before_claim = gateway_contract_with_opened_trustlines.functions.collateralOf(accounts[1]).call()
    total_collateral_before_claim = gateway_contract_with_opened_trustlines.functions.totalCollateral().call()
    balance_before_claim = currency_network_contract.functions.balance(accounts[1], gateway_contract_with_opened_trustlines.address).call()

    gateway_contract_with_opened_trustlines.functions.claim(transfer_value).transact({
        "from": accounts[1]
    })

    collateral_after_claim = gateway_contract_with_opened_trustlines.functions.collateralOf(accounts[1]).call()
    total_collateral_after_claim = gateway_contract_with_opened_trustlines.functions.totalCollateral().call()
    balance_after_claim = currency_network_contract.functions.balance(accounts[1], gateway_contract_with_opened_trustlines.address).call()

    assert(balance_before_claim == transfer_value)
    assert(balance_after_claim == 0)

    assert(collateral_before_claim == COLLATERAL)
    assert(collateral_after_claim == COLLATERAL + transfer_value)

    assert(total_collateral_before_claim == COLLATERAL * 2)
    assert(total_collateral_after_claim == total_collateral_before_claim)


def test_close_collateralized_trustline(
    currency_network_contract,
    gateway_contract_with_opened_trustlines,
    accounts
):
    collateral_before_close = gateway_contract_with_opened_trustlines.functions.collateralOf(accounts[0]).call()
    total_collateral_before_close = gateway_contract_with_opened_trustlines.functions.totalCollateral().call()

    gateway_contract_with_opened_trustlines.functions.closeCollateralizedTrustline().transact({ "from": accounts[0] })

    collateral_after_close = gateway_contract_with_opened_trustlines.functions.collateralOf(accounts[0]).call()
    total_collateral_after_close = gateway_contract_with_opened_trustlines.functions.totalCollateral().call()

    assert(collateral_before_close == COLLATERAL)
    assert(collateral_after_close == 0)
    assert(total_collateral_before_close == COLLATERAL * 2)
    assert(total_collateral_after_close == COLLATERAL * 2 - collateral_before_close)
