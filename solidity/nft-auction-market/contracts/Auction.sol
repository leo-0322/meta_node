// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Auction is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721Receiver
{
    address public seller;
    IERC721 public nft;
    IERC20 public payToken;
    uint256 public tokenId;
    uint256 public startPrice;
    uint256 public startTime;
    uint256 public endTime;

    address public highestBidder;
    uint256 public highestBid;

    bool public settled;
    bool public canceled;

    event BidPlaced(address indexed bidder, uint256 amount);
    event AuctionCanceled();
    event AuctionSettled(address indexed winner, uint256 amount);

    error InvalidSeller(address seller);
    error InvalidOwner(address owner);
    error NotSeller(address sender, address seller);
    error InvalidBidder(address bidder);
    error LessThanStartPrice(uint256 bid, uint256 startPrice);
    error LessThanHighestBid(uint256 bid, uint256 highestBid);
    error AuctionNotStart(uint256 curTime, uint256 startTime);
    error AuctionAlreadyEnd(uint256 curTime, uint256 endTime);
    error AuctionAlreadySettled();
    error AuctionAlreadyCanceled();
    /**
     * 还在拍卖中
     */
    error AuctionBidding();
    error PayNotWithETH(address pay);
    error PayNotWithERC20(address pay);
    error RefundETHFailed(address to, uint256 amount);
    error RefundERC20Failed(address payToken, address to, uint256 amount);
    error InsufficientBalance(uint256 balance, uint256 bidAmount);
    error InsufficientAllowance(uint256 allowance, uint256 bidAmount);
    error BidERC20Failed(address token, address from, uint256 amount);
    error TransferToSellerFailed(
        address payToken,
        address seller,
        uint256 amount
    );

    modifier onlySeller() {
        if (msg.sender != seller) {
            revert NotSeller(msg.sender, seller);
        }
        _;
    }

    modifier auctionActive() {
        if (block.timestamp < startTime) {
            revert AuctionNotStart(block.timestamp, startTime);
        }

        if (block.timestamp > endTime) {
            revert AuctionAlreadyEnd(block.timestamp, endTime);
        }

        if (settled) {
            revert AuctionAlreadySettled();
        }

        if (canceled) {
            revert AuctionAlreadyCanceled();
        }
        _;
    }

    modifier validBid(uint256 bid_) {
        if (msg.sender == address(0)) {
            revert InvalidBidder(msg.sender);
        }

        if (bid_ <= startPrice) {
            revert LessThanStartPrice(bid_, startPrice);
        }

        if (bid_ <= highestBid) {
            revert LessThanHighestBid(bid_, highestBid);
        }
        _;
    }

    function initialize(
        address seller_,
        IERC721 nft_,
        uint256 tokenId_,
        IERC20 payToken_,
        uint256 startPrice_,
        uint256 startTime_,
        uint256 endTime_,
        address owner_
    ) external initializer {
        if (seller_ == address(0)) {
            revert InvalidSeller(seller_);
        }

        if (owner_ == address(0)) {
            revert InvalidOwner(owner_);
        }

        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        seller = seller_;
        nft = nft_;
        payToken = payToken_;
        tokenId = tokenId_;
        startPrice = startPrice_;
        startTime = startTime_;
        endTime = endTime_;
    }

    function bid()
        external
        payable
        nonReentrant
        auctionActive
        validBid(msg.value)
    {
        if (address(payToken) != address(0)) {
            revert PayNotWithETH(address(payToken));
        }
        _refund();
        highestBidder = msg.sender;
        highestBid = msg.value;
        emit BidPlaced(msg.sender, msg.value);
    }

    function bidERC20(
        uint256 amount
    ) external nonReentrant auctionActive validBid(amount) {
        if (address(payToken) == address(0)) {
            revert PayNotWithERC20(address(payToken));
        }
        uint256 balance = payToken.balanceOf(msg.sender);
        if (balance < amount) {
            revert InsufficientBalance(balance, amount);
        }

        uint256 allowance = payToken.allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert InsufficientAllowance(allowance, amount);
        }

        bool ok = payToken.transferFrom(msg.sender, address(this), amount);
        if (!ok) {
            revert BidERC20Failed(address(payToken), msg.sender, amount);
        }
        _refund();
        highestBidder = msg.sender;
        highestBid = amount;
        emit BidPlaced(msg.sender, amount);
    }

    function settle() external onlyOwner nonReentrant {
        if (settled) {
            revert AuctionAlreadySettled();
        }

        if (canceled) {
            revert AuctionAlreadyCanceled();
        }

        if (block.timestamp < endTime) {
            revert AuctionBidding();
        }
        settled = true;
        if (highestBidder == address(0)) {
            nft.safeTransferFrom(address(this), seller, tokenId);
            emit AuctionSettled(address(0), 0);
            return;
        }
        nft.safeTransferFrom(address(this), highestBidder, tokenId);
        if (address(payToken) == address(0)) {
            (bool ok, ) = payable(seller).call{value: highestBid}("");
            if (!ok) {
                revert TransferToSellerFailed(address(0), seller, highestBid);
            }
        } else {
            bool ok = payToken.transfer(seller, highestBid);
            if (!ok) {
                revert TransferToSellerFailed(
                    address(payToken),
                    seller,
                    highestBid
                );
            }
        }
        emit AuctionSettled(highestBidder, highestBid);
    }

    function cancel() external onlySeller nonReentrant {
        if (settled) {
            revert AuctionAlreadySettled();
        }

        if (canceled) {
            revert AuctionAlreadyCanceled();
        }

        if (highestBidder != address(0)) {
            revert AuctionBidding();
        }

        canceled = true;
        nft.safeTransferFrom(address(this), seller, tokenId);
        emit AuctionCanceled();
    }

    function _refund() internal {
        if (highestBidder == address(0)) {
            return;
        }

        if (address(payToken) == address(0)) {
            (bool ok, ) = payable(highestBidder).call{value: highestBid}("");
            if (!ok) {
                revert RefundETHFailed(highestBidder, highestBid);
            }
        } else {
            bool ok = payToken.transfer(highestBidder, highestBid);
            if (!ok) {
                revert RefundERC20Failed(
                    address(payToken),
                    highestBidder,
                    highestBid
                );
            }
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
