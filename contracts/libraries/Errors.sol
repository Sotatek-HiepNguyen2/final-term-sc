// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Errors {
    error Unauthorized(address user);

    error InvalidSellTax(uint256 tax);
    error InvalidBuyTax(uint256 tax);

    error InvalidPrice(uint256 price);
    error AuctionNotExists(uint256 auctionId);
    error AuctionNotEnded(uint256 auctionId);
    error AuctionAlreadyEnded(uint256 auctionId);

    error InvalidBidIncrement(uint256 bidIncrement);

    error SaleNotExists(uint256 saleId);
    error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
    error NoProceeds();
    error PriceMustBeAboveZero();
    error UserAlreadyNotBanned(address user);
    error UserBanned(address user);

    error InvalidQuantity(uint256 quantity);
}
