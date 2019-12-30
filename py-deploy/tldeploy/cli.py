import json

import click
import pkg_resources
from deploy_tools.cli import (
    auto_nonce_option,
    connect_to_json_rpc,
    gas_option,
    gas_price_option,
    get_nonce,
    jsonrpc_option,
    keystore_option,
    nonce_option,
    retrieve_private_key,
)
from deploy_tools.deploy import build_transaction_options
from eth_utils import is_checksum_address, to_checksum_address

import pendulum
from tldeploy.identity import (
    deploy_identity_implementation,
    deploy_identity_proxy_factory,
)

from .core import (
    deploy_exchange,
    deploy_network,
    deploy_networks,
    deploy_unw_eth,
    register_network,
)


def report_version():
    for dist in ["trustlines-contracts-deploy", "trustlines-contracts-bin"]:
        msg = "{} {}".format(dist, pkg_resources.get_distribution(dist).version)
        click.echo(msg)


def validate_date(ctx, param, value):
    if value is None:
        return None
    try:
        return pendulum.parse(value)
    except pendulum.parsing.exceptions.ParserError as e:
        raise click.BadParameter(
            f'The parameter "{value}" cannot be parsed as a date. (Try e.g. "2020-09-28", "2020-09-28T13:56")'
        ) from e


@click.group(invoke_without_command=True)
@click.option("--version", help="Prints the version of the software", is_flag=True)
@click.pass_context
def cli(ctx, version):
    """Commandline tool to deploy the Trustlines contracts"""
    if version:
        report_version()
    elif ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())
        ctx.exit()


currency_network_contract_name_option = click.option(
    "--currency-network-contract-name",
    help="name of the currency network contract to deploy (only use this for testing)",
    default="CurrencyNetwork",
    hidden=True,
)


@cli.command(short_help="Deploy a currency network contract.")
@click.argument("name", type=str)
@click.argument("symbol", type=str)
@click.option(
    "--decimals", help="Number of decimals of the network", default=4, show_default=True
)
@click.option(
    "--fee-rate",
    help="Imbalance fee rate of the currency network in percent",
    default=0.1,
    show_default=True,
)
@click.option(
    "--default-interest-rate",
    help="Set the default interest rate in percent",
    default=0.0,
    show_default=True,
)
@click.option(
    "--custom-interests/--no-custom-interests",
    help="Allow users to set custom interest rates. Default interest rate must be zero",
    default=False,
    show_default=True,
)
@click.option(
    "--prevent-mediator-interests",
    help="Disallow payments that would result in mediators paying interests",
    is_flag=True,
    default=False,
)
@click.option(
    "--exchange-contract",
    help="Address of the exchange contract to use. [Optional] [default: None]",
    default=None,
    type=str,
    metavar="ADDRESS",
    show_default=True,
)
@currency_network_contract_name_option
@click.option(
    "--expiration-time",
    help=(
        "Expiration time of the currency network after which it will be frozen (0 means disabled). "
        "Per default the network does not expire."
    ),
    required=False,
    type=int,
)
@click.option(
    "--expiration-date",
    help=(
        "Expiration date of the currency network after which it will be frozen "
        "(e.g. '2020-09-28', '2020-09-28T13:56'). "
        "Per default the network does not expire."
    ),
    type=str,
    required=False,
    metavar="DATE",
    callback=validate_date,
)
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
def currencynetwork(
    name: str,
    symbol: str,
    decimals: int,
    jsonrpc: str,
    fee_rate: float,
    default_interest_rate: float,
    custom_interests: bool,
    prevent_mediator_interests: bool,
    exchange_contract: str,
    currency_network_contract_name: str,
    expiration_time: int,
    expiration_date: pendulum.DateTime,
    gas: int,
    gas_price: int,
    nonce: int,
    auto_nonce: bool,
    keystore: str,
):
    """Deploy a currency network contract with custom settings and optionally connect it to an exchange contract"""
    if exchange_contract is not None and not is_checksum_address(exchange_contract):
        raise click.BadParameter("{} is not a valid address.".format(exchange_contract))

    if custom_interests and default_interest_rate != 0.0:
        raise click.BadParameter(
            "Custom interests can only be set without a"
            " default interest rate, but was {}%.".format(default_interest_rate)
        )

    if prevent_mediator_interests and not custom_interests:
        raise click.BadParameter(
            "Prevent mediator interests is not necessary if custom interests are disabled."
        )

    if expiration_date is not None and expiration_time is not None:
        raise click.BadParameter(
            f"Both --expiration-date and --expiration-times have been specified."
        )

    if expiration_date is None and expiration_time is None:
        expiration_time = 0

    if expiration_date is not None:
        expiration_time = int(expiration_date.timestamp())

    fee_divisor = 1 / fee_rate * 100 if fee_rate != 0 else 0
    if int(fee_divisor) != fee_divisor:
        raise click.BadParameter("This fee rate is not usable")
    fee_divisor = int(fee_divisor)

    default_interest_rate = default_interest_rate * 100
    if int(default_interest_rate) != default_interest_rate:
        raise click.BadParameter("This default interest rate is not usable")
    default_interest_rate = int(default_interest_rate)

    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )

    contract = deploy_network(
        web3,
        name,
        symbol,
        decimals,
        fee_divisor=fee_divisor,
        default_interest_rate=default_interest_rate,
        custom_interests=custom_interests,
        prevent_mediator_interests=prevent_mediator_interests,
        exchange_address=exchange_contract,
        currency_network_contract_name=currency_network_contract_name,
        expiration_time=expiration_time,
        transaction_options=transaction_options,
        private_key=private_key,
    )

    click.echo(
        "CurrencyNetwork(name={name}, symbol={symbol}, "
        "decimals={decimals}, fee_divisor={fee_divisor}, "
        "default_interest_rate={default_interest_rate}, "
        "custom_interests={custom_interests}, "
        "prevent_mediator_interests={prevent_mediator_interests}, "
        "exchange_address={exchange_address}): {address}".format(
            name=name,
            symbol=symbol,
            decimals=decimals,
            fee_divisor=fee_divisor,
            default_interest_rate=default_interest_rate,
            custom_interests=custom_interests,
            prevent_mediator_interests=prevent_mediator_interests,
            exchange_address=exchange_contract,
            address=to_checksum_address(contract.address),
        )
    )


@cli.command(short_help="Deploy an exchange contract.")
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
def exchange(
    jsonrpc: str, gas: int, gas_price: int, nonce: int, auto_nonce: bool, keystore: str
):
    """Deploy an exchange contract and a contract to wrap Ether into an ERC 20
  token.
    """
    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )
    exchange_contract = deploy_exchange(
        web3=web3, transaction_options=transaction_options, private_key=private_key
    )
    exchange_address = exchange_contract.address
    unw_eth_contract = deploy_unw_eth(
        web3=web3,
        transaction_options=transaction_options,
        private_key=private_key,
        exchange_address=exchange_address,
    )
    unw_eth_address = unw_eth_contract.address
    click.echo("Exchange: {}".format(to_checksum_address(exchange_address)))
    click.echo("Unwrapping ether: {}".format(to_checksum_address(unw_eth_address)))


@cli.command(short_help="Deploy an identity implementation contract.")
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
def identity_implementation(
    jsonrpc: str, gas: int, gas_price: int, nonce: int, auto_nonce: bool, keystore: str
):
    """Deploy an identity contract without initializing it. Can be used as the implementation for deployed
    identity proxies.
    """
    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )
    identity_implementation = deploy_identity_implementation(
        web3=web3, transaction_options=transaction_options, private_key=private_key
    )
    click.echo(
        "Identity implementation: {}".format(
            to_checksum_address(identity_implementation.address)
        )
    )


@cli.command(short_help="Deploy an identity proxy factory.")
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
def identity_proxy_factory(
    jsonrpc: str, gas: int, gas_price: int, nonce: int, auto_nonce: bool, keystore: str
):
    """Deploy an identity proxy factory, which can be used to create proxies for identity contracts.
    """

    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )
    identity_proxy_factory = deploy_identity_proxy_factory(
        web3=web3, transaction_options=transaction_options, private_key=private_key
    )
    click.echo(
        "Identity proxy factory: {}".format(
            to_checksum_address(identity_proxy_factory.address)
        )
    )


@cli.command(short_help="Deploy contracts for testing.")
@click.option(
    "--file",
    help="Output file for the addresses in json",
    default="",
    type=click.Path(dir_okay=False, writable=True),
)
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
@currency_network_contract_name_option
def test(
    jsonrpc: str,
    file: str,
    gas: int,
    gas_price: int,
    nonce: int,
    auto_nonce: bool,
    keystore: str,
    currency_network_contract_name: str,
):
    """Deploy three test currency network contracts connected to an exchange contract and an unwrapping ether contract.
    Also deploys an identity proxy factory and a identity implementation contract.
    This can be used for testing"""

    expiration_time = 4_102_444_800  # 01/01/2100

    network_settings = [
        {
            "name": "Cash",
            "symbol": "CASH",
            "decimals": 4,
            "fee_divisor": 1000,
            "default_interest_rate": 0,
            "custom_interests": True,
            "expiration_time": expiration_time,
        },
        {
            "name": "Work Hours",
            "symbol": "HOU",
            "decimals": 4,
            "fee_divisor": 0,
            "default_interest_rate": 1000,
            "custom_interests": False,
            "expiration_time": expiration_time,
        },
        {
            "name": "Beers",
            "symbol": "BEER",
            "decimals": 0,
            "fee_divisor": 0,
            "custom_interests": False,
            "expiration_time": expiration_time,
        },
    ]

    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )
    networks, exchange, unw_eth = deploy_networks(
        web3,
        network_settings,
        currency_network_contract_name=currency_network_contract_name,
    )
    identity_implementation = deploy_identity_implementation(
        web3=web3, transaction_options=transaction_options, private_key=private_key
    )
    identity_proxy_factory = deploy_identity_proxy_factory(
        web3=web3, transaction_options=transaction_options, private_key=private_key
    )
    addresses = dict()
    network_addresses = [network.address for network in networks]
    exchange_address = exchange.address
    unw_eth_address = unw_eth.address
    addresses["networks"] = network_addresses
    addresses["exchange"] = exchange_address
    addresses["unwEth"] = unw_eth_address
    addresses["identityImplementation"] = identity_implementation.address
    addresses["identityProxyFactory"] = identity_proxy_factory.address

    if file:
        with open(file, "w") as outfile:
            json.dump(addresses, outfile)

    click.echo("Exchange: {}".format(to_checksum_address(exchange_address)))
    click.echo("Unwrapping ether: {}".format(to_checksum_address(unw_eth_address)))
    click.echo(
        "Identity proxy factory: {}".format(
            to_checksum_address(identity_proxy_factory.address)
        )
    )
    click.echo(
        "Identity implementation: {}".format(
            to_checksum_address(identity_implementation.address)
        )
    )
    for settings, address in zip(network_settings, network_addresses):
        click.echo(
            "CurrencyNetwork({settings}) at {address}".format(
                settings=settings, address=to_checksum_address(address)
            )
        )


@cli.command(short_help="Deploy a set of currency network contract for issue 785.")
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
def deploy_networks(
    jsonrpc: str, gas: int, gas_price: int, nonce: int, auto_nonce: bool, keystore: str
):
    """Deploy a currency network contract with custom settings and optionally connect it to an exchange contract"""

    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )

    names = [
        "US Dollar",
        "Euro",
        "Japanese Yen",
        "Pound Sterling",
        "Australian Dollar",
        "Canadian Dollar",
        "Swiss Franc",
        "Chinese Yuan Renminbi",
        "Swedish Krona",
        "Mexican Peso",
        "New Zealand Dollar",
        "Singapore Dollar",
        "Hong Kong Dollar",
        "Norwegian Krone",
        "South Korean Won",
        "Turkish Lira",
        "Indian Rupee",
        "Russian Ruble",
        "Brazilian Real",
        "South African Rand",
        "Bitcoin",
        "Ether",
        "Dai",
        "Hours",
        "Beer",
        "Indonesian Rupiah",
        "Pakistani Rupee",
        "Bangladeshi Taka",
        "Nigerian Naira",
        "West African CFA Franc",
        "Central African CFA Franc",
        "Vietnamese Dong",
        "Philippine Peso",
        "Ethiopian Birr",
        "Egyptian Pound",
        "Turkish Lira",
        "Iranian Rial",
        "Thai Baht",
        "Congolese Franc",
        "Burmese Kyat",
        "Ukrainian Hryvnia",
        "Colombian Peso",
        "Argentine Peso",
        "Polish Zloty",
        "Tanzanian Shilling",
        "Solomon Islands Dollar",
    ]
    symbols = [
        "USD",
        "EUR",
        "JPY",
        "GBP",
        "AUD",
        "CAD",
        "CHF",
        "CNY",
        "SEK",
        "MXN",
        "NZD",
        "SGD",
        "HKD",
        "NOK",
        "KRW",
        "TRY",
        "INR",
        "RUB",
        "BRL",
        "ZAR",
        "BTC",
        "ETH",
        "DAI",
        "HOURS",
        "BEER",
        "IDR",
        "PKR",
        "BDT",
        "NGN",
        "XOF",
        "XAF",
        "VND",
        "PHP",
        "ETB",
        "EGP",
        "TRY",
        "IRR",
        "THB",
        "CDF",
        "MMK",
        "UAH",
        "COP",
        "ARS",
        "PLN",
        "TZS",
        "SBD",
    ]
    decimals = [
        8,
        8,
        6,
        8,
        8,
        8,
        8,
        7,
        7,
        7,
        8,
        8,
        7,
        7,
        5,
        7,
        6,
        6,
        8,
        7,
        8,
        8,
        8,
        8,
        1,
        4,
        6,
        6,
        6,
        5,
        5,
        4,
        6,
        7,
        7,
        7,
        4,
        7,
        5,
        5,
        7,
        5,
        6,
        8,
        5,
        7,
    ]
    custom_interests = [
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        False,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
        True,
    ]
    fee_divisors = [
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        0,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
    ]
    expiration_time = 1_613_347_200
    prevent_mediator_interests = False

    for i in range(46):
        contract = deploy_network(
            web3,
            names[i],
            symbols[i],
            decimals[i],
            fee_divisor=fee_divisors[i],
            default_interest_rate=0,
            custom_interests=custom_interests[i],
            prevent_mediator_interests=prevent_mediator_interests,
            currency_network_contract_name="CurrencyNetwork",
            expiration_time=expiration_time,
            transaction_options=transaction_options,
            private_key=private_key,
        )

        click.echo(
            "CurrencyNetwork(name={name}: {address}".format(
                name=names[i], address=to_checksum_address(contract.address)
            )
        )


@cli.command(short_help="Deploy a set of currency network contract for issue 785.")
@jsonrpc_option
@gas_option
@gas_price_option
@nonce_option
@auto_nonce_option
@keystore_option
def register_networks(
    jsonrpc: str, gas: int, gas_price: int, nonce: int, auto_nonce: bool, keystore: str
):
    """Deploy a currency network contract with custom settings and optionally connect it to an exchange contract"""

    web3 = connect_to_json_rpc(jsonrpc)
    private_key = retrieve_private_key(keystore)
    nonce = get_nonce(
        web3=web3, nonce=nonce, auto_nonce=auto_nonce, private_key=private_key
    )
    transaction_options = build_transaction_options(
        gas=gas, gas_price=gas_price, nonce=nonce
    )

    networks = [
        "0x12657128d7fa4291647eC3b0147E5fA6EebD388A",
        # "0xF2320a5371DA3CB967B9355597AA7adEc17E4220",
        # "0x18BDC736b23Ff7294BED9fa988a1443357C7B0ed",
        # "0x0A6f0C541Be542c098B7Ee03C9C634f20BCf8422",
        # "0x01564a4b7C327c84763D7fCf629B02584AE72973",
        # "0x8B2c0e43F69a8a25c94510cC85138260bb24e381",
        # "0x7A6049b3A96E7a6D68e6e6813a19594Ea336d080",
        # "0xB57C960Ee760cDa8184C9C9d9b7D0FeBE4557616",
        # "0x8306e229ea6Edf3aD2670681912CcC0C338f7963",
        # "0x70d4db4eC56b398D7cbA3666835490cb0e39f008",
        # "0x049D814ED22bEA4394aC2Ec48bace8A1e31BC376",
        # "0xc3790A6df080381ebf3eF9BeB35e6b70431bB420",
        # "0xa81DE4DA252E012a5e8b0Fe1FE91BB0a55Dc5f9d",
        # "0xB365694dB0961Fe81cA5e296c1250d24a4Ee627f",
        # "0x1A64Bd5e956DA93E912CB7eb9b00B8D2Bc9015F9",
        # "0x714dabD79B7962dA47c8fEA446064523CE0456fE",
        # "0xC0f1030d83AEEF1616deef060114E31B3A25De81",
        # "0x15933718E2e3478e756C13d516f7f4f4F749b3D6",
        # "0x77626459240b8105DeC70dC97D61441924f166Df",
        # "0x264B1775Ce5d2831608575974CfB9EB9F8F659f5",
        # "0xb2B3A0E958e3eEb333b734ABF34ACA2dB5b94B8F",
        # "0xA31fA3D8DaEBc1d7fb91a6F5F6805873dC958Ff2",
        # "0x603f22B1D3854b985E0a61Ce4c0349534a0e5673",
        # "0x5F74eD72158566c05328Eb815544461bD0b45116",
        # "0x7Ac3fC1C428df99D81d9b644106FF67c44A155aA",
        # "0xef5bC01da9AC8B32F78dC847D84454E48510Ef72",
        # "0x97668E07c122f7701b804A4eA6fd196F1e264423",
        # "0x57c4a2cCF2CC99f3dF7855465d1528C110Ff4F14",
        # "0xa809D5e740AA324FF94751836b1d7Aa6BA2de81E",
        # "0xF455c46823Cdb5A899217A0f085525874bA194A8",
        # "0xc8a0a3aA3A98F27198De126379386D8aA7D01950",
        # "0xCaa5B04e6E44EC3106EEBdAAd7D6C7bE9370Be32",
        # "0x2421A2ea7B24b5D26177B78afcf8F4B40255324d",
        # "0x2aB3f469D041aE68F45b3C255B7CB46370FfffF5",
        # "0x03FE2A6a589e33b7d3cD8208705092BE572A76d1",
        # "0x55997a8d56840508b1f78e9c0B2aA27d7D62430B",
        # "0xFe54Cbb23414467CcC052dACA1ecc908745D71Eb",
        # "0x4D4dd71A818D4F7d3349F936382ea70979123F81",
        # "0xCC6039e0681548002bcF39bf65d444beD65980B0",
        # "0x821b770a4b5D1228322B2A2Bb29354b5faabD29F",
        # "0x86D50E94e6Ba4B99C5c19439c13a07E5B7c231f9",
        # "0x6212C2783B2acCA8468b1befb19a4aAccb3c4970",
        # "0x4B1Ce992B04539786DF19dDC416490cd6595DB01",
        # "0x8588173E0322089Efe851b14d041aC15AC991C07",
        # "0xcb02a08a72Cb459fE41E987065fE1E2D7438E64E",
        # "0x0FbD56e384826246dC795C1A1951c781184F8faa",
    ]
    registry_address = "0x02c3cA67cF3310295195173cb654cfd61f4c849D"

    for i in range(1):
        tx_receipt = register_network(
            web3, registry_address, networks[i], transaction_options=transaction_options
        )

        click.echo(
            "CurrencyNetwork registered: {address}".format(
                address=to_checksum_address(networks[i])
            )
        )
