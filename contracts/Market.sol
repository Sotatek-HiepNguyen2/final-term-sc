// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

// Allow user to list NFT contract for sale
// NFT follows ERC721 or ERC1155 standard
// Auction are supported, but not required
// User can buy NFT with ERC20 token or ETH
contract Marketplace {
    // NFT contract address
    address public nftAddress;

    // NFT ID
    uint256 public nftId;

    // Price of NFT
    uint256 public price;

    // Owner of NFT
    address public owner;

    // Buyer of NFT
    address public buyer;

    // ERC20 token address
    address public tokenAddress;

    // Auction start time
    uint256 public auctionStartTime;

    // Auction end time
    uint256 public auctionEndTime;

    // Auction minimum price
    uint256 public auctionMinPrice;

    // Auction highest bid
    uint256 public auctionHighestBid;

    // Auction highest bidder
    address public auctionHighestBidder;

    // Auction ended
    bool public auctionEnded;

    // Event emitted when NFT is listed for sale
    event NFTListed(uint256 nftId, uint256 price, address owner);

    // Event emitted when NFT is bought
    event NFTBought(uint256 nftId, uint256 price, address owner, address buyer);

    // Event emitted when NFT is listed for auction
    event NFTAuctionListed(uint256 nftId, uint256 startTime, uint256 endTime, uint256 minPrice, address owner);

    // Event emitted when NFT is bid
    event NFTBid(uint256 nftId, uint256 price, address bidder);

    // Event emitted when NFT auction is ended
    event NFTAuctionEnded(uint256 nftId, uint256 price, address owner, address buyer);

    // Event emitted when NFT is withdrawn
    event NFTWithdrawn(uint256 nftId, address owner);

    // Event emitted when ERC20 token is withdrawn
    event TokenWithdrawn(uint256 amount, address owner);

    // Event emitted when ERC20 token is deposited
    event TokenDeposited(uint256 amount, address owner);

    // Event emitted when ERC20 token is transferred
    event TokenTransferred(uint256 amount, address from, address to);

    // Event emitted when ERC20 token is approved
    event TokenApproved(uint256 amount, address owner, address spender);

    // Event emitted when ERC20 token is spent
    event TokenSpent(uint256 amount, address owner, address spender);

    // Event emitted when ERC20 token is burned
    event TokenBurned(uint256 amount, address owner);

    function listItem(uint256 _nftId, uint256 _price) public {
        nftId = _nftId;
        price = _price;
        owner = msg.sender;

        emit NFTListed(nftId, price, owner);
    }

    function cancelListing() public {}

    function buyItem(uint256 _nftId) public {
        nftId = _nftId;
        buyer = msg.sender;

        emit NFTBought(nftId, price, owner, buyer);
    }

    function listAuction(uint256 _nftId, uint256 _startTime, uint256 _endTime, uint256 _minPrice) public {
        nftId = _nftId;
        auctionStartTime = _startTime;
        auctionEndTime = _endTime;
        auctionMinPrice = _minPrice;
        owner = msg.sender;

        emit NFTAuctionListed(nftId, auctionStartTime, auctionEndTime, auctionMinPrice, owner);
    }

    function withdrawProceeds() public {}
}
