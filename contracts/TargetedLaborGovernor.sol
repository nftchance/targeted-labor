// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Auth, Authority} from "solmate/src/auth/Auth.sol";

contract TargetedLaborGovernor is Auth {
    /// @dev The address of the signer.
    address public signer;
    
    /// @dev The fee for the protocol.
    uint256 public fee;

    /// @dev A mapping of non-blocking nonces for an address.
    mapping(address => mapping(uint256 => uint256)) public nonces;

    constructor(uint256 _fee) Auth(msg.sender, Authority(address(0))) {
        fee = _fee;
    }

    /// @dev Allows the governor to set the signer.
    function setSigner(address _signer) public requiresAuth {
        signer = _signer;
    }

    /// @dev Allows the governor to set the fee.
    function setFee(uint256 _fee) public requiresAuth {
        fee = _fee;
    }
}
