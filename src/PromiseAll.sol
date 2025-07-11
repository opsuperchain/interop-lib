// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Promise} from "./Promise.sol";
import {IResolvable} from "./interfaces/IResolvable.sol";

/// @title PromiseAll
/// @notice JavaScript-style Promise.all() implementation that resolves when all input promises resolve,
///         or rejects immediately when any input promise rejects
contract PromiseAll is IResolvable {
    /// @notice The Promise contract instance
    Promise public immutable promiseContract;

    /// @notice Structure to track a PromiseAll instance
    struct PromiseAllData {
        uint256[] inputPromises;     // Array of input promise IDs
    }

    /// @notice Mapping from PromiseAll promise ID to its data
    mapping(uint256 => PromiseAllData) private promiseAllData;

    /// @notice Event emitted when a PromiseAll is created
    event PromiseAllCreated(uint256 indexed promiseAllId, uint256[] inputPromises);

    /// @notice Event emitted when a PromiseAll resolves
    event PromiseAllResolved(uint256 indexed promiseAllId, bytes[] values);

    /// @notice Event emitted when a PromiseAll rejects
    event PromiseAllRejected(uint256 indexed promiseAllId, uint256 failedPromiseId, bytes errorData);

    /// @param _promiseContract The address of the Promise contract
    constructor(address _promiseContract) {
        promiseContract = Promise(_promiseContract);
    }

    /// @notice Create a new PromiseAll that resolves when all input promises resolve
    /// @param inputPromises Array of promise IDs to wait for
    /// @return promiseAllId The ID of the created PromiseAll promise
    function create(uint256[] memory inputPromises) external returns (uint256 promiseAllId) {
        require(inputPromises.length > 0, "PromiseAll: empty input array");
        
        // Create a promise for this PromiseAll
        promiseAllId = promiseContract.create();
        
        // Initialize the PromiseAll data
        PromiseAllData storage data = promiseAllData[promiseAllId];
        data.inputPromises = inputPromises;
        
        emit PromiseAllCreated(promiseAllId, inputPromises);
    }

    /// @notice Check if a PromiseAll can be resolved or needs to be rejected
    /// @param promiseAllId The ID of the PromiseAll promise to check
    /// @return canResolve Whether the PromiseAll can be resolved/rejected now
    function canResolve(uint256 promiseAllId) external view returns (bool canResolve) {
        PromiseAllData storage data = promiseAllData[promiseAllId];
        
        // Must exist and not be settled yet
        if (data.inputPromises.length == 0) {
            return false;
        }
        
        // Check if the PromiseAll promise itself is still pending
        Promise.PromiseStatus status = promiseContract.status(promiseAllId);
        if (status != Promise.PromiseStatus.Pending) {
            return false;
        }
        
        // Check if any input promise has rejected (fail-fast)
        for (uint256 i = 0; i < data.inputPromises.length; i++) {
            Promise.PromiseStatus inputStatus = promiseContract.status(data.inputPromises[i]);
            if (inputStatus == Promise.PromiseStatus.Rejected) {
                return true; // Can resolve (actually reject) immediately
            }
        }
        
        // Check if all input promises have resolved
        uint256 resolvedCount = 0;
        for (uint256 i = 0; i < data.inputPromises.length; i++) {
            Promise.PromiseStatus inputStatus = promiseContract.status(data.inputPromises[i]);
            if (inputStatus == Promise.PromiseStatus.Resolved) {
                resolvedCount++;
            }
        }
        
        return resolvedCount == data.inputPromises.length;
    }

    /// @notice Resolve or reject the PromiseAll based on input promise states
    /// @param promiseAllId The ID of the PromiseAll promise to resolve
    function resolve(uint256 promiseAllId) external {
        PromiseAllData storage data = promiseAllData[promiseAllId];
        
        require(data.inputPromises.length > 0, "PromiseAll: promise does not exist");
        
        Promise.PromiseStatus status = promiseContract.status(promiseAllId);
        require(status == Promise.PromiseStatus.Pending, "PromiseAll: promise already settled");
        
        // Check if any input promise has rejected (fail-fast)
        for (uint256 i = 0; i < data.inputPromises.length; i++) {
            Promise.PromiseStatus inputStatus = promiseContract.status(data.inputPromises[i]);
            if (inputStatus == Promise.PromiseStatus.Rejected) {
                // Reject the PromiseAll with the first rejection found
                Promise.PromiseData memory promiseData = promiseContract.getPromise(data.inputPromises[i]);
                
                promiseContract.reject(promiseAllId, promiseData.returnData);
                emit PromiseAllRejected(promiseAllId, data.inputPromises[i], promiseData.returnData);
                
                // Clean up storage
                delete promiseAllData[promiseAllId];
                return;
            }
        }
        
        // Check if all input promises have resolved
        uint256 resolvedCount = 0;
        for (uint256 i = 0; i < data.inputPromises.length; i++) {
            Promise.PromiseStatus inputStatus = promiseContract.status(data.inputPromises[i]);
            if (inputStatus == Promise.PromiseStatus.Resolved) {
                resolvedCount++;
            }
        }
        
        require(resolvedCount == data.inputPromises.length, "PromiseAll: not all promises resolved yet");
        
        // All promises resolved - collect values and resolve the PromiseAll
        bytes[] memory resolvedValues = new bytes[](data.inputPromises.length);
        for (uint256 i = 0; i < data.inputPromises.length; i++) {
            Promise.PromiseData memory promiseData = promiseContract.getPromise(data.inputPromises[i]);
            resolvedValues[i] = promiseData.returnData;
        }
        
        bytes memory encodedValues = abi.encode(resolvedValues);
        
        promiseContract.resolve(promiseAllId, encodedValues);
        emit PromiseAllResolved(promiseAllId, resolvedValues);
        
        // Clean up storage
        delete promiseAllData[promiseAllId];
    }

    /// @notice Get the input promises for a PromiseAll
    /// @param promiseAllId The ID of the PromiseAll promise
    /// @return inputPromises Array of input promise IDs
    function getInputPromises(uint256 promiseAllId) external view returns (uint256[] memory inputPromises) {
        return promiseAllData[promiseAllId].inputPromises;
    }

    /// @notice Get the current resolution status of a PromiseAll
    /// @param promiseAllId The ID of the PromiseAll promise
    /// @return resolvedCount Number of input promises that have resolved
    /// @return totalCount Total number of input promises
    /// @return settled Whether the PromiseAll has been settled
    function getStatus(uint256 promiseAllId) external view returns (uint256 resolvedCount, uint256 totalCount, bool settled) {
        PromiseAllData storage data = promiseAllData[promiseAllId];
        
        // Count currently resolved promises
        resolvedCount = 0;
        for (uint256 i = 0; i < data.inputPromises.length; i++) {
            Promise.PromiseStatus inputStatus = promiseContract.status(data.inputPromises[i]);
            if (inputStatus == Promise.PromiseStatus.Resolved) {
                resolvedCount++;
            }
        }
        
        // Check if PromiseAll itself is settled
        Promise.PromiseStatus promiseAllStatus = promiseContract.status(promiseAllId);
        settled = (promiseAllStatus != Promise.PromiseStatus.Pending);
        
        return (resolvedCount, data.inputPromises.length, settled);
    }

    /// @notice Check if a PromiseAll exists
    /// @param promiseAllId The ID to check
    /// @return exists Whether the PromiseAll exists
    function exists(uint256 promiseAllId) external view returns (bool exists) {
        return promiseAllData[promiseAllId].inputPromises.length > 0;
    }
} 