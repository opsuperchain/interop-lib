// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PredeployAddresses} from "./PredeployAddresses.sol";
import {IL2ToL2CrossDomainMessenger} from "../interfaces/IL2ToL2CrossDomainMessenger.sol";

library CrossDomainMessageLib {
    /// @notice The error emitted when a dependent message has not been relayed.
    error DependentMessageNotSuccessful(bytes32 msgHash);
    /// @notice The error emitted when the caller is not the L2toL2CrossDomainMessenger.
    error CallerNotL2toL2CrossDomainMessenger();
    /// @notice The error emitted when the original sender of the cross-domain message is not this same address as this contract.
    error InvalidCrossDomainSender();

    /// @notice Checks if the msgHash has been relayed and reverts with a special error signature
    /// that the auto-relayer performs special handling on if the msgHash has not been relayed.
    /// If the auto-relayer encounters this error, it will parse the msgHash and wait for the
    /// msgHash to be relayed before relaying the message that calls this function. This ensures
    /// that any dependent message is relayed before the message that depends on it.
    /// @param msgHash The hash of the message to check if it has been relayed.
    function requireMessageSuccess(bytes32 msgHash) internal view {
        if (
            !IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER).successfulMessages(msgHash)
        ) {
            revert DependentMessageNotSuccessful(msgHash);
        }
    }

    /// @notice Checks if the caller is the L2toL2CrossDomainMessenger. It is important to use this check
    /// on cross-domain messages that should only be relayed through the L2toL2CrossDomainMessenger.
    function requireCallerIsCrossDomainMessenger() internal view {
        if (msg.sender != address(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER)) {
            revert CallerNotL2toL2CrossDomainMessenger();
        }
    }

    /// @notice While relaying a message through the L2toL2CrossDomainMessenger, checks
    /// that the original sender of the cross-domain message is this same address.
    /// It is important to use this check on cross-domain messages that should only be
    /// sent and relayed by the same contract on different chains.
    function requireCrossDomainCallback() internal view {
        requireCallerIsCrossDomainMessenger();

        if (
            IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageSender()
                != address(this)
        ) revert InvalidCrossDomainSender();
    }
}
