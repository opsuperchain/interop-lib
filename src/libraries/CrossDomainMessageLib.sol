// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PredeployAddresses} from "./PredeployAddresses.sol";
import {IL2ToL2CrossDomainMessenger} from "../interfaces/IL2ToL2CrossDomainMessenger.sol";

library CrossDomainMessageLib {
    error DependentMessageNotSuccessful(bytes32 msgHash);
    error CallerNotL2ToL2CrossDomainMessenger();
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

    function requireCallerIsCrossDomainMessenger() internal view {
        if (msg.sender != address(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER)) {
            revert CallerNotL2ToL2CrossDomainMessenger();
        }
    }

    function requireCrossDomainCallback() internal view {
        requireCallerIsCrossDomainMessenger();

        if (
            IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageSender()
                != address(this)
        ) revert InvalidCrossDomainSender();
    }
}
