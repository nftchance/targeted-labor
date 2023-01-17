// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {IERC20, IRoyaltiesManager, TargetedLaborStorage} from "./TargetedLaborStorage.sol";

abstract contract TargetedLaborFront is TargetedLaborStorage {
    /**
     * @dev Get the active bid id and index by a requester and a specific provider.
     * @notice If the requester has not a valid bid, the transaction will be reverted.
     * @param _provider Address of the provider being requested for the job.
     * @param _requester Address of the requester requesting the job.
     * @return bidIndex The bid index to be used within bidsByProvider mapping.
     * @return bidId The id of the bid in the system.
     * @return requester The confirmed address of the requester of work.
     * @return amount The amount of payment token associated with this bid.
     * @return expires uint256 of the expiration time
     */
    function getBidByRequester(address _provider, address _requester)
        public
        view
        returns (
            uint256 bidIndex,
            bytes32 bidId,
            address requester,
            uint256 amount,
            uint256 expires
        )
    {
        /// @dev Get the bid by requester and provider.
        bidId = bidIdByProviderAndRequester[_provider][_requester];

        /// @dev Get the bid index by bid id.
        bidIndex = bidIdToIndex[bidId];

        /// @dev Get all of the bid details.
        (bidId, requester, amount, expires) = getBidByProvider(
            _provider,
            bidIndex
        );

        /// @dev Check if the bid is valid.
        require(_requester == requester, "TargetedLaborBidHouse: Invalid bid");
    }

    /**
     * @dev Get the active bid id and index by a requester and a specific index.
     * @param _provider Address of the provider being requested for the job.
     * @param _bidIndex The index of the bid to be retrieved.
     * @return The id of the bid in the system.
     * @return Address of the requester requesting the job.
     * @return The amount of payment token associated with this bid.
     * @return When the bid expires.
     */
    function getBidByProvider(address _provider, uint256 _bidIndex)
        public
        view
        returns (
            bytes32,
            address,
            uint256,
            uint256
        )
    {
        /// @dev Get the bid by provider and index.
        Bid memory bid = _getBid(_provider, _bidIndex);

        /// @dev Surface up the bid details.
        return (bid.id, bid.requester, bid.amount, bid.expires);
    }

    /**
     * @dev Creates a bid for a provider for a requester.
     * @param _provider Address of the provider being requested for the job.
     * @param _tokenAddress Address of the token that is used as payment.
     * @param _amount Amount of tokens that the requester is willing to pay.
     * @param _duration Duration of the job in seconds.
     * @param _fingerprint Fingerprint of the job.
     */
    function _bid(
        address _provider,
        address _tokenAddress,
        uint256 _amount,
        uint256 _duration,
        bytes memory _fingerprint
    ) internal whenNotPaused {
        /// @dev Save the requester to the stack.
        address requester = msg.sender;

        /// @dev Make sure spam-bids are not possible.
        require(
            _amount > 0,
            "TargetedLaborBidHouse: Amount must be greater than 0"
        );

        /// @dev Confirm the requester has sufficient funds.
        _requireRequesterBalance(requester, _amount);

        /// @dev Make sure the duration is within the min and max duration.
        require(
            _duration > MIN_BID_DURATION && _duration < MAX_BID_DURATION,
            "TargetedLaborBidHouse: Duration must be within the min and max duration"
        );

        /// @dev Make sure the provider is a valid address and not the requester.
        require(
            _provider != address(0) && _provider != requester,
            "TargetedLaborBidHouse: Provider must be a valid address and not the sender"
        );

        /// @dev Determine when the bid will expire.
        uint256 expires = block.timestamp + _duration;

        /// @dev Create the bid id that will be used to reference the bid.
        bytes32 bidId = keccak256(
            abi.encode(
                block.timestamp,
                requester,
                _tokenAddress,
                _amount,
                _duration,
                _fingerprint
            )
        );

        /// @dev Create an index variable in-stack as we are fixing to get the providers bids.
        uint256 bidIndex;

        /// @dev Clear out an old bid this requester has for the provider if there is one.
        if (_requesterHasABid(_provider, requester)) {
            bytes32 oldBidId;
            (bidIndex, oldBidId, , , ) = getBidByRequester(
                _provider,
                requester
            );

            /// @dev Remove the old bid from the provider.
            delete bidIdToIndex[oldBidId];
        } else {
            /// @dev Assign the bid index to the current bid counter for the provider.
            bidIndex = bidCounterByProvider[_provider];

            /// @dev Increment the bid counter for the provider.
            bidCounterByProvider[_provider]++;
        }

        /// @dev Set the bid reference.
        bidIdByProviderAndRequester[_provider][requester] = bidId;
        bidIdToIndex[bidId] = bidIndex;

        /// @dev Save the bid in the providers ledger.
        bidsByProvider[_provider][bidIndex] = Bid({
            id: bidId,
            requester: requester,
            tokenAddress: _tokenAddress,
            amount: _amount,
            expires: expires,
            fingerprint: _fingerprint
        });

        /// @dev Announce that a new bid was created.
        emit BidCreated(
            bidId,
            _provider,
            requester,
            _tokenAddress,
            _amount,
            expires,
            _fingerprint
        );
    }

    /**
     * @dev Remove expired bid.
     * @param _provider Address of the provider being requested for the job.
     * @param _requester Address of the requester requesting the job.
     */
    function _removeExpired(address _provider, address _requester)
        internal
        whenNotPaused
    {
        /// @dev Get the details of the bid.
        (
            uint256 bidIndex,
            bytes32 bidId,
            ,
            ,
            uint256 expires
        ) = getBidByRequester(_provider, _requester);

        /// @dev Confirm the bid is expired.
        require(
            expires < block.timestamp,
            "TargetedLaborBidHouse: Bid is not expired"
        );

        /// @dev Remove the bid from the provider.
        _cancel(bidIndex, bidId, _provider, _requester);
    }

    /**
     * @dev Cancel a bid by a provider for a requester.
     * @param _bidIndex The index of the bid to be retrieved.
     * @param _bidId The id of the bid to be retrieved.
     * @param _provider Address of the provider being requested for the job.
     * @param _requester Address of the requester requesting the job.
     */
    function _cancel(
        uint256 _bidIndex,
        bytes32 _bidId,
        address _provider,
        address _requester
    ) internal whenNotPaused {
        /// @dev Delete the stored bid data.
        delete bidIdToIndex[_bidId];
        delete bidIdByProviderAndRequester[_provider][_requester];

        /// @dev Check if the bid is at the end of the mapping
        uint256 lastBidIndex = bidCounterByProvider[_provider] - 1;
        if (lastBidIndex != _bidIndex) {
            /// @dev Move last bid to the removed place.
            Bid storage lastBid = bidsByProvider[_provider][lastBidIndex];

            /// @dev Update the bids that are stored on the provider.
            bidsByProvider[_provider][_bidIndex] = lastBid;

            /// @dev Update the bid index.
            bidIdToIndex[lastBid.id] = _bidIndex;
        }

        /// @dev Delete empty index.
        delete bidsByProvider[_provider][lastBidIndex];

        /// @dev Decrease bids counter.
        bidCounterByProvider[_provider]--;

        /// @dev Announce that the bid was cancelled.
        emit BidCancelled(_bidId, _provider, _requester);
    }

    /**
     * @dev Accept a bid by a provider for a requester.
     * @param _bidIndex The index of the bid to be retrieved.
     * @param _bidId The id of the bid to be retrieved.
     * @param _provider Address of the provider being requested for the job.
     * @param _requester Address of the requester requesting the job.
     */
    function _accept(
        uint256 _bidIndex,
        bytes32 _bidId,
        address _provider,
        address _requester
    ) internal whenNotPaused {
        /// @dev Get the bid details out of storage and into memory.
        Bid memory requesterBid = _getBid(_provider, _bidIndex);

        /// @dev Ensure the bid meets the valid-state conditions.
        require(
            requesterBid.id == _bidId &&
                requesterBid.expires >= block.timestamp,
            "TargetedLaborBid: Bid does not exist or has expired"
        );

        /// @dev Get the bid details out of storage and into memory.
        address requester = requesterBid.requester;
        uint256 amount = requesterBid.amount;

        /// @dev Check that the requester is the same as the one passed in.
        _requireRequesterBalance(_requester, amount);

        /// @dev Remove the bid from the provider's list of bids.
        delete bidsByProvider[_provider][_bidIndex];
        delete bidIdToIndex[_bidId];
        delete bidIdByProviderAndRequester[_provider][requester];

        /// @dev Increment the bid counter for the provider.
        delete bidCounterByProvider[_provider];

        uint256 royaltiesShareAmount;
        address royaltiesReceiver;

        if (royaltiesCutPerMillion > 0) {
            royaltiesShareAmount =
                (amount * royaltiesCutPerMillion) /
                ONE_MILLION;

            (bool success, bytes memory res) = address(royaltiesManager)
                .staticcall(
                    abi.encodeWithSelector(
                        royaltiesManager.getRoyaltiesReceiver.selector,
                        address(this),
                        requester,
                        _provider
                    )
                );

            if (success) {
                (royaltiesReceiver) = abi.decode(res, (address));
                if (royaltiesReceiver != address(0)) {
                    require(
                        paymentToken.transferFrom(
                            _requester,
                            royaltiesReceiver,
                            royaltiesShareAmount
                        ),
                        "TargetedLaborBid: Failed to transfer royalties to receiver"
                    );
                }
            }
        }

        /// @dev Transfer the funds to the provider.
        paymentToken.transferFrom(
            _requester,
            _provider,
            amount - royaltiesShareAmount
        );
    }

    /**
     * @dev Check if the requester has a bid for an specific token.
     * @param _provider Address of the provider being requested for the job.
     * @param _requester Address of the requester requesting the job.
     * @return True if the requester has a bid for the provider.
     */
    function _requesterHasABid(address _provider, address _requester)
        internal
        view
        returns (bool)
    {
        /// @dev Get the bid id for the requester and provider.
        bytes32 bidId = bidIdByProviderAndRequester[_provider][_requester];

        /// @dev Get the bid index based on the id.
        uint256 bidIndex = bidIdToIndex[bidId];

        /// @dev Check if the bid index is valid.
        if (bidIndex >= bidCounterByProvider[_provider]) return false;

        /// @dev Get the bid from the provider.
        Bid memory bid = bidsByProvider[_provider][bidIndex];

        /// @dev Check if the bid is valid.
        return bid.requester == _requester;
    }

    /**
     * @dev Get the active bid id and index by a requester and an specific token.
     * @notice If the index is not valid, it will revert.
     * @param _provider Address of the provider being requested for the job.
     * @param _bidIndex The index of the bid to be retrieved.
     * @return Bid
     */
    function _getBid(address _provider, uint256 _bidIndex)
        internal
        view
        returns (Bid memory)
    {
        /// @dev Check if the bid index is valid.
        require(
            _bidIndex < bidCounterByProvider[_provider],
            "TargetedLaborBidHouse: Invalid bid index"
        );

        /// @dev Get the bid from the provider.
        return bidsByProvider[_provider][_bidIndex];
    }

    /**
     * @dev Check if the requester has balance and the contract.
     *      has enough allowance to use the requesters payment tokens on their belhalf.
     * @param _requester Address of the requester requesting the job.
     * @param _amount Amount of tokens that the requester is willing to pay.
     */
    function _requireRequesterBalance(address _requester, uint256 _amount)
        internal
        view
    {
        /// @dev Confirm the requester has enough balance.
        require(
            paymentToken.balanceOf(_requester) >= _amount,
            "ERC721Bid#_requireRequesterBalance: INSUFFICIENT_FUNDS"
        );

        /// @dev Confirm the balance is approved for use by the contract.
        require(
            paymentToken.allowance(_requester, address(this)) >= _amount,
            "ERC721Bid#_requireRequesterBalance: CONTRACT_NOT_AUTHORIZED"
        );
    }

    /**
     * @dev Convert bytes to bytes32.
     * @param _data The bytes to be converted.
     * @return The bytes32 representation of the bytes.
     */
    function _bytesToBytes32(bytes memory _data)
        internal
        pure
        returns (bytes32)
    {
        require(
            _data.length == 32,
            "ERC721Bid#_bytesToBytes32: DATA_LENGHT_SHOULD_BE_32"
        );

        bytes32 bidId;
        assembly {
            bidId := mload(add(_data, 0x20))
        }
        return bidId;
    }
}
