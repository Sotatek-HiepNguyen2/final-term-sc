// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error ItemNotForSale(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NoProceeds();
error NotOwner();
error NotApprovedForMarketplace();
error PriceMustBeAboveZero();
error UserAlreadyNotBanned(address user);
error UserBanned(address user);

error InvalidQuantity(uint256 quantity);
error InvalidPrice(uint256 price);

address constant ETH = address(0);

contract Marketplace is Ownable, ReentrancyGuard {
    constructor(address _owner) Ownable(_owner) {}

    struct Listing {
        uint256 price;
        address paymentToken;
        address seller;
    }

    struct Auction {
        address seller;
        address priceToken;
        uint256 floorPrice;
        uint256 endAuction;
        uint256 bidCount;
        uint256 currentBidPrice;
        address payable currentBidOwner;
    }

    // NFTCollection => TokenID => Listing/Auction
    mapping(address => mapping(uint256 => Listing)) private derectSale;
    mapping(address => mapping(uint256 => Auction)) private auctions;

    // Seller => token => amount
    mapping(address => mapping(address => uint256)) private sellerProceeds;

    // =============================== //

    mapping(address => bool) blackList;

    function banUser(address _user) external onlyOwner {
        blackList[_user] = true;
    }

    function unbanUser(address _user) external onlyOwner {
        require(blackList[_user] == true, UserAlreadyNotBanned(_user));
        delete blackList[_user];
    }

    modifier whiteListOnly() {
        require(blackList[msg.sender] != true, UserBanned(msg.sender));
        _;
    }

    // ====================== //

    event NewAuctionListed();
    event NewBidPlaced();

    event ItemListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);

    event ItemCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);

    event ItemBought(address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price);

    // ================ Function modifiers ================== //
    modifier notListed(address _nftAddress, uint256 _tokenId) {
        Listing memory listing = directListings[nftAddress][tokenId];
        Auction memory aution = auctions[nftAddress][tokenId];

        if (listing.price > 0 && auction.floorPrice > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier nftOwnerOnly(
        address spender,
        address nftAddress,
        uint256 tokenId,
        NFTType nftType
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NotOwner();
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = directListings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }

    function createAuction(
        address nftAddress,
        uint256 tokenId,
        uint256 floorPrice,
        address priceToken,
        uint256 endAuction
    ) external {
        IERC721(nftAddress).approve(address(this), tokenId);

        auctions[auctionId] = Auction(
            msg.sender,
            nftAddress,
            tokenId,
            floorPrice,
            priceToken,
            0,
            payable(address(0)),
            endAuction,
            0
        );
        auctionId++;

        emit NewAuctionListed();
    }

    function placeNewBid(uint256 _auctionId, uint256 _newBid) external payable {
        Auction storage auction = auctions[_auctionId];

        // Need to send token/coin to market contract
        if (auction.priceToken == address(0)) {
            // TODO: need change
            require(msg.value >= auction.currentBidPrice);
            return;
        }

        IERC20 paymentToken = IERC20(auction.priceToken);

        //
        paymentToken.transferFrom(msg.sender, address(this), _newBid);

        if (auction.bidCount > 0) {
            paymentToken.transfer(auction.currentBidOwner, auction.currentBidPrice);
        }

        auction.currentBidPrice = _newBid;
        auction.currentBidOwner = payable(msg.sender);
        auction.bidCount++;

        emit NewBidPlaced();
    }

    function withdrawNft(uint256 _auctionId) external {
        // Require exist auction
        // Require auction end
        // Require: winner

        Auction memory auction = auctions[_auctionId];

        address nftAddress = auction.nft;
        delete (auctions[_auctionId]);
        IERC721(nftAddress).safeTransferFrom(auction.seller, msg.sender, auction.tokenId);
    }

    function withdrawProceeds(address[] memory tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            address withdrawalToken = tokens[i];
            uint256 proceeds = sellerProceeds[msg.sender][withdrawalToken];

            if (proceeds > 0) {
                uint256 tempProceeds = proceeds;
                sellerProceeds[msg.sender][withdrawalToken] = 0;

                // ETH
                if (withdrawalToken == address(0)) {
                    (bool success, ) = payable(msg.sender).call{ value: tempProceeds }("");
                    require(success, "Transfer failed");
                    break;
                }

                IERC20 _withdrawalToken = IERC20(withdrawalToken);
                require(_withdrawalToken.transfer(msg.sender, proceeds), "Transfer failed");
            }
        }
    }

    function isOpen(uint256 _auctionId) public view returns (bool) {
        Auction storage auction = auctions[_auctionId];
        if (block.timestamp >= auction.endAuction) return false;
        return true;
    }

    function getCurrentBid(uint256 _auctionId) public view returns (address, uint256) {
        require(auctions[_auctionId].seller != address(0), "Invalid auction index");
        return (auctions[_auctionId].currentBidOwner, auctions[_auctionId].currentBidPrice);
    }

    // ======= Direct list for sale ======== //

    function listItemForDirectSale(
        bool _isERC1155,
        address _paymentToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _erc1155Quantity,
        uint256 _price
    ) external whiteListOnly nftOwnerOnly(_nftAddress, _tokenId, msg.sender) notListed {
        require(_price > 0, PriceMustBeAboveZero());

        Listing memory listing = directListings[_nftAddress][_tokenId];
        if (listing.price > 0) {
            revert AlreadyListed(_nftAddress, _tokenId);
        }

        if (_isERC1155) {
            listErc1155ForDirectSale(_nftAddress, _paymentToken, _tokenId, _erc1155Quantity, _price);
        } else {
            listErc721ForDirectSale(_nftAddress, _paymentToken, _tokenId, _price);
        }

        directListings[_nftAddress][_tokenId] = Listing(_price, _paymentToken, msg.sender);
        emit ItemListed(msg.sender, _nftAddress, _tokenId, _price);
    }

    function listErc1155ForDirectSale(
        address _nftAddress,
        address _paymentToken,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price
    ) private {
        require(_quantity > 0, InvalidQuantity(_quantity));
        require(_price > 0, InvalidPrice(_quantity));
        require(_quantity > 0, InvalidQuantity(_quantity));
    }

    function listErc721ForDirectSale(
        address _nftAddress,
        address _paymentToken,
        uint256 _tokenId,
        uint256 _price
    ) private {}

    function cancelListing(
        address nftAddress,
        uint256 tokenId
    ) external isOwner(nftAddress, tokenId, msg.sender) isListed(nftAddress, tokenId) {
        delete (directListings[nftAddress][tokenId]);
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }

    function buyItem(address nftAddress, uint256 tokenId) external payable isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listedItem = directListings[nftAddress][tokenId];
        if (msg.value < listedItem.price) {
            revert PriceNotMet(nftAddress, tokenId, listedItem.price);
        }

        sellerProceeds[listedItem.seller][listedItem.paymentToken] += msg.value;
        delete (directListings[nftAddress][tokenId]);
        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    ) external isListed(nftAddress, tokenId) nonReentrant isOwner(nftAddress, tokenId, msg.sender) {
        if (newPrice == 0) {
            revert PriceMustBeAboveZero();
        }

        directListings[nftAddress][tokenId].price = newPrice;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
    }

    // function withdrawProceeds() external {
    //     uint256 proceeds = sellerProceeds[msg.sender];
    //     if (proceeds <= 0) {
    //         revert NoProceeds();
    //     }
    //     sellerProceeds[msg.sender] = 0;

    //     (bool success, ) = payable(msg.sender).call{value: proceeds}("");
    //     require(success, "Transfer failed");
    // }

    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        return directListings[nftAddress][tokenId];
    }

    function getProceeds(address seller, address token) external view returns (uint256) {
        return sellerProceeds[seller][token];
    }
}
