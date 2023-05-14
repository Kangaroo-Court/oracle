// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// This contract allows assertions on any form of data to be made using the UMA Optimistic Oracle V3 and stores the
// proposed value so that it may be retrieved on chain. The dataId is intended to be an arbitrary value that uniquely
// identifies a specific piece of information in the consuming contract and is replaceable. Similarly, any data
// structure can be used to replace the asserted data.
contract LivelinessAsserter {
    using SafeERC20 for IERC20;
    IERC20 public immutable defaultCurrency;
    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 7200;
    bytes32 public immutable defaultIdentifier;
    mapping(bytes32 => bool) public lastAttestationStatus;
    mapping(bytes32 => uint256) assertionExpirations;
    struct DataAssertion {
        bytes32 dataId; // The dataId that was asserted.
        address token;
        uint256 timestamp;
        bool dead; // This could be an arbitrary data type.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    
    mapping(bytes32 => DataAssertion) public assertionsData;

    event DataAsserted(
        bytes32 indexed dataId,
        address token,
        bool dead,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    event DataAssertionResolved(
        bytes32 indexed dataId,
        address token,
        bool dead,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    constructor(address _defaultCurrency, address _optimisticOracleV3) {
        defaultCurrency = IERC20(_defaultCurrency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
    }
    function setExpiration(bytes32 dataId,uint256 expiration) public{
        assertionExpirations[dataId]=expiration;
    }
    // Asserts data for a specific dataId on behalf of an asserter address.
    // Data can be asserted many times with the same combination of arguments, resulting in unique assertionIds. This is
    // because the block.timestamp is included in the claim. The consumer contract must store the returned assertionId
    // identifiers to able to get the information using getData.
    function assertDataFor(
        bytes32 dataId,
        address t,
        bool status,
        address asserter
    ) public returns (bytes32 assertionId) {
        if (assertionExpirations[dataId] > 0) {
            require(
                block.timestamp < assertionExpirations[dataId],
                "attestations have expired"
            );
        }
        uint256 _status;
        asserter = asserter == address(0) ? msg.sender : asserter;
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);
        _status = status ? 1 : 0;
        // The claim we want to assert is the first argument of assertTruth. It must contain all of the relevant
        // details so that anyone may verify the claim without having to read any further information on chain. As a
        // result, the claim must include both the data id and data, as well as a set of instructions that allow anyone
        // to verify the information in publicly available sources.
        // See the UMIP corresponding to the defaultIdentifier used in the OptimisticOracleV3 "ASSERT_TRUTH" for more
        // information on how to construct the claim.
        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Data asserted: 0x", // in the example data is type bytes32 so we add the hex prefix 0x.
                ClaimData.toUtf8BytesAddress(t),
                "the status is",
                ClaimData.toUtf8BytesUint(_status),
                " for dataId: 0x",
                ClaimData.toUtf8Bytes(dataId),
                " and asserter: 0x",
                ClaimData.toUtf8BytesAddress(asserter),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );
        assertionsData[assertionId] = DataAssertion(
            dataId,
            t,
            block.timestamp,
            status,
            asserter,
            false
        );
        ///emit DataAsserted(dataId, data, asserter, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionsData[assertionId].resolved = true;
            DataAssertion memory dataAssertion = assertionsData[assertionId];
            lastAttestationStatus[dataAssertion.dataId] = assertionsData[
                assertionId
            ].dead;

            // Else delete the data assertion if it was false to save gas.
        } else delete assertionsData[assertionId];
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public {}

    function resolved(bytes32 id) public view returns (bool) {
        return lastAttestationStatus[id];
    }
}
