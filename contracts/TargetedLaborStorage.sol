// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Auth, Authority} from "solmate/src/auth/Auth.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IRoyaltiesManager} from "./interfaces/IRoyaltiesManager.sol";

/**
 * @title Interface for contracts conforming to ERC-20
 */
interface IERC20 {
    function balanceOf(address from) external view returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
}

contract TargetedLaborStorage is Auth, Pausable, EIP712 {
    struct Bid {
        // Bid Id
        bytes32 id;
        // Bidder address
        address requester;
        // ERC721 address
        address tokenAddress;
        // Price for the bid in wei
        uint256 amount;
        // Time when this bid ends
        uint256 expires;
        // Fingerprint for composable
        bytes fingerprint;
    }

    /// @dev Defining the range that bid duration can operate within.
    uint256 public constant MAX_BID_DURATION = 182 days;
    uint256 public constant MIN_BID_DURATION = 1 minutes;

    /// @dev Handling the fees that are charged for using this marketplace.
    uint256 public constant ONE_MILLION = 1000000;

    /// @dev The token that is used as currency in this marketplace.
    IERC20 public paymentToken;

    /// @dev Stores a single active bid from a requester to a provider.
    mapping(address => mapping(uint256 => Bid)) internal bidsByProvider;

    /// @dev Bid count by provider address => bid counts
    mapping(address => uint256) public bidCounterByProvider;

    /// @dev Index of the bid at bidsByToken mapping by bid id => bid index
    mapping(bytes32 => uint256) public bidIdToIndex;

    /// @dev Stores the bid ids by provider address => bidder address => bidId
    mapping(address => mapping(address => bytes32))
        public bidIdByProviderAndRequester;

    IRoyaltiesManager public royaltiesManager;

    uint256 public royaltiesCutPerMillion;

    /// @dev Announce when a bid is created in the marketplace.
    event BidCreated(
        bytes32 _id,
        address indexed _provider,
        address indexed _requester,
        address indexed _tokenAddress,
        uint256 _amount,
        uint256 _expires,
        bytes _fingerprint
    );

    /// @dev Announce when a bid is accepted in the marketplace.
    event BidAccepted(
        bytes32 _id,
        address indexed _tokenAddress,
        uint256 indexed _tokenId,
        address _bidder,
        address indexed _seller,
        uint256 _price,
        uint256 _fee
    );

    /// @dev Announce when a bid is cancelled.
    event BidCancelled(
        bytes32 _id,
        address indexed _tokenAddress,
        address indexed _bidder
    );

    /// @dev Announce when the owed royalties cut has been updated.
    event ChangedRoyaltiesCutPerMillion(uint256 _royaltiesCutPerMillion);

    /// @dev Announce when the logic of royalty management is updated.
    event RoyaltiesManagerSet(
        IRoyaltiesManager indexed _oldRoyaltiesManager,
        IRoyaltiesManager indexed _newRoyaltiesManager
    );

    constructor(
        IERC20 _paymentToken,
        IRoyaltiesManager _royaltiesManager,
        uint256 _royaltiesCutPerMillion,
        string memory _domainSeparatorName,
        string memory _chainId
    )
        Auth(msg.sender, Authority(address(0)))
        EIP712(_domainSeparatorName, _chainId)
        Pausable()
    {
        /// @dev Initialize the royalty engine.
        setRoyaltiesManager(_royaltiesManager);

        /// @dev Initialize the fee structure for jobs running inside the network.
        setRoyaltiesCutPerMillion(_royaltiesCutPerMillion);

        /// @dev Set the payment token that will be used to pay for the jobs.
        setPaymentToken(_paymentToken);
    }

    /**
     * @dev Allow marketplace admins to halt the marketplace.
     */
    function pause() public requiresAuth {
        _pause();
    }

    /**
     * @dev Allow marketplace admins to resume the marketplace.
     */
    function unpause() public requiresAuth {
        _unpause();
    }

    /**
     * @dev Sets the share cut for the royalties that's
     *  charged to the seller on a successful sale
     * @param _royaltiesCutPerMillion - fees for royalties
     */
    function setRoyaltiesCutPerMillion(uint256 _royaltiesCutPerMillion)
        public
        requiresAuth
    {
        royaltiesCutPerMillion = _royaltiesCutPerMillion;

        require(
            royaltiesCutPerMillion < 1000000,
            "ERC721Bid#setRoyaltiesCutPerMillion: TOTAL_FEES_MUST_BE_BETWEEN_0_AND_999999"
        );

        emit ChangedRoyaltiesCutPerMillion(royaltiesCutPerMillion);
    }

    /**
     * @notice Set the royalties manager
     * @param _newRoyaltiesManager - royalties manager
     */
    function setRoyaltiesManager(IRoyaltiesManager _newRoyaltiesManager)
        public
        requiresAuth
    {
        // require(
        //     address(_newRoyaltiesManager).isContract(),
        //     "ERC721Bid#setRoyaltiesManager: INVALID_ROYALTIES_MANAGER"
        // );

        emit RoyaltiesManagerSet(royaltiesManager, _newRoyaltiesManager);
        
        royaltiesManager = _newRoyaltiesManager;
    }

    /**
     * @notice Set the payment token
     * @param _newPaymentToken - payment token
     */
    function setPaymentToken(IERC20 _newPaymentToken) public requiresAuth {
        // require(
        //     address(_newPaymentToken).isContract(),
        //     "ERC721Bid#setPaymentToken: INVALID_PAYMENT_TOKEN"
        // );

        paymentToken = _newPaymentToken;
    }
}
