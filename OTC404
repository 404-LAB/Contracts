// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract OTC404 {

    address public owner;
    uint256 public offerCount;
    uint256 public orderCount;
    bool private locked;
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => Order) public orders;

    struct Offer {
        address seller;
        address token;
        uint256 tokenAmount;
        uint256 remainingAmount;
        uint256 priceInWei;
        bool isAvailable;
    }

    struct Order {
        address buyer;
        address token;
        uint256 tokenAmount;
        uint256 remainingAmount;
        uint256 priceInWei;
        bool isAvailable;
    }

    event OfferCreated(uint256 indexed offerId, address indexed seller, address token, uint256 tokenAmount, uint256 priceInWei);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, address token, uint256 tokenAmount, uint256 priceInWei);
    event TradeExecuted(uint256 indexed offerId, uint256 indexed orderId, address buyer, uint256 tradeAmount, uint256 tradeValue);
    event OfferCancelled(uint256 indexed offerId);
    event OrderCancelled(uint256 indexed orderId);

    modifier noReentrancy() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        locked = false;
    }

    function createOffer(address _token, uint256 _tokenAmount, uint256 _priceInWei) external {
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_priceInWei > 0, "Price must be greater than 0");

        offerCount++;
        offers[offerCount] = Offer(msg.sender, _token, _tokenAmount, _tokenAmount, _priceInWei, true);

        emit OfferCreated(offerCount, msg.sender, _token, _tokenAmount, _priceInWei);
    }

    function createOrder(address _token, uint256 _tokenAmount, uint256 _priceInWei) external payable {
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_priceInWei * _tokenAmount == msg.value, "Incorrect value");

        orderCount++;
        orders[orderCount] = Order(msg.sender, _token, _tokenAmount, _tokenAmount, _priceInWei, true);

        emit OrderCreated(orderCount, msg.sender, _token, _tokenAmount, _priceInWei);
    }

   
    function fillOffer(uint256 _offerId, uint256 _amount) external payable noReentrancy {
        Offer storage offer = offers[_offerId];
        require(offer.isAvailable, "Offer not available");
        require(offer.remainingAmount >= _amount, "Not enough tokens in the offer");
        require(offer.priceInWei * _amount == msg.value, "Incorrect value");

        // Improved error handling
        bool success = IERC20(offer.token).transferFrom(offer.seller, msg.sender, _amount);
        require(success, "Token transfer failed");

        offer.remainingAmount -= _amount;
        if (offer.remainingAmount == 0) {
            offer.isAvailable = false;
        }

        payable(offer.seller).transfer(msg.value);
        emit TradeExecuted(_offerId, 0, msg.sender, _amount, msg.value);
    }

    function fillOrder(uint256 _orderId, uint256 _amount) external noReentrancy {
        Order storage order = orders[_orderId];
        require(order.isAvailable, "Order not available");
        require(order.remainingAmount >= _amount, "Not enough tokens requested in the order");

        uint256 tradeValue = order.priceInWei * _amount;
        require(IERC20(order.token).transferFrom(msg.sender, order.buyer, _amount), "Transfer failed");

        order.remainingAmount -= _amount;
        if (order.remainingAmount == 0) {
            order.isAvailable = false;
        }

        payable(msg.sender).transfer(tradeValue);

        emit TradeExecuted(0, _orderId, order.buyer, _amount, tradeValue);
    }

    function cancelOffer(uint256 _offerId) external noReentrancy {
        Offer storage offer = offers[_offerId];
        require(msg.sender == offer.seller, "Not the seller");
        offer.isAvailable = false;
        emit OfferCancelled(_offerId);
    }

    function cancelOrder(uint256 _orderId) external noReentrancy {
        Order storage order = orders[_orderId];
        require(msg.sender == order.buyer, "Not the buyer");
        order.isAvailable = false;
        if (order.remainingAmount > 0) {
            uint256 refundAmount = order.priceInWei * order.remainingAmount;
            payable(order.buyer).transfer(refundAmount);
        }
        emit OrderCancelled(_orderId);
    }
}
