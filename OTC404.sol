// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IERC20
 * @dev Interface for the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title OTC404
 * @dev Implements an over-the-counter (OTC) trading contract for direct trades between users for ERC20 tokens.
 */
contract OTC404 {

    address public owner; // Owner of the contract.
    uint256 public offerCount; // Total number of offers created.
    uint256 public orderCount; // Total number of orders created.
    bool private locked; // Reentrancy guard state variable.
    mapping(uint256 => Offer) public offers; // Mapping of offer IDs to their corresponding offers.
    mapping(uint256 => Order) public orders; // Mapping of order IDs to their corresponding orders.

    /**
     * @dev Struct to represent an offer to sell tokens.
     */
    struct Offer {
        address seller; // Address of the seller.
        address token; // Address of the ERC20 token being sold.
        uint256 tokenAmount; // Amount of tokens being sold.
        uint256 remainingAmount; // Remaining amount of tokens available for sale.
        uint256 priceInWei; // Price per token in Wei.
        bool isAvailable; // Flag to check if the offer is still available.
    }

    /**
     * @dev Struct to represent an order to buy tokens.
     */
    struct Order {
        address buyer; // Address of the buyer.
        address token; // Address of the ERC20 token being bought.
        uint256 tokenAmount; // Amount of tokens being bought.
        uint256 remainingAmount; // Remaining amount of tokens available to buy.
        uint256 priceInWei; // Price per token in Wei.
        bool isAvailable; // Flag to check if the order is still available.
    }

    // Events
    event OfferCreated(uint256 indexed offerId, address indexed seller, address token, uint256 tokenAmount, uint256 priceInWei);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address token, uint256 tokenAmount, uint256 priceInWei);
    event TradeExecuted(uint256 indexed offerId, uint256 indexed orderId, address buyer, uint256 tradeAmount, uint256 tradeValue);
    event OfferCancelled(uint256 indexed offerId);
    event OrderCancelled(uint256 indexed orderId);

    // Modifiers
    modifier noReentrancy() {
        require(!locked, "[404Lab] : Reentrancy Guard, operation not permitted");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "[404Lab] : Caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        locked = false;
    }

    /**
     * @dev Creates a new offer for selling tokens.
     * @param _token Address of the ERC20 token being sold.
     * @param _tokenAmount Amount of tokens being sold.
     * @param _priceInWei Price per token in Wei.
     */
    function createOffer(address _token, uint256 _tokenAmount, uint256 _priceInWei) external {
        require(_tokenAmount > 0, "[404Lab] :Token amount must be greater than 0");
        require(_priceInWei > 0, "[404Lab] : Price must be greater than 0");

        offerCount++;
        offers[offerCount] = Offer(msg.sender, _token, _tokenAmount, _tokenAmount, _priceInWei, true);

        emit OfferCreated(offerCount, msg.sender, _token, _tokenAmount, _priceInWei);
    }

    /**
     * @dev Creates a new order for buying tokens.
     * @param _token Address of the ERC20 token being bought.
     * @param _tokenAmount Amount of tokens being bought.
     * @param _priceInWei Price per token in Wei.
     */
    function createOrder(address _token, uint256 _tokenAmount, uint256 _priceInWei) external payable {
        require(_tokenAmount > 0, "[404Lab] : Token amount must be greater than 0");
        require(_priceInWei * _tokenAmount == msg.value, "[404Lab] : Incorrect value");

        orderCount++;
        orders[orderCount] = Order(msg.sender, _token, _tokenAmount, _tokenAmount, _priceInWei, true);

        emit OrderCreated(orderCount, msg.sender, _token, _tokenAmount, _priceInWei);
    }

    /**
     * @dev Fills an existing offer by purchasing tokens.
     * @param _offerId ID of the offer being filled.
     * @param _amount Amount of tokens to purchase.
     */
    function fillOffer(uint256 _offerId, uint256 _amount) external payable noReentrancy {
        Offer storage offer = offers[_offerId];
        require(offer.isAvailable, "[404Lab] : Offer not available");
        require(offer.remainingAmount >= _amount, "[404Lab] : Not enough tokens in the offer");
        require(offer.priceInWei * _amount == msg.value, "[404Lab] : Incorrect value");

        bool success = IERC20(offer.token).transferFrom(offer.seller, msg.sender, _amount);
        require(success, "[404Lab] : Token transfer failed");

        offer.remainingAmount -= _amount;
        if (offer.remainingAmount == 0) {
            offer.isAvailable = false;
        }

        payable(offer.seller).transfer(msg.value);
        emit TradeExecuted(_offerId, 0, msg.sender, _amount, msg.value);
    }

    /**
     * @dev Fills an existing order by selling tokens to the buyer.
     * @param _orderId ID of the order being filled.
     * @param _amount Amount of tokens to sell.
     */
    function fillOrder(uint256 _orderId, uint256 _amount) external noReentrancy {
        Order storage order = orders[_orderId];
        require(order.isAvailable, "[404Lab] : Order not available");
        require(order.remainingAmount >= _amount, "[404Lab] : Not enough tokens requested in the order");

        uint256 tradeValue = order.priceInWei * _amount;
        require(IERC20(order.token).transferFrom(msg.sender, order.buyer, _amount), "[404Lab] : Transfer failed");

        order.remainingAmount -= _amount;
        if (order.remainingAmount == 0) {
            order.isAvailable = false;
        }

        payable(msg.sender).transfer(tradeValue);

        emit TradeExecuted(0, _orderId, order.buyer, _amount, tradeValue);
    }

    /**
     * @dev Cancels an existing offer, making it no longer available.
     * @param _offerId ID of the offer to cancel.
     */
    function cancelOffer(uint256 _offerId) external noReentrancy {
        Offer storage offer = offers[_offerId];
        require(msg.sender == offer.seller, "[404Lab] : Not the seller");
        offer.isAvailable = false;
        emit OfferCancelled(_offerId);
    }

    /**
     * @dev Cancels an existing order, refunding the remaining amount to the buyer if necessary.
     * @param _orderId ID of the order to cancel.
     */
    function cancelOrder(uint256 _orderId) external noReentrancy {
        Order storage order = orders[_orderId];
        require(msg.sender == order.buyer, "[404Lab] : Not the buyer");
        order.isAvailable = false;
        if (order.remainingAmount > 0) {
            uint256 refundAmount = order.priceInWei * order.remainingAmount;
            payable(order.buyer).transfer(refundAmount);
        }
        emit OrderCancelled(_orderId);
    }
}
