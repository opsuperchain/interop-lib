// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {IL2ToL2CrossDomainMessenger, Identifier} from "../interfaces/IL2ToL2CrossDomainMessenger.sol";
import {ICrossL2Inbox} from "../interfaces/ICrossL2Inbox.sol";
import {PredeployAddresses} from "../libraries/PredeployAddresses.sol";
import {console} from "forge-std/console.sol";
import {CommonBase} from "forge-std/Base.sol";
import {VmSafe} from "forge-std/Vm.sol";

/**
 * @title Relayer
 * @notice Abstract contract that simulates cross-chain message relaying between L2 chains
 * @dev This contract is designed for testing cross-chain messaging in a local environment
 *      by creating forks of two L2 chains and relaying messages between them.
 *      It captures SentMessage events using vm.recordLogs() and vm.getRecordedLogs() and relays them to their destination chains.
 */
abstract contract Relayer is CommonBase {
    /// @notice Reference to the L2ToL2CrossDomainMessenger contract
    IL2ToL2CrossDomainMessenger messenger =
        IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    /// @notice Fork ID for the first chain
    uint256 chainA;

    /// @notice Fork ID for the second chain
    uint256 chainB;

    /// @notice Mapping from chain ID to fork ID
    /// @dev Used to select the correct fork when relaying messages
    mapping(uint256 => uint256) public forkIdByChainId;

    /**
     * @notice Constructor that sets up the test environment with two chain forks
     * @dev Creates forks for two L2 chains and maps their chain IDs to fork IDs
     */
    constructor() {
        vm.recordLogs();

        chainA = vm.createFork("http://127.0.0.1:9545");
        chainB = vm.createFork("http://127.0.0.1:9546");

        vm.selectFork(chainA);
        forkIdByChainId[block.chainid] = chainA;

        vm.selectFork(chainB);
        forkIdByChainId[block.chainid] = chainB;
    }

    /**
     * @notice Selects a fork based on the chain ID
     * @param chainId The chain ID to select
     * @return forkId The selected fork ID
     */
    function selectForkByChainId(uint256 chainId) internal returns (uint256) {
        uint256 forkId = forkIdByChainId[chainId];
        vm.selectFork(forkId);
        return forkId;
    }

    /**
     * @notice Relays all pending cross-chain messages
     * @dev Filters logs for SentMessage events and relays them to their destination chains
     *      This function handles the entire relay process:
     *      1. Captures all SentMessage events
     *      2. Constructs the message payload for each event
     *      3. Creates an Identifier for each message
     *      4. Selects the destination chain fork
     *      5. Relays the message to the destination
     */
    function relayAllMessages() public {
        Vm.Log[] memory allLogs = vm.getRecordedLogs();

        for (uint256 i = 0; i < allLogs.length; i++) {
            Vm.Log memory log = allLogs[i];

            // Skip logs that aren't SentMessage events
            if (log.topics[0] != keccak256("SentMessage(uint256,address,uint256,address,bytes)")) continue;

            bytes memory payload = constructMessagePayload(log);

            // identifier is spoofed because recorded log does not capture block number that the log was emitted on.
            Identifier memory id = Identifier(
                PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER, block.number, i, block.timestamp, block.chainid
            );
            bytes32 slot = ICrossL2Inbox(PredeployAddresses.CROSS_L2_INBOX).calculateChecksum(id, keccak256(payload));
            uint256 destination = uint256(log.topics[1]);

            selectForkByChainId(destination);

            // warm slot
            vm.load(PredeployAddresses.CROSS_L2_INBOX, slot);

            // relay message
            messenger.relayMessage(id, payload);
        }
    }

    /**
     * @notice Constructs a message payload from a log
     * @param log The log containing the SentMessage event data
     * @return A bytes array containing the reconstructed message payload
     * @dev This function reconstructs the original message payload by:
     *      1. Copying all topics (32 bytes each)
     *      2. Appending the log data
     *      The resulting payload is used for message relay
     */
    function constructMessagePayload(Vm.Log memory log) internal pure returns (bytes memory) {
        // Calculate total length: each topic is 32 bytes + data length
        uint256 totalLength = (log.topics.length * 32) + log.data.length;
        bytes memory payload = new bytes(totalLength);
        uint256 cursor = 0;

        // Copy each topic (32 bytes each)
        for (uint256 i = 0; i < log.topics.length; i++) {
            bytes32 topic = log.topics[i];
            assembly {
                let payloadPtr := add(add(payload, 32), cursor) // 32 is to skip length prefix
                mstore(payloadPtr, topic)
            }
            cursor += 32;
        }

        // Copy the data
        bytes memory logData = log.data; // Create a local variable to use in assembly
        assembly {
            let dataLength := mload(logData)
            if gt(dataLength, 0) {
                let payloadPtr := add(add(payload, 32), cursor) // 32 is to skip length prefix
                let dataPtr := add(logData, 32) // 32 is to skip length prefix
                for { let i := 0 } lt(i, dataLength) { i := add(i, 32) } {
                    mstore(add(payloadPtr, i), mload(add(dataPtr, i)))
                }
            }
        }

        return payload;
    }
}
