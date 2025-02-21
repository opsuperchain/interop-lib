# Advanced Patterns

This doc contains advanced patterns for constructing and handling cross chain messages.

## Dependent Message Hashes

It is possible that you may have messages that depend on the result of other messages. For example, you may want to bridge an ERC20 to another chain and then perform an action only after the ERC20 has been successfully bridged. In order to do this, you need to make sure that the cross-domain messages are relayed in the correct order. The `requireMessageSuccess` function from the [CrossDomainMessageLib](https://github.com/ethereum-optimism/interop-lib/blob/main/src/libraries/CrossDomainMessageLib.sol) can be used to make sure that the dependent message hash completes before continuing on to relay next message. In order to get this to relay properly you could either manually relay the messages in the correct order or add special handling to your relayer that parses the dependent message hash from the `DependentMessageNotSuccessful(bytes32)` error signature and then have the auto-relayer wait for that dependent message to be relayed before relaying the next message. [Supersim](https://github.com/ethereum-optimism/supersim) and the interop devnet auto-relayer have this functionality built in, so they will handle the auto-relaying properly if you use the `requireMessageSuccess` function. Here is an example of how to use this pattern (referenced from the [superchain-starter-multisend](https://github.com/ethereum-optimism/superchain-starter-multisend/blob/main/contracts/src/CrossChainMultisend.sol) example):

```solidity

 function send(uint256 _destinationChainId, Send[] calldata _sends) public payable returns (bytes32) {
        uint256 totalAmount;
        for (uint256 i; i < _sends.length; i++) {
            totalAmount += _sends[i].amount;
        }

        if (msg.value != totalAmount) revert IncorrectValue();

        bytes32 sendWethMsgHash = superchainWeth.sendETH{value: totalAmount}(address(this), _destinationChainId);

        return l2ToL2CrossDomainMessenger.sendMessage(
            _destinationChainId, address(this), abi.encodeCall(this.relay, (sendWethMsgHash, _sends))
        );
    }

    function relay(bytes32 _sendWethMsgHash, Send[] calldata _sends) public {
        CrossDomainMessageLib.requireCrossDomainCallback();
        // CrossDomainMessageLib.requireMessageSuccess uses a special error signature that the
        // auto-relayer performs special handling on. The auto-relayer parses the _sendWethMsgHash
        // and waits for the _sendWethMsgHash to be relayed before relaying this message.
        CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);

        for (uint256 i; i < _sends.length; i++) {
            address to = _sends[i].to;
            // use .call for example purpose, but not recommended in production.
            (bool success,) = to.call{value: _sends[i].amount}("");
            require(success, "ETH transfer failed");
        }
    }

```

## Experimental

The patterns below are experimental and haven't been audited or rigorously tested.

### superchain-async Library

Link: https://github.com/ben-chain/superchain-async/tree/main

The `superchain-async` library provides an abstraction for asynchronous function calls across interoperating L2s. It introduces an async/promise pattern to handle cross-chain interactions, compatible with vanilla Solidity syntax. This library is still under development and is not yet ready for use in production. We are sharing it here for early feedback and contributions/improvements are welcome.