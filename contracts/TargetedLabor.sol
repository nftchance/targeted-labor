// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

/// @dev Core dependencies.
import {TargetedLaborGovernor} from "./TargetedLaborGovernor.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IERC20 {
    function transfer(address _recipient, uint256 _amount)
        external
        returns (bool);

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);
}

/**
 * @title TargetedLabor
 * @dev A protocol for targeted labor that allows requesters to build off-chain jobs that can be
 *      accepted by providers in the protocol.
 */
contract TargetedLabor is TargetedLaborGovernor {
    using ECDSA for bytes32;

    struct Job {
        address funder;
        address target;
        uint256 expiration;
        Release release;
        Funding funding;
        uint256 nonce;
    }

    struct Funding {
        IERC20 token;
        uint256 amount;
    }

    struct Release {
        uint256 placeholder;
    }

    mapping(address => Job) public funderToJobs;

    /// @dev Initialize the protocol.
    constructor(uint256 _fee) TargetedLaborGovernor(_fee) {}

    /// @dev Allows requesters to cancel a job.
    function cancel() public {
        // TODO: Check the funder of the job.
        // TODO: Yoink money back.
        // TODO: Terminate the job.
    }

    /// @dev Allows providers in the protocol to accept a job or any changes when edited.
    function accept(bytes memory _job, bytes memory _signature) public {
        /// @dev Decode the job.
        Job memory job = abi.decode(_job, (Job));

        /// @dev Check that the nonce is all good.
        require(
            job.nonce == ++nonces[msg.sender][job.nonce],
            "TargetedLabor: Nonce already used."
        );

        // @dev Then we hash the details of the job with the target that is
        //      accepting the job.
        bytes32 jobHash = keccak256(
            abi.encodePacked(
                job.funder,
                job.target,
                job.expiration,
                job.funding.token,
                job.funding.amount,
                job.release.placeholder,
                job.nonce,
                msg.sender
            )
        );

        // @dev Check the signature
        require(
            jobHash.recover(_signature) == job.funder,
            "TargetedLabor: Invalid signature"
        );

        /// @dev Transfer the ERC20 being used as payment from the funder.
        require(
            job.funding.token.transferFrom(
                job.funder,
                address(this),
                job.funding.amount
            ),
            "TargetedLabor: Failed to transfer ERC20."
        );

        funderToJobs[job.funder] = job;
    }

    /// @dev Allows providers to withdraw their earnings.
    function withdraw() public {
        // TODO: Determine the amount of funds the provider has earned.
    }
}
