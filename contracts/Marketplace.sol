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
        sellTax = 25;
        buyTax = 25;
        treasury = _treasury;
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
    }

    // State =========

    uint8 public sellTax;
    uint8 public buyTax;
    address public treasury;
    mapping(address => bool) public blacklist;

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
        bool isEnded;
    }

    /**
     * @dev Mapping of auctionId to the highest bid placed
     * Because bidder can only withdraw their bid if they are not the highest bidder and the auction is ended
     */
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => uint256)) bids;
    mapping(uint256 => Listing) public directSales;
    uint256 auctionId;
    uint256 listingId;
    mapping(address => mapping(address => uint256)) private pendingWithdrawals;

    // Modifiers =========

    modifier whiteListOnly() {
        if (blacklist[_msgSender()] == true) {
            revert Errors.Unauthorized(_msgSender());
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

    modifier auctionCreatorOnly(uint256 _auctionId) {
        if (auctions[_auctionId].seller != _msgSender()) {
            revert Errors.NotAuctionCreator(_auctionId);
        }
        _;
    }

    modifier liveAuction(uint256 _auctionId) {
        if (auctions[_auctionId].endAuction < block.timestamp) {
            revert Errors.AuctionNotEnded(_auctionId);
        }

        if (auctions[_auctionId].isEnded == true) {
            revert Errors.AuctionAlreadyEnded(_auctionId);
        }
        _;
    }

    modifier validErc1155Quantity(address nftAddress, uint256 _quantity) {
        if (Helpers.isERC1155(nftAddress) && _quantity == 0) {
            revert Errors.InvalidQuantity(_quantity);
        }
        _;
    }

    modifier existSale(uint256 _saleId) {
        if (directSales[_saleId].price == 0) {
            revert Errors.SaleNotExists(_saleId);
        }
        _;
    }

    modifier sellerOnly(uint256 _saleId) {
        if (directSales[_saleId].seller != _msgSender()) {
            revert Errors.SellerOnly(_msgSender());
        }
        _;
    }

    modifier itemAvailable(uint256 _saleId) {
        if (directSales[_saleId].isSold == true) {
            revert Errors.ItemAlreadySold(_saleId);
        }
        _;
    }

    // Internal =========

    function getNewBidPriceFromUserPlaced(uint256 _userPlacedAmount) internal view returns (uint256) {
        return (_userPlacedAmount * Constants.TAX_BASE) / (Constants.TAX_BASE + buyTax);
    }

    function getSellTaxFee(uint256 _price) internal view returns (uint256) {
        return (_price * sellTax) / Constants.TAX_BASE;
    }

    function getBuyTaxFee(uint256 _price) internal view returns (uint256) {
        return (_price * buyTax) / Constants.TAX_BASE;
    }

    /**
     * @dev Transfer the NFT back to the seller if the auction is ended and no one bid
     * @param _auctionId The auction id
     */
    function delistNft(uint256 _auctionId) internal {
        Auction memory auction = auctions[_auctionId];
        address nftAddress = auction.nftAddress;

        if (Helpers.isERC721(nftAddress)) {
            return IERC721(nftAddress).safeTransferFrom(address(this), _msgSender(), auction.tokenId);
        }

        return
            IERC1155(nftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                auction.tokenId,
                auction.erc1155Quantity,
                "0x0"
            );
    }

    // Tax =========

    function setTaxFee(uint8 _sellTax, uint8 _buyTax) external onlyOwner {
        if (_sellTax > 100) {
            revert Errors.InvalidSellTax(_sellTax);
        }
        if (_buyTax > 100) {
            revert Errors.InvalidBuyTax(_buyTax);
        }

        sellTax = _sellTax;
        buyTax = _buyTax;

        emit Events.TaxChanged(_sellTax, _buyTax);
    }

    // Ban/Unban =========

    function banUser(address user) external onlyOwner {
        blacklist[user] = true;
        emit Events.UserBanned(user);
    }

    function unbanUser(address user) external onlyOwner {
        delete blacklist[user];
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
    ) external whiteListOnly validPrice(_floorPrice) validErc1155Quantity(_nftAddress, _erc1155Quantity) {
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
            false
        );
        auctionId++;

        emit Events.AuctionCreated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _erc1155Quantity,
            _floorPrice,
            _bidIncrement,
            _startAuction,
            _endAuction
        );
    }

    function placeNewBid(
        uint256 _auctionId,
        uint256 _newBidPrice
    ) external payable whiteListOnly existAuction(_auctionId) liveAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        // Actual amount user have to placed
        uint256 userPlacedAmount;
        bool isETHPayment = Helpers.isETH(auction.priceToken);

        if (isETHPayment) {
            userPlacedAmount = msg.value;
        } else {
            userPlacedAmount = _newBidPrice;
        }

        uint256 newBidPrice = getNewBidPriceFromUserPlaced(userPlacedAmount);

        require(newBidPrice >= auction.floorPrice, "PlaceBid: Bid price must be above floor price");
        if (auction.bidCount > 0) {
            require(
                newBidPrice >= auction.currentBidPrice + auction.bidIncrement,
                "PlaceBid: New bid price need to greater than minimum price"
            );
        }

        if (!isETHPayment) {
            IERC20 paymentToken = IERC20(auction.priceToken);
            paymentToken.safeTransferFrom(_msgSender(), address(this), userPlacedAmount);
        }

        if (auction.currentBidOwner != address(0)) {
            bids[_auctionId][auction.currentBidOwner] += userPlacedAmount;
        }

        auction.currentBidPrice = newBidPrice;
        auction.currentBidOwner = payable(_msgSender());
        auction.bidCount++;

        emit Events.NewBidPlaced(auctionId, _msgSender(), userPlacedAmount);
    }

    /**
     * Seller or highest bidder can withdraw their bid if the auction is ended
     * @param _auctionId The auction id
     */
    function endAuction(uint256 _auctionId) external existAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];

        require(block.timestamp >= auction.endAuction, "EndAuction: Not end yet");
        require(auction.isEnded == false, "EndAuction: Already ended");

        // Claim NFT back if no one bid
        if (auction.bidCount == 0) {
            delistNft(_auctionId);
            emit Events.AuctionEndedWithNoWinner(_auctionId);
            return;
        }

        uint256 sellTaxFee = getSellTaxFee(auction.currentBidPrice);
        uint256 buyTaxFee = getBuyTaxFee(auction.currentBidPrice);

        // Reduce amount winner can claim
        uint256 sellerProceeds = auction.currentBidPrice - sellTaxFee;

        // Send the sell fee to treasury
        if (Helpers.isETH(auction.priceToken)) {
            (bool success, ) = payable(treasury).call{ value: sellTaxFee + buyTaxFee }("");
            require(success, "EndAuction: Transfer fee failed");
        } else {
            IERC20(auction.priceToken).safeTransfer(treasury, sellTaxFee + buyTaxFee);
        }

        // Transfer the NFT to the winner
        if (Helpers.isERC721(auction.nftAddress)) {
            IERC721(auction.nftAddress).safeTransferFrom(address(this), auction.currentBidOwner, auction.tokenId);
        } else {
            IERC1155(auction.nftAddress).safeTransferFrom(
                address(this),
                auction.currentBidOwner,
                auction.tokenId,
                auction.erc1155Quantity,
                "0x0"
            );
        }

        pendingWithdrawals[_msgSender()][auction.priceToken] += sellerProceeds;
        auction.isEnded = true;
        emit Events.AuctionEnded(_auctionId, auction.currentBidOwner, auction.currentBidPrice);
    }

    function cancelAuction(uint256 _auctionId) external existAuction(_auctionId) auctionCreatorOnly(_auctionId) {
        Auction memory auction = auctions[_auctionId];

        require(auction.bidCount == 0, "CancelAuction: User already bidded");
        require(auction.startAuction > block.timestamp, "CancelAuction: Auction already started");

        delete (auctions[_auctionId]);
        emit Events.AuctionCanceled(_auctionId);
    }

    // Direct sale =========

    function listForSale(
        address _paymentToken,
        address _nftAddress,
        uint256 _tokenId,
        uint256 _erc1155Quantity,
        uint256 _price
    ) external whiteListOnly validPrice(_price) validErc1155Quantity(_nftAddress, _erc1155Quantity) {
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

        emit Events.ItemListed(_msgSender(), _nftAddress, _tokenId, _erc1155Quantity, _price, _paymentToken);
    }

    function buyItem(
        uint256 _saleId
    ) external payable whiteListOnly nonReentrant existSale(_saleId) itemAvailable(_saleId) {
        Listing memory sale = directSales[_saleId];

        uint256 sellFee = getSellTaxFee(sale.price);
        uint256 buyFee = getBuyTaxFee(sale.price);
        uint256 actualPrice = sale.price + buyFee;
        uint256 sellerProceeds = sale.price - sellFee;

        if (Helpers.isETH(sale.paymentToken)) {
            if (msg.value < actualPrice) {
                revert Errors.PriceNotMet(sale.nftAddress, sale.tokenId, actualPrice);
            }

            (bool success, ) = payable(treasury).call{ value: sellFee }("");
            require(success, "Buy: Transfer fee failed");
        } else {
            IERC20(sale.paymentToken).safeTransferFrom(_msgSender(), address(this), sale.price);
            IERC20(sale.paymentToken).safeTransfer(treasury, sellFee);
        }

        if (Helpers.isERC721(sale.nftAddress)) {
            IERC721(sale.nftAddress).safeTransferFrom(address(this), _msgSender(), sale.tokenId);
        } else {
            IERC1155(sale.nftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                sale.tokenId,
                sale.erc1155Quantity,
                "0x0"
            );
        }

        pendingWithdrawals[sale.seller][sale.paymentToken] += sellerProceeds;
        directSales[_saleId].isSold = true;
        emit Events.ItemBought(_saleId, _msgSender());
    }

    function cancelListing(uint256 _saleId) external existSale(_saleId) sellerOnly(_saleId) itemAvailable(_saleId) {
        Listing memory sale = directSales[_saleId];

        // Transfer back the NFT
        if (Helpers.isERC721(sale.nftAddress)) {
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
        emit Events.ItemCanceled(_saleId);
    }

    // Withdraw =========

    function getProceeds(address seller, address token) external view returns (uint256) {
        return pendingWithdrawals[seller][token];
    }

    function withdraw(address[] memory tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            address withdrawalToken = tokens[i];
            uint256 pendingAmount = pendingWithdrawals[_msgSender()][withdrawalToken];

            if (pendingAmount > 0) {
                uint256 tempProceeds = pendingAmount;
                pendingWithdrawals[_msgSender()][withdrawalToken] = 0;

                // ETH
                if (Helpers.isETH(withdrawalToken)) {
                    (bool success, ) = payable(_msgSender()).call{ value: tempProceeds }("");
                    require(success, "Transfer failed");
                    break;
                }

                IERC20(withdrawalToken).safeTransfer(_msgSender(), pendingAmount);
            }
        }
    }

    // ETH Receiver =========

    receive() external payable {
        emit Events.ETHReceived(_msgSender(), msg.value);
    }
}
