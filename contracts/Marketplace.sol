// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { Events } from "contracts/libraries/Events.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { Constants } from "contracts/libraries/Constants.sol";
import { Helpers } from "contracts/libraries/Helpers.sol";

contract Marketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _treasury) public initializer {
        sellTaxFee = 25;
        buyTaxFee = 25;
        treasury = _treasury;
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
    }

    // State =========

    address public treasury;
    uint8 public sellTaxFee;
    uint8 public buyTaxFee;

    struct Listing {
        uint256 price;
        uint256 erc1155Quantity;
        address paymentToken;
        address seller;
        address nftAddress;
        uint256 tokenId;
        bool isSold;
    }

    struct Auction {
        address seller;
        address nftAddress;
        address priceToken;
        uint256 tokenId;
        uint256 erc1155Quantity;
        uint256 floorPrice;
        uint256 startAuction;
        uint256 endAuction;
        uint256 bidIncrement;
        uint256 bidCount;
        uint256 currentBidPrice;
        address payable currentBidOwner;
        Constants.AuctionStatus status;
    }
    mapping(address => uint256) bids;

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Listing) public directSales;
    uint256 auctionId;
    uint256 listingId;

    mapping(address => mapping(address => uint256)) private pendingWithdrawals;
    mapping(address => bool) public blacklist;

    // Modifiers =========

    modifier whiteListOnly() {
        if (blacklist[msg.sender] == true) {
            revert Errors.Unauthorized(msg.sender);
        }
        _;
    }

    modifier validPrice(uint256 _price) {
        if (_price == 0) revert Errors.InvalidPrice(_price);
        _;
    }

    modifier existAuction(uint256 _auctionId) {
        if (auctions[_auctionId].floorPrice == 0) {
            revert Errors.AuctionNotExists(_auctionId);
        }
        _;
    }

    modifier liveAuction(uint256 _auctionId) {
        if (auctions[_auctionId].endAuction < block.timestamp) {
            revert Errors.AuctionNotEnded(_auctionId);
        }

        if (auctions[_auctionId].status == Constants.AuctionStatus.Ended) {
            revert Errors.AuctionAlreadyEnded(_auctionId);
        }
        _;
    }

    modifier existSale(uint256 _saleId) {
        if (directSales[_saleId].price == 0) {
            revert Errors.SaleNotExists(_saleId);
        }
        _;
    }

    // Tax =========

    function setTaxFee(uint8 _sellTaxFee, uint8 _buyTaxFee) external onlyOwner {
        if (_sellTaxFee > 100) {
            revert Errors.InvalidSellTax(_sellTaxFee);
        }
        if (_buyTaxFee > 100) {
            revert Errors.InvalidBuyTax(_buyTaxFee);
        }

        sellTaxFee = _sellTaxFee;
        buyTaxFee = _buyTaxFee;

        emit Events.TaxChanged(_sellTaxFee, _buyTaxFee);
    }

    // Ban/Unban =========

    function banUser(address user) private onlyOwner {
        blacklist[user] = true;
        emit Events.UserBanned(user);
    }

    function unbanUser(address user) private onlyOwner {
        blacklist[user] = false;
        emit Events.UserUnbanned(user);
    }

    // Auction =========

    function createAuction(
        address _priceToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _floorPrice,
        uint256 _startAuction,
        uint256 _endAuction,
        uint256 _erc1155Quantity,
        uint256 _bidIncrement
    ) external whiteListOnly validPrice(_floorPrice) {
        require(_startAuction > block.timestamp, "CreateAuction: Start time must be in the future");
        require(_startAuction < _endAuction, "CreateAuction: Start time must be before end time");
        require(_bidIncrement > 0, "CreateAuction: Bid increment must be above zero");

        if (Helpers.isERC721(_nftAddress)) {
            IERC721(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId);
        } else {
            IERC1155(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId, _erc1155Quantity, "0x0");
        }

        auctions[auctionId] = Auction(
            _msgSender(),
            _nftAddress,
            _priceToken,
            _tokenId,
            _erc1155Quantity,
            _floorPrice,
            _startAuction,
            _endAuction,
            _bidIncrement,
            0,
            0,
            payable(address(0)),
            Constants.AuctionStatus.Ongoing
        );
        auctionId++;

        emit Events.AuctionCreated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _erc1155Quantity,
            _floorPrice,
            _startAuction,
            _endAuction
        );
    }

    function placeNewBid(
        uint256 _auctionId,
        uint256 _newBidPrice
    ) external payable whiteListOnly existAuction(_auctionId) liveAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        uint256 newBidPrice;
        bool isETHPayment = Helpers.isETH(auction.priceToken);

        if (isETHPayment) {
            newBidPrice = msg.value;
        } else {
            newBidPrice = _newBidPrice;
        }

        require(newBidPrice >= auction.floorPrice, "PlaceBid: Bid price must be above floor price");
        if (auction.bidCount > 0) {
            require(
                newBidPrice >= auction.currentBidPrice + auction.bidIncrement,
                "PlaceBid: New bid price need to greater than minimum price"
            );
        }

        if (!isETHPayment) {
            IERC20 paymentToken = IERC20(auction.priceToken);
            paymentToken.safeTransfer(_msgSender(), address(this), _newBidPrice);
            auction.currentBidPrice = _newBidPrice;
        }
        pendingWithdrawals[_msgSender()][auction.priceToken] += newBidPrice;

        auction.currentBidPrice = newBidPrice;
        auction.currentBidOwner = payable(_msgSender());
        auction.bidCount++;

        emit Events.NewBidPlaced(auctionId, _msgSender(), _newBidPrice);
    }

    function endAuction(uint256 _auctionId) external {
        Auction storage auction = auctions[_auctionId];

        require(auction.floorPrice > 0, "EndAuction: Auction not exist");
        require(auction.seller == _msgSender(), "EndAuction: Not creator");
        require(block.timestamp >= auction.endAuction, "EndAuction: Not end yet");
        require(auction.isEnded == false, "EndAuction: Already ended");

        // Calculate sell fee, auction winner need to pay extra fee to claim the NFT
        uint256 sellFee = (auction.currentBidPrice * sellTaxFee) / Constants.TAX_BASE;

        auction.isEnded = true;
        emit Events.AuctionEnded(_auctionId);
    }

    function cancelAuction(uint256 _auctionId) external existAuction {
        Auction memory auction = auctions[_auctionId];

        require(auction.seller == _msgSender(), "CancelAuction: should be the owner of the auction");
        require(auction.bidCount == 0, "CancelAuction: User already bidded");
        require(auction.startAuction > block.timestamp, "CancelAuction: Auction already started");

        delete (auctions[_auctionId]);
        emit Events.AuctionCanceled(_auctionId);
    }

    // ======= Direct sale ======== //

    function listForSale(
        address _paymentToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _erc1155Quantity,
        uint256 _price
    ) external whiteListOnly validPrice(_price) {
        if (Helpers.isERC721(_nftAddress)) {
            IERC721(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId);
        } else {
            IERC1155(_nftAddress).safeTransferFrom(_msgSender(), address(this), _tokenId, _erc1155Quantity, "0x0");
        }

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

        emit Events.ItemListed(msg.sender, _nftAddress, _tokenId, _erc1155Quantity, _price, _paymentToken);
    }

    function buyItem(uint256 _saleId) external payable whiteListOnly nonReentrant {
        Listing memory sale = directSales[_saleId];

        require(sale.price > 0, "Not exist");
        require(sale.isSold == false, "Already sold");

        uint256 sellFee = (sale.price * sellTaxFee) / TAX_BASE;
        uint256 buyFee = (sale.price * buyTaxFee) / TAX_BASE;

        uint256 actualPrice = sale.price + buyFee;

        if (isETHPayment) {
            if (msg.value < actualPrice) {
                revert PriceNotMet(sale.nftAddress, sale.tokenId, sale.price);
            }

            (bool success, ) = payable(treasury).call{ value: sellFee }("");
            require(success, "Transfer fee failed");
        } else {
            IERC20(sale.paymentToken).transferFrom(_msgSender(), address(this), sale.price);
            IERC20(sale.paymentToken).transfer(treasury, sellFee);
        }

        if (isERC721(sale.nftAddress)) {
            IERC721(sale.nftAddress).safeTransferFrom(address(this), msg.sender, sale.tokenId);
        } else {
            IERC1155(sale.nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                sale.tokenId,
                sale.erc1155Quantity,
                "0x0"
            );
        }

        pendingWithdrawals;
        [sale.seller][sale.paymentToken] += sale.price - sellFee;
        directSales[_saleId].isSold = true;
        emit ItemBought(msg.sender, sale.nftAddress, sale.tokenId, sale.price, sale.erc1155Quantity);
    }

    function cancelListing(uint256 _saleId) external {
        Listing memory sale = directSales[_saleId];

        require(sale.price > 0, "Invalid sale id");
        require(sale.seller == msg.sender, "Cancel: should be the owner of the sell");
        require(sale.isSold == false, "Cancel: already sold");

        // Transfer back the NFT
        if (isERC721(sale.nftAddress)) {
            IERC721(sale.nftAddress).safeTransferFrom(address(this), sale.seller, sale.tokenId);
        } else {
            IERC1155(sale.nftAddress).safeTransferFrom(
                address(this),
                sale.seller,
                sale.tokenId,
                sale.erc1155Quantity,
                "0x0"
            );
        }
        delete (directSales[_saleId]);
        emit ItemCanceled(sale.seller, sale.nftAddress, sale.tokenId, sale.erc1155Quantity);
    }

    // Withdraw =========

    function getProceeds(address seller, address token) external view returns (uint256) {
        return pendingWithdrawals;
        [seller][token];
    }

    function withdrawProceeds(address[] memory tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            address withdrawalToken = tokens[i];
            uint256 proceeds = pendingWithdrawals;
            [_msgSender()][withdrawalToken];

            if (proceeds > 0) {
                uint256 tempProceeds = proceeds;
                pendingWithdrawals;
                [_msgSender()][withdrawalToken] = 0;

                // ETH
                if (withdrawalToken == address(0)) {
                    (bool success, ) = payable(_msgSender()).call{ value: tempProceeds }("");
                    require(success, "Transfer failed");
                    break;
                }

                IERC20 _withdrawalToken = IERC20(withdrawalToken);
                require(_withdrawalToken.transfer(_msgSender(), proceeds), "Transfer failed");
            }
        }
    }

    function withdrawNft(uint256 _auctionId) external {
        Auction memory auction = auctions[_auctionId];
        // Require exist auction
        require(auction.floorPrice > 0, "Auction not exist");
        // Require auction end
        require(auction.endAuction >= block.timestamp && auction.isEnded, "Auction in progress");
        // Require: winner
        require(auction.currentBidOwner == _msgSender(), "Not the auction winner");

        address nftAddress = auction.nftAddress;
        delete (auctions[_auctionId]);

        if (isERC721(nftAddress)) {
            return IERC721(nftAddress).safeTransferFrom(auction.seller, _msgSender(), auction.tokenId);
        }

        return
            IERC1155(nftAddress).safeTransferFrom(
                auction.seller,
                _msgSender(),
                auction.tokenId,
                auction.erc1155Quantity,
                "0x0"
            );
    }
}
