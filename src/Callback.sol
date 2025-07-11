// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Promise} from "./Promise.sol";
import {IResolvable} from "./interfaces/IResolvable.sol";
import {IL2ToL2CrossDomainMessenger} from "./interfaces/IL2ToL2CrossDomainMessenger.sol";

/// @title Callback
/// @notice Callback promise contract that implements .then() and .catch() functionality
contract Callback is IResolvable {
    /// @notice The Promise contract instance
    Promise public immutable promiseContract;
    
    /// @notice Cross-domain messenger for sending cross-chain messages (optional)
    IL2ToL2CrossDomainMessenger public immutable messenger;
    
    /// @notice Current chain ID for generating global promise IDs (optional)
    uint256 public immutable currentChainId;

    /// @notice Callback types for handling different promise states
    enum CallbackType {
        Then,   // Executes when parent promise resolves
        Catch   // Executes when parent promise rejects
    }

    /// @notice Callback data structure
    struct CallbackData {
        uint256 parentPromiseId;
        address target;
        bytes4 selector;
        CallbackType callbackType;
    }

    /// @notice Mapping from callback promise ID to callback data
    mapping(uint256 => CallbackData) public callbacks;

    /// @notice Event emitted when a callback is registered
    event CallbackRegistered(uint256 indexed callbackPromiseId, uint256 indexed parentPromiseId, CallbackType callbackType);

    /// @notice Event emitted when a callback is executed
    event CallbackExecuted(uint256 indexed callbackPromiseId, bool success, bytes returnData);

    /// @param _promiseContract The address of the Promise contract
    /// @param _messenger The cross-domain messenger contract address (use address(0) for local-only mode)
    constructor(address _promiseContract, address _messenger) {
        promiseContract = Promise(_promiseContract);
        messenger = IL2ToL2CrossDomainMessenger(_messenger);
        currentChainId = block.chainid;
    }

    /// @notice Create a .then() callback that executes when the parent promise resolves
    /// @param parentPromiseId The ID of the parent promise to watch
    /// @param target The contract address to call when parent resolves
    /// @param selector The function selector to call
    /// @return callbackPromiseId The ID of the created callback promise
    function then(uint256 parentPromiseId, address target, bytes4 selector) external returns (uint256 callbackPromiseId) {
        // Create a new promise for this callback
        callbackPromiseId = promiseContract.create();
        
        // Store the callback data
        callbacks[callbackPromiseId] = CallbackData({
            parentPromiseId: parentPromiseId,
            target: target,
            selector: selector,
            callbackType: CallbackType.Then
        });
        
        emit CallbackRegistered(callbackPromiseId, parentPromiseId, CallbackType.Then);
    }

    /// @notice Create a .catch() callback that executes when the parent promise rejects
    /// @param parentPromiseId The ID of the parent promise to watch
    /// @param target The contract address to call when parent rejects
    /// @param selector The function selector to call
    /// @return callbackPromiseId The ID of the created callback promise
    function onReject(uint256 parentPromiseId, address target, bytes4 selector) external returns (uint256 callbackPromiseId) {
        // Create a new promise for this callback
        callbackPromiseId = promiseContract.create();
        
        // Store the callback data
        callbacks[callbackPromiseId] = CallbackData({
            parentPromiseId: parentPromiseId,
            target: target,
            selector: selector,
            callbackType: CallbackType.Catch
        });
        
        emit CallbackRegistered(callbackPromiseId, parentPromiseId, CallbackType.Catch);
    }

    /// @notice Create a cross-chain .then() callback that executes on another chain when the parent promise resolves
    /// @param destinationChain The chain ID where the callback should execute
    /// @param parentPromiseId The ID of the parent promise to watch
    /// @param target The contract address to call when parent resolves
    /// @param selector The function selector to call
    /// @return callbackPromiseId The ID of the created callback promise
    function thenOn(uint256 destinationChain, uint256 parentPromiseId, address target, bytes4 selector) external returns (uint256 callbackPromiseId) {
        require(address(messenger) != address(0), "Callback: cross-chain not enabled");
        require(destinationChain != currentChainId, "Callback: cannot register callback on same chain");
        
        // Create a new promise for this callback
        callbackPromiseId = promiseContract.create();
        
        // Transfer resolution rights to destination chain
        promiseContract.transferResolve(callbackPromiseId, destinationChain, address(this));
        
        // Send cross-chain message to register callback on destination chain
        bytes memory message = abi.encodeWithSignature(
            "receiveCallbackRegistration(uint256,uint256,address,bytes4,uint8)",
            callbackPromiseId,
            parentPromiseId, 
            target,
            selector,
            uint8(CallbackType.Then)
        );
        
        messenger.sendMessage(destinationChain, address(this), message);
        
        emit CallbackRegistered(callbackPromiseId, parentPromiseId, CallbackType.Then);
    }

    /// @notice Create a cross-chain .catch() callback that executes on another chain when the parent promise rejects
    /// @param destinationChain The chain ID where the callback should execute
    /// @param parentPromiseId The ID of the parent promise to watch
    /// @param target The contract address to call when parent rejects
    /// @param selector The function selector to call
    /// @return callbackPromiseId The ID of the created callback promise
    function onRejectOn(uint256 destinationChain, uint256 parentPromiseId, address target, bytes4 selector) external returns (uint256 callbackPromiseId) {
        require(address(messenger) != address(0), "Callback: cross-chain not enabled");
        require(destinationChain != currentChainId, "Callback: cannot register callback on same chain");
        
        // Create a new promise for this callback
        callbackPromiseId = promiseContract.create();
        
        // Transfer resolution rights to destination chain
        promiseContract.transferResolve(callbackPromiseId, destinationChain, address(this));
        
        // Send cross-chain message to register callback on destination chain
        bytes memory message = abi.encodeWithSignature(
            "receiveCallbackRegistration(uint256,uint256,address,bytes4,uint8)",
            callbackPromiseId,
            parentPromiseId,
            target, 
            selector,
            uint8(CallbackType.Catch)
        );
        
        messenger.sendMessage(destinationChain, address(this), message);
        
        emit CallbackRegistered(callbackPromiseId, parentPromiseId, CallbackType.Catch);
    }

    /// @notice Receive callback registration from another chain
    /// @param callbackPromiseId The global callback promise ID
    /// @param parentPromiseId The parent promise ID to watch  
    /// @param target The contract address to call when parent settles
    /// @param selector The function selector to call
    /// @param callbackType The type of callback (Then or Catch)
    function receiveCallbackRegistration(
        uint256 callbackPromiseId,
        uint256 parentPromiseId,
        address target,
        bytes4 selector,
        uint8 callbackType
    ) external {
        // Verify the message comes from another Callback contract via cross-domain messenger
        require(msg.sender == address(messenger), "Callback: only messenger can call");
        require(messenger.crossDomainMessageSender() == address(this), "Callback: only from Callback contract");
        
        // Store the callback data locally
        callbacks[callbackPromiseId] = CallbackData({
            parentPromiseId: parentPromiseId,
            target: target,
            selector: selector,
            callbackType: CallbackType(callbackType)
        });
        
        emit CallbackRegistered(callbackPromiseId, parentPromiseId, CallbackType(callbackType));
    }

    /// @notice Resolve a callback promise by executing the callback if conditions are met
    /// @param callbackPromiseId The ID of the callback promise to resolve
    function resolve(uint256 callbackPromiseId) external {
        CallbackData memory callbackData = callbacks[callbackPromiseId];
        require(callbackData.target != address(0), "Callback: callback does not exist");
        
        // Check that callback promise is still pending
        Promise.PromiseStatus callbackStatus = promiseContract.status(callbackPromiseId);
        require(callbackStatus == Promise.PromiseStatus.Pending, "Callback: callback already settled");
        
        // Get parent promise data
        Promise.PromiseData memory parentPromise = promiseContract.getPromise(callbackData.parentPromiseId);
        
        // Check if callback should execute based on parent state and callback type
        bool shouldExecute = false;
        if (callbackData.callbackType == CallbackType.Then && parentPromise.status == Promise.PromiseStatus.Resolved) {
            shouldExecute = true;
        } else if (callbackData.callbackType == CallbackType.Catch && parentPromise.status == Promise.PromiseStatus.Rejected) {
            shouldExecute = true;
        }
        
        if (!shouldExecute) {
            // If parent is still pending, cannot execute yet
            if (parentPromise.status == Promise.PromiseStatus.Pending) {
                revert("Callback: parent promise not settled");
            } else {
                // Parent is settled but doesn't match callback type, reject this callback
                promiseContract.reject(callbackPromiseId, abi.encode("Callback not applicable"));
                // Clean up storage
                delete callbacks[callbackPromiseId];
                emit CallbackExecuted(callbackPromiseId, false, abi.encode("Callback not applicable"));
                return;
            }
        }
        
        // Execute the callback
        (bool success, bytes memory returnData) = callbackData.target.call(
            abi.encodeWithSelector(callbackData.selector, parentPromise.returnData)
        );
        
        if (success) {
            // Resolve the callback promise with the return value from the callback
            promiseContract.resolve(callbackPromiseId, returnData);
        } else {
            // Reject the callback promise with the error data
            promiseContract.reject(callbackPromiseId, returnData);
        }
        
        // Clean up storage
        delete callbacks[callbackPromiseId];
        
        emit CallbackExecuted(callbackPromiseId, success, returnData);
    }

    /// @notice Check if a callback can be resolved
    /// @param callbackPromiseId The ID of the callback promise to check
    /// @return canResolve Whether the callback can be resolved now
    function canResolve(uint256 callbackPromiseId) external view returns (bool canResolve) {
        CallbackData memory callbackData = callbacks[callbackPromiseId];
        if (callbackData.target == address(0)) return false;
        
        // Check callback promise status
        Promise.PromiseStatus callbackStatus = promiseContract.status(callbackPromiseId);
        if (callbackStatus != Promise.PromiseStatus.Pending) return false;
        
        // Check parent promise status
        Promise.PromiseData memory parentPromise = promiseContract.getPromise(callbackData.parentPromiseId);
        
        if (callbackData.callbackType == CallbackType.Then && parentPromise.status == Promise.PromiseStatus.Resolved) {
            return true;
        } else if (callbackData.callbackType == CallbackType.Catch && parentPromise.status == Promise.PromiseStatus.Rejected) {
            return true;
        } else if (parentPromise.status != Promise.PromiseStatus.Pending) {
            // Parent is settled but doesn't match callback type
            return true; // Can resolve to reject the callback
        }
        
        return false;
    }

    /// @notice Get callback data for a callback promise
    /// @param callbackPromiseId The ID of the callback promise
    /// @return callbackData The callback data, or empty if doesn't exist
    function getCallback(uint256 callbackPromiseId) external view returns (CallbackData memory callbackData) {
        return callbacks[callbackPromiseId];
    }

    /// @notice Check if a callback promise exists
    /// @param callbackPromiseId The ID of the callback promise to check
    /// @return exists Whether the callback exists
    function exists(uint256 callbackPromiseId) external view returns (bool exists) {
        return callbacks[callbackPromiseId].target != address(0);
    }
} 