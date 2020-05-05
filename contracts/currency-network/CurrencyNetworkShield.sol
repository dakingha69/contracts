/**
Contract to enable the management of private fungible token (ERC-20) transactions using zk-SNARKs.
@Author Westlad, Chaitanya-Konda, iAmMichaelConnor
*/

pragma solidity ^0.5.8;

import "./CurrencyNetworkBasic.sol";
import "./CurrencyNetworkGateway.sol";
import "../MerkleTree.sol";
import "../verifier/VerifierInterface.sol";

contract CurrencyNetworkShield is MerkleTree {
    // ENUMS:
    enum TransactionTypes { Mint, Transfer, Burn, SimpleBatchTransfer }

    // EVENTS:
    // Observers may wish to listen for nullification of commitments:
    event Transfer(bytes32 nullifier1, bytes32 nullifier2);
    event SimpleBatchTransfer(bytes32 nullifier);
    event Burn(bytes32 nullifier);

    // Observers may wish to listen for zkSNARK-related changes:
    event VerifierChanged(address newVerifierContract);
    event VkChanged(TransactionTypes txType);
    event GatewayChanged(address newGatewayContract);

    // For testing only. This SHOULD be deleted before mainnet deployment:
    event GasUsed(
        uint256 byShieldContract,
        uint256 byVerifierContract,
        uint256 byCurrencyNetworkContract
    );

    // CONTRACT INSTANCES:
    VerifierInterface private verifier; // the verification smart contract
    CurrencyNetworkGateway private gateway; // the IOU token gateway contract

    // PRIVATE TRANSACTIONS' PUBLIC STATES:
    mapping(bytes32 => bytes32) public nullifiers; // store nullifiers of spent commitments
    mapping(bytes32 => bytes32) public roots; // holds each root we've calculated so that we can pull the one relevant to the prover
    bytes32 public latestRoot; // holds the index for the latest root so that the prover can provide it later and this contract can look up the relevant root

    // VERIFICATION KEY STORAGE:
    mapping(uint => uint256[]) public vks; // mapped to by an enum uint(TransactionTypes):

    bool private isInitialized;

    // FUNCTIONS:

    /**
     Initialize shield contract.
     */
    function init(
        address _verifier,
        address payable _gateway
    )
        public
    {
        require(!isInitialized, "Contract already initialized!");

        isInitialized = true;
        verifier = VerifierInterface(_verifier);
        gateway = CurrencyNetworkGateway(_gateway);
    }

    /**
    Change connected gateway contract
    TODO: Restrict access
     */
    function changeGateway(
        address payable _gateway
    )
        external
    {
        gateway = CurrencyNetworkGateway(_gateway);
        emit GatewayChanged(_gateway);
    }

    /**
    Get address of connected gateway contract
     */
    function getGateway() public view returns (address) {
        return address(gateway);
    }

    /**
    Get address of connected currency network
     */
    function getCurrencyNetwork() public view returns (address) {
        return CurrencyNetworkGateway(gateway).getCurrencyNetwork();
    }

    /**
    function to change the address of the underlying Verifier contract
    TODO: Restrict access
    */
    function changeVerifier(
        address _verifier
    )
        external
    {
        verifier = VerifierInterface(_verifier);
        emit VerifierChanged(_verifier);
    }

    /**
    returns the verifier-interface contract address that this shield contract is calling
    */
    function getVerifier() public view returns (address) {
        return address(verifier);
    }

    /**
    Stores verification keys (for the 'mint', 'transfer' and 'burn' computations).
    */
    function registerVerificationKey(
        uint256[] calldata _vk,
        TransactionTypes _txType
    )
        external
        // onlyOwner
        returns (bytes32)
    {
        // CAUTION: we do not prevent overwrites of vk's. Users must listen for the emitted event to detect updates to a vk.
        vks[uint(_txType)] = _vk;

        emit VkChanged(_txType);
    }

    /**
    Returns the registered verification key for given type.
     */
    function getVerificationKey(TransactionTypes _txType)
        external
        view
        returns (uint256[] memory)
    {
        return vks[uint(_txType)];
    }

    /**
    The mint function accepts IOU tokens from the specified currency network contract and creates the same amount as a commitment.
    */
    function mint(
        uint256[] calldata _proof,
        uint256[] calldata _inputs,
        uint64 _value,
        bytes32 _commitment,
        address[] calldata _path
    )
        external
    {
        // gas measurement:
        uint256 gasCheckpoint = gasleft();

        // Check that the publicInputHash equals the hash of the 'public inputs':
        bytes31 publicInputHash = bytes31(bytes32(_inputs[0]) << 8);
        bytes31 publicInputHashCheck = bytes31(sha256(abi.encodePacked(uint128(_value), _commitment)) << 8); // Note that we force the _value to be left-padded with zeros to fill 128-bits, so as to match the padding in the hash calculation performed within the zokrates proof.
        require(publicInputHashCheck == publicInputHash, "publicInputHash cannot be reconciled");

        // gas measurement:
        uint256 gasUsedByShieldContract = gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // verify the proof
        bool result = verifier.verify(_proof, _inputs, vks[uint(TransactionTypes.Mint)]);
        require(result, "The proof has not been verified by the contract");

        // gas measurement:
        uint256 gasUsedByVerifierContract = gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // update contract states
        latestRoot = insertLeaf(_commitment); // recalculate the root of the merkleTree as it's now different
        roots[latestRoot] = latestRoot; // and save the new root to the list of roots

        // gas measurement:
        gasUsedByShieldContract = gasUsedByShieldContract + gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // Finally, transfer the IOU tokens from the sender to gateway contract
        CurrencyNetworkBasic currencyNetwork = CurrencyNetworkBasic(
            CurrencyNetworkGateway(gateway).getCurrencyNetwork()
        );

        require(_path[_path.length - 1] == address(gateway), "Path end is not Gateway")
        require(_path[0] == msg.sender, "Path start is not msg.sender")
        currencyNetwork.transferFrom(_value, 0, _path, "");

        // gas measurement:
        uint256 gasUsedByCurrencyNetworkContract = gasCheckpoint - gasleft();

        emit GasUsed(
            gasUsedByShieldContract,
            gasUsedByVerifierContract,
            gasUsedByCurrencyNetworkContract
        );
    }

    /**
    The transfer function transfers a commitment to a new owner
    */
    function transfer(
        uint256[] calldata _proof,
        uint256[] calldata _inputs,
        bytes32 _root,
        bytes32 _nullifierC,
        bytes32 _nullifierD,
        bytes32 _commitmentE,
        bytes32 _commitmentF
    )
        external
    {
        // gas measurement:
        uint256[3] memory gasUsed; // array needed to stay below local stack limit
        gasUsed[0] = gasleft();

        // Check that the publicInputHash equals the hash of the 'public inputs':
        bytes31 publicInputHash = bytes31(bytes32(_inputs[0]) << 8);
        bytes31 publicInputHashCheck = bytes31(sha256(abi.encodePacked(_root, _nullifierC, _nullifierD, _commitmentE, _commitmentF)) << 8);
        require(publicInputHashCheck == publicInputHash, "publicInputHash cannot be reconciled");

        // gas measurement:
        gasUsed[1] = gasUsed[0] - gasleft();
        gasUsed[0] = gasleft();

        // verify the proof
        bool result = verifier.verify(_proof, _inputs, vks[uint(TransactionTypes.Transfer)]);
        require(result, "The proof has not been verified by the contract");

        // gas measurement:
        gasUsed[2] = gasUsed[0] - gasleft();
        gasUsed[0] = gasleft();

        // check inputs vs on-chain states
        require(roots[_root] == _root, "The input root has never been the root of the Merkle Tree");
        require(_nullifierC != _nullifierD, "The two input nullifiers must be different!");
        require(_commitmentE != _commitmentF, "The new commitments (commitmentE and commitmentF) must be different!");
        require(nullifiers[_nullifierC] == 0, "The commitment being spent (commitmentE) has already been nullified!");
        require(nullifiers[_nullifierD] == 0, "The commitment being spent (commitmentF) has already been nullified!");

        // update contract states
        nullifiers[_nullifierC] = _nullifierC; //remember we spent it
        nullifiers[_nullifierD] = _nullifierD; //remember we spent it

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = _commitmentE;
        leaves[1] = _commitmentF;

        latestRoot = insertLeaves(leaves); // recalculate the root of the merkleTree as it's now different
        roots[latestRoot] = latestRoot; // and save the new root to the list of roots

        emit Transfer(_nullifierC, _nullifierD);

        // gas measurement:
        gasUsed[1] = gasUsed[1] + gasUsed[0] - gasleft();
        emit GasUsed(gasUsed[1], gasUsed[2], 0);
    }

    /**
    The transfer function transfers 20 commitments to new owners
    */
    function simpleBatchTransfer(
        uint256[] calldata _proof,
        uint256[] calldata _inputs,
        bytes32 _root,
        bytes32 _nullifier,
        bytes32[] calldata _commitments
    )
        external
    {
        // gas measurement:
        uint256 gasCheckpoint = gasleft();

        // Check that the publicInputHash equals the hash of the 'public inputs':
        bytes31 publicInputHash = bytes31(bytes32(_inputs[0]) << 8);
        bytes31 publicInputHashCheck = bytes31(sha256(abi.encodePacked(_root, _nullifier, _commitments)) << 8);
        require(publicInputHashCheck == publicInputHash, "publicInputHash cannot be reconciled");

        // gas measurement:
        uint256 gasUsedByShieldContract = gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // verify the proof
        bool result = verifier.verify(_proof, _inputs, vks[uint(TransactionTypes.SimpleBatchTransfer)]);
        require(result, "The proof has not been verified by the contract");

        // gas measurement:
        uint256 gasUsedByVerifierContract = gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // check inputs vs on-chain states
        require(roots[_root] == _root, "The input root has never been the root of the Merkle Tree");
        require(nullifiers[_nullifier] == 0, "The commitment being spent has already been nullified!");

        // update contract states
        nullifiers[_nullifier] = _nullifier; //remember we spent it

        latestRoot = insertLeaves(_commitments);
        roots[latestRoot] = latestRoot; //and save the new root to the list of roots

        emit SimpleBatchTransfer(_nullifier);

        // gas measurement:
        gasUsedByShieldContract = gasUsedByShieldContract + gasCheckpoint - gasleft();
        emit GasUsed(gasUsedByShieldContract, gasUsedByVerifierContract, 0);
    }

    function burn(
        uint256[] calldata _proof,
        uint256[] calldata _inputs,
        bytes32 _root,
        bytes32 _nullifier,
        uint64 _value,
        uint256 _payTo,
        address[] calldata _path
    )
        external
    {
        // gas measurement:
        uint256 gasCheckpoint = gasleft();

        // Check that the publicInputHash equals the hash of the 'public inputs':
        bytes31 publicInputHash = bytes31(bytes32(_inputs[0]) << 8);
        bytes31 publicInputHashCheck = bytes31(sha256(abi.encodePacked(_root, _nullifier, uint128(_value), _payTo)) << 8); // Note that although _payTo represents an address, we have declared it as a uint256. This is because we want it to be abi-encoded as a bytes32 (left-padded with zeros) so as to match the padding in the hash calculation performed within the zokrates proof. Similarly, we force the _value to be left-padded with zeros to fill 128-bits.
        require(publicInputHashCheck == publicInputHash, "publicInputHash cannot be reconciled");

        // gas measurement:
        uint256 gasUsedByShieldContract = gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // verify the proof
        bool result = verifier.verify(_proof, _inputs, vks[uint(TransactionTypes.Burn)]);
        require(result, "The proof has not been verified by the contract");

        // gas measurement:
        uint256 gasUsedByVerifierContract = gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        // check inputs vs on-chain states
        require(roots[_root] == _root, "The input root has never been the root of the Merkle Tree");
        require(nullifiers[_nullifier]==0, "The commitment being spent has already been nullified!");

        nullifiers[_nullifier] = _nullifier; // add the nullifier to the list of nullifiers

        // gas measurement:
        gasUsedByShieldContract = gasUsedByShieldContract + gasCheckpoint - gasleft();
        gasCheckpoint = gasleft();

        //Finally, transfer the IOU tokens from gateway to the payTO address
        CurrencyNetworkBasic currencyNetwork = CurrencyNetworkBasic(
            CurrencyNetworkGateway(gateway).getCurrencyNetwork()
        );
        address payToAddress = address(_payTo); // we passed _payTo as a uint256, to ensure the packing was correct within the sha256() above
        require(_path[_path.length - 1] == payToAddress, "Path end is not payTo")
        require(_path[0] == address(gateway), "Path start is not Gateway")
        currencyNetwork.transferFrom(_value, 0, _path, "");

        // gas measurement
        uint256 gasUsedByCurrencyNetworkContract = gasCheckpoint - gasleft();

        emit Burn(_nullifier);
        emit GasUsed(
            gasUsedByShieldContract,
            gasUsedByVerifierContract,
            gasUsedByCurrencyNetworkContract
        );
    }
}
