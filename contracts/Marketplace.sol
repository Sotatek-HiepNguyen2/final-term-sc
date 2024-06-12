// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error NoProceeds();
error NotOwner();
error PriceMustBeAboveZero();
error UserAlreadyNotBanned(address user);
error UserBanned(address user);

error NftHasNotApproved();
error InsufficientBalance(uint256 amount);

error InvalidQuantity(uint256 quantity);
error InvalidPrice(uint256 price);

uint16 constant TAX_BASE = 10000;
address constant ETH = address(0);

// These are the interface identifiers for ERC721 and ERC1155, calculated as follows:
// bytes4(keccak256('balanceOf(address)')) ^ bytes4(keccak256('ownerOf(uint256)')) for ERC721
// bytes4(keccak256('balanceOf(address,uint256)')) ^ bytes4(keccak256('safeTransferFrom(address,address,uint256,uint256,bytes)')) for ERC1155
bytes4 constant INTERFACE_ID_ERC721 = 0x80ac58cd;
bytes4 constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

function isERC721(address nft) view returns (bool) {
    return IERC165(nft).supportsInterface(INTERFACE_ID_ERC721);
}

function isERC1155(address nft) view returns (bool) {
    return IERC165(nft).supportsInterface(INTERFACE_ID_ERC1155);
}

contract Marketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    address public treasury;
    uint8 public sellTaxFee;
    uint8 public buyTaxFee;
    function initialize(address _treasury) public initializer {
        sellTaxFee = 25;
        buyTaxFee = 25;
        treasury = _treasury;
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
    }

    function setTaxFee(uint8 _sellTaxFee, uint8 _buyTaxFee) external onlyOwner {
        require(_sellTaxFee < 100, "Invalid sell tax fee");
        require(_buyTaxFee < 100, "Invalid buy tax fee");

        sellTaxFee = _sellTaxFee;
        buyTaxFee = _buyTaxFee;
    }

    struct Listing {
        uint256 price;
        uint256 erc1155Quantity;
        address paymentToken;
        address seller;
        address nftAddress;
        uint256 tokenId;
        bool isSold;
    }
    mapping(uint256 => Listing) public directSales;
    uint256 listingId;

    struct Auction {
        address seller;
        address nftAddress;
        address priceToken;
        uint256 tokenId;
        uint256 floorPrice;
        uint256 endAuction;
        uint256 bidIncrement;
        uint256 bidCount;
        uint256 currentBidPrice;
        address payable currentBidOwner;
        bool isEnded;
    }
    mapping(uint256 => Auction) public auctions;
    uint256 auctionId;

    // Seller => token => amount
    mapping(address => mapping(address => uint256)) private sellerProceeds;

    // ==============Blacklist================= //

    mapping(address => bool) public blackList;

    function banUser(address _user) external onlyOwner {
        blackList[_user] = true;
    }

    function unbanUser(address _user) external onlyOwner {
        if (blackList[_user] == false) {
            revert UserAlreadyNotBanned(_user);
        }

        delete blackList[_user];
    }

    modifier whiteListOnly() {
        if (blackList[msg.sender] == true) {
            revert UserBanned(msg.sender);
        }
        _;
    }

    // ===========Events=========== //
    enum NFTType {
        ERC721,
        ERC1155
    }

    event NewAuctionCreated(
        address creator,
        address nftAddress,
        uint256 tokenId,
        NFTType nftType,
        uint256 quantity,
        uint256 floorPrice,
        uint256 endTime
    );
    event NewBidPlaced();

    event ItemListed(address seller, address nftAddress, uint256 tokenId, uint256 price);
    event ItemCanceled(address seller, address nftAddress, uint256 tokenId, uint256 quantity);
    event ItemBought(address buyer, address nftAddress, uint256 tokenId, uint256 price, uint256 quantity);

    //=============Auction==================//

    //    function createAuction(
    //        address _nftAddress,
    //        uint256 _tokenId,
    //        uint256 floorPrice,
    //        address priceToken,
    //        uint256 endAuction
    //    ) external whiteListOnly {
    //         if (isERC721(_nftAddress)) {
    //             IERC721(_nftAddress).approve(address(this), _tokenId);
    //         } else if (isERC1155(_nftAddress)) {

    //         }

    //        auctions[auctionId] = Auction(
    //            msg.sender,
    //            _nftAddress,
    //            _tokenId,
    //            floorPrice,
    //            priceToken,
    //            0,
    //            payable(address(0)),
    //            endAuction,
    //            0
    //        );
    //        auctionId++;

    //        emit NewAuctionCreated(msg.sender, _nftAddress, _tokenId, );
    //    }

    //    function cancelAuction(
    //        address _nftAddress,
    //        uint256 _tokenId
    //    ) external nftOwnerOnly(_nftAddress, _tokenId, msg.sender) {
    //        delete (directListings[_nftAddress][_tokenId]);
    //        emit ItemCanceled(msg.sender, _nftAddress, _tokenId);
    //    }

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

    //    function withdrawNft(uint256 _auctionId) external {
    //        // Require exist auction
    //        // Require auction end
    //        // Require: winner

    //        Auction memory auction = auctions[_auctionId];

    //        address nftAddress = auction.nft;
    //        delete (auctions[_auctionId]);
    //        IERC721(nftAddress).safeTransferFrom(auction.seller, msg.sender, auction.tokenId);
    //    }

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

    // ======= Direct sale ======== //

    function validateErc1155(address _nftAddress, uint256 _tokenId, uint256 _quantity) private view {
        IERC1155 nft = IERC1155(_nftAddress);
        if (nft.balanceOf(_msgSender(), _tokenId) < _quantity) {
            revert InsufficientBalance(_quantity);
        }

        if (!nft.isApprovedForAll(_msgSender(), address(this))) {
            revert NftHasNotApproved();
        }
    }

    function validateErc721(address _nftAddress, uint256 _tokenId) private view {
        IERC721 nft = IERC721(_nftAddress);

        require(
            nft.getApproved(_tokenId) == address(this) || nft.isApprovedForAll(_msgSender(), address(this)),
            "NFTTrade: Caller has not approved NFTTrade contract for token transfer."
        );

        require(nft.ownerOf(_tokenId) == _msgSender(), "NFTTrade: Caller does not own the token.");
    }

    modifier validPrice(uint256 _price) {
        if (_price == 0) revert InvalidPrice(_price);
        _;
    }

    modifier validNFT(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity
    ) {
        if (isERC1155(_nftAddress)) {
            validateErc1155(_nftAddress, _tokenId, _quantity);
        } else if (isERC721(_nftAddress)) {
            validateErc721(_nftAddress, _tokenId);
        }
        _;
    }

    function listForSale(
        address _paymentToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _erc1155Quantity,
        uint256 _price
    ) external whiteListOnly validPrice(_price) validNFT(_nftAddress, _tokenId, _erc1155Quantity) {
        Listing memory newListing = Listing({
            price: _price,
            erc1155Quantity: _erc1155Quantity,
            paymentToken: _paymentToken,
            seller: _msgSender(),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            isSold: false
        });

        directSales[listingId] = newListing;
        listingId++;

        emit ItemListed(msg.sender, _nftAddress, _tokenId, _price);
    }

    function cancelListing(uint256 _saleId) external {
        Listing memory sale = directSales[_saleId];

        require(sale.price > 0, "Invalid sale id");
        require(sale.seller == msg.sender, "Cancel: should be the owner of the sell");
        require(sale.isSold == false, "Cancel: already sold");

        delete (directSales[_saleId]);
        emit ItemCanceled(sale.seller, sale.nftAddress, sale.tokenId, sale.erc1155Quantity);
    }

    function buyItem(uint256 _saleId) external payable whiteListOnly nonReentrant {
        Listing memory sale = directSales[_saleId];

        require(sale.price > 0, "Not exist");
        bool isETHPayment = sale.paymentToken == address(0);

        if (isETHPayment) {
            if (msg.value < sale.price) {
                revert PriceNotMet(sale.nftAddress, sale.tokenId, sale.price);
            }

            sellerProceeds[sale.seller][sale.paymentToken] += msg.value;
        }

        if (!isETHPayment) {
            IERC20(sale.paymentToken).transferFrom(_msgSender(), address(this), sale.price);
            sellerProceeds[sale.seller][sale.paymentToken] += sale.price;
        }

        if (isERC721(sale.nftAddress)) {
            IERC721(sale.nftAddress).safeTransferFrom(sale.seller, msg.sender, sale.tokenId);
        } else {
            IERC1155(sale.nftAddress).safeTransferFrom(
                sale.seller,
                msg.sender,
                sale.tokenId,
                sale.erc1155Quantity,
                "0x0"
            );
        }

        directSales[_saleId].isSold = true;
        emit ItemBought(msg.sender, sale.nftAddress, sale.tokenId, sale.price, sale.erc1155Quantity);
    }

    function getProceeds(address seller, address token) external view returns (uint256) {
        return sellerProceeds[seller][token];
    }
}
