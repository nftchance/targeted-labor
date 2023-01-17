// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRoyaltiesManager {
    function getRoyaltiesReceiver(
        address _marketAddress,
        address _requester,
        address _provider
    ) external view returns (address);
}
