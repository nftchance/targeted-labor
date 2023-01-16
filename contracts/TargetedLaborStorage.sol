// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Auth, Authority} from "solmate/src/auth/Auth.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

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

contract TargetedLaborStorage is Auth, Pausable {
    // 182 days - 26 weeks - 6 months
    uint256 public constant MAX_BID_DURATION = 182 days;
    uint256 public constant MIN_BID_DURATION = 1 minutes;
    uint256 public constant ONE_MILLION = 1000000;

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

    address public feesCollector;
    IRoyaltiesManager public royaltiesManager;

    uint256 public feesCollectorCutPerMillion;
    uint256 public royaltiesCutPerMillion;

    // EVENTS
    event BidCreated(
        bytes32 _id,
        address indexed _provider,
        address indexed _requester,
        address indexed _tokenAddress,
        uint256 _amount,
        uint256 _expires,
        bytes _fingerprint
    );

    event BidAccepted(
        bytes32 _id,
        address indexed _tokenAddress,
        uint256 indexed _tokenId,
        address _bidder,
        address indexed _seller,
        uint256 _price,
        uint256 _fee
    );

    event BidCancelled(
        bytes32 _id,
        address indexed _tokenAddress,
        address indexed _bidder
    );

    event ChangedFeesCollectorCutPerMillion(
        uint256 _feesCollectorCutPerMillion
    );
    event ChangedRoyaltiesCutPerMillion(uint256 _royaltiesCutPerMillion);
    event FeesCollectorSet(
        address indexed _oldFeesCollector,
        address indexed _newFeesCollector
    );
    event RoyaltiesManagerSet(
        IRoyaltiesManager indexed _oldRoyaltiesManager,
        IRoyaltiesManager indexed _newRoyaltiesManager
    );

    constructor(
        address _feesCollector,
        IERC20 _paymentToken,
        IRoyaltiesManager _royaltiesManager,
        uint256 _feesCollectorCutPerMillion,
        uint256 _royaltiesCutPerMillion
    ) Auth(msg.sender, Authority(address(0))) Pausable() {
        /// @dev Connect the addresses that will be used to collect fees and royalties.
        setFeesCollector(_feesCollector);
        setRoyaltiesManager(_royaltiesManager);

        /// @dev Initialize the fee structure for jobs running inside the network.
        setFeesCollectorCutPerMillion(_feesCollectorCutPerMillion);
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
     * @dev Sets the share cut for the fees collector of the contract that's
     *  charged to the seller on a successful sale
     * @param _feesCollectorCutPerMillion - fees for the collector
     */
    function setFeesCollectorCutPerMillion(uint256 _feesCollectorCutPerMillion)
        public
        requiresAuth
    {
        feesCollectorCutPerMillion = _feesCollectorCutPerMillion;

        require(
            feesCollectorCutPerMillion + royaltiesCutPerMillion < 1000000,
            "ERC721Bid#setFeesCollectorCutPerMillion: TOTAL_FEES_MUST_BE_BETWEEN_0_AND_999999"
        );

        emit ChangedFeesCollectorCutPerMillion(feesCollectorCutPerMillion);
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
            feesCollectorCutPerMillion + royaltiesCutPerMillion < 1000000,
            "ERC721Bid#setRoyaltiesCutPerMillion: TOTAL_FEES_MUST_BE_BETWEEN_0_AND_999999"
        );

        emit ChangedRoyaltiesCutPerMillion(royaltiesCutPerMillion);
    }

    /**
     * @notice Set the fees collector
     * @param _newFeesCollector - fees collector
     */
    function setFeesCollector(address _newFeesCollector) public requiresAuth {
        require(
            _newFeesCollector != address(0),
            "ERC721Bid#setFeesCollector: INVALID_FEES_COLLECTOR"
        );

        emit FeesCollectorSet(feesCollector, _newFeesCollector);
        feesCollector = _newFeesCollector;
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
