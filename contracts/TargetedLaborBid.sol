// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {Auth, Authority} from "solmate/src/auth/Auth.sol";

// I want to create a contract where users can placed bids of an ERC20 token on a job.
// Jobs are assigned to addresses that are pending by default and then accepted or rejected by the provider the job is offered to.
// With this, I do not want to charge bidders money as they are just singing a signature. When the provider accepts a job, the er20 is moved into the contract.
// The requester can also choose to cancel the job and withdraw the funds from the contract related to that job.
contract TargetedLaborBid is Auth {
    constructor() Auth(msg.sender, Authority(address(0))) {}

    function bid(
        address _provider,
        address _tokenAddress,
        uint256 _amount,
        uint256 _duration
    ) public {
        _bid(_provider, _tokenAddress, _amount, _duration, "");
    }

    function bid(
        address _provider,
        address _tokenAddress,
        uint256 _amount,
        uint256 _duration,
        bytes memory _fingerprint
    ) public {
        _bid(_provider, _tokenAddress, _amount, _duration, _fingerprint);
    }

    function _bid(
        address _provider,
        address _tokenAddress,
        uint256 _amount,
        uint256 _duration,
        bytes memory _fingerprint
    ) internal {
        address sender = msg.sender;

        require(_amount > 0, "TargetedLaborBid: amount must be greater than 0");

        _requireBidderBalance(sender, _amount);

        require(
            _duration > MIN_BID_DURATION,
            "TargetedLaborBid: duration must be greater than MIN_BID_DURATION"
        );

        require(
            _duration < MAX_BID_DURATION,
            "TargetedLaborBid: duration must be less than MAX_BID_DURATION"
        );

        require(
            _provider != address(0) && _provider != sender,
            "TargetedLaborBid: provider must be a valid address and not the sender"
        );

        uint256 expires = block.timestamp + _duration;

        bytes32 bidId = keccak256(
            abi.encode(
                block.timestamp,
                sender,
                _tokenAddress,
                _amount,
                _duration,
                _fingerprint
            )
        );
    }

    function acceptBid() public {}

    function rejectBid() public {
        // I want to reject a bid on a job.
    }

    function cancelJob() public {
        // I want to cancel a job.
    }

    function withdrawFunds() public {
        // I want to withdraw funds from a job.
    }
}
