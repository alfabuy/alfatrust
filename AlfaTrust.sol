// Copyright (c) 2024 AlfaBuy Corp.
// All rights reserved.
// Unauthorized use, modification, or distribution of this software is strictly prohibited.

// Specify the version of Solidity, the compiler to use
pragma solidity ^0.8.24;

// Importing from OpenZeppelin's library for reentrancy guard and safe ERC20 operations
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Enable the use of SafeERC20 library for IERC20 interface
using SafeERC20 for IERC20;

// AlfaTrust is a contract that manages secure transactions between parties with arbitration
contract AlfaTrust is ReentrancyGuard {
    // Tokens and arbiter are immutable after contract deployment, meaning they cannot be changed
    IERC20 public immutable usdtToken;
    IERC20 public immutable usdcToken;
    address public immutable arbiter;

    // Fee percentage for arbiter and counters for accumulated fees and total deals
    uint256 private arbiterFeePercent = 2;
    uint256 private arbiterFeesAccumulatedUsdt = 0;
    uint256 private arbiterFeesAccumulatedUsdc = 0;
    uint256 private dealCounter = 0;

    // Deal struct to hold the details of each transaction
    struct Deal {
        uint96 amount;
        address buyer;
        address seller;
        DealStatus status;
        RefundStatus refundStatus;
        Token token;
    }

    // Enums to define possible states of tokens, deals, and refunds
    enum Token { usdt, usdc }
    enum DealStatus { Pending, Completed, Refunded }
    enum RefundStatus { NoRefundAllowed, RefundToBuyerAllowed, RefundToSellerAllowed, RefundToBuyerExecuted, RefundToSellerExecuted }

    // Mapping to keep track of all deals by their IDs
    mapping(uint256 => Deal) private deals;

    // Events to log activities on the blockchain
    event DealCreated(uint256 dealId, address buyer, address seller, uint256 amount);
    event DealPaymentCompleted(uint256 dealId, uint256 payoutAmount, address toAddress);
    event SellerRefundApproved(uint256 dealId, uint256 refundAmount);
    event BuyerRefundApproved(uint256 dealId, uint256 refundAmount);
    event DealRefundIssued(uint256 dealId, uint256 refundAmount, address toAddress);
    event ArbitrationFeeWithdrawn(address arbiter, uint256 feeAmount);
    event ArbitrationFeeRateUpdated(uint256 newFeePercent);

    // Custom errors to provide detailed exceptions
    error ArbiterOnly();
    error BuyerOnly();
    error UnauthorizedParticipant();
    error DealDoesNotExist();
    error InvalidDealState();
    error ZeroSellerAddress();
    error NoSelfDealingAllowed();
    error UnsupportedToken();
    error RefundNotAllowed();
    error NoRefundAuthorized();
    error RefundRecipientMissing();
    error NoArbitrationFees();
    error FeeIsTooHigh();

    // Constructor to set up tokens and arbiter upon deployment
    constructor(IERC20 _usdtToken, IERC20 _usdcToken, address _arbiter) {
        usdtToken = _usdtToken;
        usdcToken = _usdcToken;
        arbiter = _arbiter;
    }
    
    // Modifiers to restrict function execution to specific roles
    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert ArbiterOnly();
        _;
    }

    modifier onlyBuyer(uint256 dealId) {
        if (msg.sender != deals[dealId].buyer) revert BuyerOnly();
        _;
    }

    modifier onlyDealParticipant(uint256 dealId) {
        if (msg.sender != deals[dealId].buyer && msg.sender != deals[dealId].seller && msg.sender != arbiter) 
            revert UnauthorizedParticipant();
        _;
    }

    // Function to get the current status of a deal by its ID
    function getDealStatus(uint256 dealId) external view returns (DealStatus) {
        // Retrieve the deal from storage
        Deal memory deal = deals[dealId];
        // If the deal does not exist (buyer address is default), revert with an error
        if (deal.buyer == address(0)) revert DealDoesNotExist();
        // Return the current status of the deal
        return deal.status;
    }

    // Function to get the refund status of a deal by its ID
    function getRefundStatus(uint256 dealId) external view returns (RefundStatus) {
        // Retrieve the deal from storage
        Deal memory deal = deals[dealId];
        // Return the current refund status of the deal
        return deal.refundStatus;
    }

    // Function to get the current fee rate for the arbiter
    function getFeeRate() external view returns (uint256) {
        // Return the current arbiter fee percent
        return arbiterFeePercent;
    }

    // Internal function to transfer tokens from one address to the contract
    function _transferToken(Token token, address from, uint96 amount) internal {
        // Transfer the specified amount of USDT or USDC from the sender to this contract
        if (token == Token.usdt) {
            usdtToken.safeTransferFrom(from, address(this), amount);
        } else if (token == Token.usdc) {
            usdcToken.safeTransferFrom(from, address(this), amount);
        } else {
            // If the token type is unsupported, revert the transaction
            revert UnsupportedToken();
        }
    }

    // Function to create a new deal between a buyer and a seller
    function createDeal(Token token, address seller, uint96 amount) external {
        // The buyer is the sender of the transaction
        address buyer = msg.sender;
        // Revert if the seller address is not specified
        if (seller == address(0)) revert ZeroSellerAddress();
        // Revert if the buyer and seller are the same address
        if (buyer == seller) revert NoSelfDealingAllowed();

        // Transfer the specified token from the buyer to this contract
        _transferToken(token, buyer, amount);

        // Increment the deal counter and create a new deal
        uint256 dealId = ++dealCounter;
        deals[dealId] = Deal(amount, buyer, seller, DealStatus.Pending, RefundStatus.NoRefundAllowed, token);
        // Emit an event to log the deal creation
        emit DealCreated(dealId, buyer, seller, uint256(amount));
    }

    // Function to complete a deal, transferring funds to the seller and fees to the arbiter
    function completeDeal(uint256 dealId) external nonReentrant onlyBuyer(dealId) {
        // Retrieve the deal from storage
        Deal storage deal = deals[dealId];
        // Revert if the deal is not in a pending state
        if (deal.status != DealStatus.Pending) revert InvalidDealState();

        // Calculate the arbiter's fee and the payout amount for the seller
        uint256 arbiterFee = (uint256(deal.amount) * arbiterFeePercent) / 100;
        uint256 payoutAmount = uint256(deal.amount) - arbiterFee;

        // Transfer the payout amount to the seller and accumulate the arbiter's fee
        if (deal.token == Token.usdt) {
            usdtToken.safeTransfer(deal.seller, payoutAmount);
            arbiterFeesAccumulatedUsdt += arbiterFee;
        } else {
            usdcToken.safeTransfer(deal.seller, payoutAmount);
            arbiterFeesAccumulatedUsdc += arbiterFee;
        }
        // Update the deal status to completed
        deal.status = DealStatus.Completed;
        // Emit an event to log the payment completion
        emit DealPaymentCompleted(dealId, payoutAmount, deal.seller);
    }

    // Function to allow the arbiter to approve a refund to the buyer
    function approveRefundForBuyer(uint256 dealId) external onlyArbiter {
        // Retrieve the deal from storage
        Deal storage deal = deals[dealId];
        // Revert if the deal is not pending or if refunds are not allowed
        if (deal.status != DealStatus.Pending || deal.refundStatus != RefundStatus.NoRefundAllowed) revert RefundNotAllowed();
        // Update the refund status to allow refund to the buyer
        deal.refundStatus = RefundStatus.RefundToBuyerAllowed;
        // Emit an event to log the buyer refund approval
        emit BuyerRefundApproved(dealId, uint256(deal.amount));
    }

    // Function to allow the arbiter to approve a refund to the seller
    function approveRefundForSeller(uint256 dealId) external onlyArbiter {
        // Retrieve the deal from storage
        Deal storage deal = deals[dealId];
        // Revert if the deal is not pending or if refunds are not allowed
        if (deal.status != DealStatus.Pending || deal.refundStatus != RefundStatus.NoRefundAllowed) revert RefundNotAllowed();
        // Update the refund status to allow refund to the seller
        deal.refundStatus = RefundStatus.RefundToSellerAllowed;
        // Emit an event to log the seller refund approval
        emit SellerRefundApproved(dealId, uint256(deal.amount));
    }

    // Function to issue a refund based on the current refund status of the deal
    function refund(uint256 dealId) external nonReentrant onlyDealParticipant(dealId) {
        // Retrieve the deal from storage
        Deal storage deal = deals[dealId];
        // Revert if the deal is not in a pending state
        if (deal.status != DealStatus.Pending) revert RefundNotAllowed();
        address refundRecipient;
        // Calculate the arbiter's fee and the refund amount
        uint256 arbiterFee = (uint256(deal.amount) * arbiterFeePercent) / 100;
        uint256 refundAmount = uint256(deal.amount) - arbiterFee;

        // Determine the recipient of the refund based on the refund status
        if (deal.refundStatus == RefundStatus.RefundToBuyerAllowed) {
            refundRecipient = deal.buyer;
        } else if (deal.refundStatus == RefundStatus.RefundToSellerAllowed) {
            refundRecipient = deal.seller;
        } else {
            revert NoRefundAuthorized();
        }
        // Revert if the recipient address is not valid
        if (refundRecipient ==  address(0)) revert RefundRecipientMissing();

        // Transfer the refund amount to the recipient and accumulate the arbiter's fee
        if (deal.token == Token.usdt) {
            usdtToken.safeTransfer(refundRecipient, refundAmount);
            arbiterFeesAccumulatedUsdt += arbiterFee;
        } else {
            usdcToken.safeTransfer(refundRecipient, refundAmount);
            arbiterFeesAccumulatedUsdc += arbiterFee;
        }

        // Update the deal and refund statuses
        deal.status = DealStatus.Refunded;
        deal.refundStatus = refundRecipient == deal.buyer ? RefundStatus.RefundToBuyerExecuted : RefundStatus.RefundToSellerExecuted;

        // Emit an event to log the refund issuance
        emit DealRefundIssued(dealId, refundAmount, refundRecipient);
    }

    // Function for the arbiter to withdraw accumulated fees
    function withdrawArbiterFees(Token token) external nonReentrant onlyArbiter {
        uint256 feeAmount = 0;
        // Determine the fee amount based on the token type
        if (token == Token.usdt) {
            feeAmount = arbiterFeesAccumulatedUsdt;
            if (feeAmount < 1) revert NoArbitrationFees();
            usdtToken.safeTransfer(arbiter, feeAmount);
            arbiterFeesAccumulatedUsdt = 0;
        } else if (token == Token.usdc) {
            feeAmount = arbiterFeesAccumulatedUsdc;
            if (feeAmount < 1) revert NoArbitrationFees();
            usdcToken.safeTransfer(arbiter, feeAmount);
            arbiterFeesAccumulatedUsdc = 0;
        } else {
            revert UnsupportedToken();
        }

        // Emit an event to log the fee withdrawal
        emit ArbitrationFeeWithdrawn(arbiter, feeAmount);
    }

    // Function to update the arbiter's fee percentage
    function setArbiterFeePercent(uint256 newFeePercent) external onlyArbiter {
        // Revert if the new fee percentage is greater than 10%
        if (newFeePercent > 10) revert FeeIsTooHigh();
        // Update the arbiter fee percent
        arbiterFeePercent = newFeePercent;
        // Emit an event to log the fee rate update
        emit ArbitrationFeeRateUpdated(newFeePercent);
    }

}
