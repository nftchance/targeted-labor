// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

/// @dev Core dependencies.
import {TargetedLaborFront} from "./TargetedLaborFront.sol";
import {IERC20, IRoyaltiesManager, TargetedLaborStorage} from "./TargetedLaborStorage.sol";

contract TargetedLabor is TargetedLaborFront {
    constructor(
        address _owner,
        address _feesCollector,
        IERC20 _paymentToken,
        IRoyaltiesManager _royaltiesManager,
        uint256 _feesCollectorCutPerMillion,
        uint256 _royaltiesCutPerMillion
    )
        TargetedLaborStorage(
            _feesCollector,
            _paymentToken,
            _royaltiesManager,
            _feesCollectorCutPerMillion,
            _royaltiesCutPerMillion
        )
    {
        // EIP712 init
        // _initializeEIP712('Labor', '2');
    }

    /**
     * See {TargetedLaborBid._bid}
     *
     * @notice This an overloaded function and does not include `fingerprint` as a parameter.
     */
    function bid(
        address _provider,
        address _tokenAddress,
        uint256 _amount,
        uint256 _duration
    ) public {
        _bid(_provider, _tokenAddress, _amount, _duration, "");
    }

    /**
     * See {TargetedLaborBid._bid}
     */
    function bid(
        address _provider,
        address _tokenAddress,
        uint256 _amount,
        uint256 _duration,
        bytes memory _fingerprint
    ) public {
        _bid(_provider, _tokenAddress, _amount, _duration, _fingerprint);
    }

    /**
     * @dev Remove expired bids from a provider.
     * @param _providers List of provider addresses to remove expired bids from.
     * @param _requesters List of bidder addresses to remove expired bids from.
     */
    function removeExpired(
        address[] memory _providers,
        address[] memory _requesters
    ) public {
        uint256 loopLength = _providers.length;

        /// @dev Check that the arrays are of equal length.
        require(
            loopLength == _requesters.length,
            "TargetedLaborBid: Arrays must be of equal length"
        );

        /// @dev Load the for loop stack.
        uint256 i;

        /// @dev Loop through the arrays and remove expired bids.
        for (i; i < loopLength; i++) {
            /// @dev Remove the individual expired bid.
            _removeExpired(_providers[i], _requesters[i]);
        }
    }

    /**
     * @dev Remove expired bids from a provider.
     * @param _provider Provider address to remove expired bids from.
     */
    function cancel(address _provider) public {
        address requester = msg.sender;

        /// @dev Get the active bid for the provider and requester.
        (uint256 bidIndex, bytes32 bidId, , , ) = getBidByRequester(
            _provider,
            requester
        );

        /// @dev Check that the bid exists.
        _cancel(bidIndex, bidId, _provider, requester);
    }

    /**
     * @dev Accept a bid for a provider placed by a requester.
     * @param _provider Address of the provider being requested for the job.
     * @param _requester Address of the requester requesting the job.
     * @param _data Data to be passed to the accept function.
     */
    function accept(
        address _provider,
        address _requester,
        bytes memory _data
    ) public {
        /// @dev Get the active bid for the provider and requester.
        bytes32 bidId = _bytesToBytes32(_data);

        /// @dev Check that the bid exists.
        uint256 bidIndex = bidIdToIndex[bidId];

        /// @dev Accept the bid.
        _accept(bidIndex, bidId, _provider, _requester);
    }

    function withdrawFunds() public {
        // I want to withdraw funds from a job.
    }
}
