import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { describe } from "mocha";

import {
  ERC721_TOKEN_ID,
  ERC721_TOKEN_URI,
  ERC1155_QUANTITY,
  ERC1155_TOKEN_ID,
  deployMarketFixture,
} from "./Market.fixture";
import { Signers } from "./types";

describe("Market", function () {
  before(async function () {
    this.signers = {} as Signers;

    const signers = await ethers.getSigners();
    this.signers.admin = signers[0];

    this.loadFixture = loadFixture;
  });

  describe("Deployment", function () {
    beforeEach(async function () {
      const { market, treasury, owner, erc721Token } = await this.loadFixture(deployMarketFixture);
      this.market = market;
      this.treasury = treasury;
      this.owner = owner;
      this.erc721Token = erc721Token;
    });

    it("Should deploy the right owner", async function () {
      expect(await this.market.owner()).to.equal(this.owner.address);
    });

    it("Should deploy the right treasury", async function () {
      expect(await this.market.treasury()).to.equal(this.treasury.address);
    });

    it("Should deploy the right tax fee value", async function () {
      expect(await this.market.buyTaxFee()).to.equal(25);
      expect(await this.market.sellTaxFee()).to.equal(25);
    });

    it("Mock ERC721 token should be deployed", async function () {
      // check tokenURI function works
      expect(await this.erc721Token.tokenURI(ERC721_TOKEN_ID)).to.equal(ERC721_TOKEN_URI);
    });
  });

  describe("Marketplace", async function () {
    beforeEach(async function () {
      const {
        market,
        treasury,
        owner,
        bannedUser,
        autionCreator,
        bidder,
        buyer,
        seller,
        erc1155Token,
        erc20Token,
        erc721Token,
      } = await this.loadFixture(deployMarketFixture);
      this.market = market;
      this.treasury = treasury;
      this.owner = owner;
      this.bannedUser = bannedUser;
      this.auctionCreator = autionCreator;
      this.bidder = bidder;
      this.buyer = buyer;
      this.seller = seller;
      this.erc1155Token = erc1155Token;
      this.erc20Token = erc20Token;
      this.erc721Token = erc721Token;
    });

    describe("Setup tax fee", async function () {
      it("Should revert if not owner", async function () {
        await expect(this.market.connect(this.treasury).setTaxFee(5, 5)).to.be.revertedWithCustomError(
          this.market,
          "OwnableUnauthorizedAccount",
        );
      });

      it("Should revert if sell tax fee is invalid", async function () {
        await expect(this.market.setTaxFee(101, 5)).to.be.revertedWith("Invalid sell tax fee");
      });

      it("Should revert if buy tax fee is invalid", async function () {
        await expect(this.market.setTaxFee(5, 101)).to.be.revertedWith("Invalid buy tax fee");
      });

      it("Should set the right tax fee", async function () {
        const SELL_TAX_FEE = 5;
        const BUY_TAX_FEE = 10;

        await this.market.setTaxFee(SELL_TAX_FEE, BUY_TAX_FEE);
        expect(await this.market.sellTaxFee()).to.equal(SELL_TAX_FEE);
        expect(await this.market.buyTaxFee()).to.equal(BUY_TAX_FEE);
      });
    });

    describe("Blacklist", function () {
      it("Should revert if not owner", async function () {
        await expect(this.market.connect(this.treasury).banUser(this.bannedUser.address)).to.be.revertedWithCustomError(
          this.market,
          "OwnableUnauthorizedAccount",
        );
      });

      it("Should blacklist an address", async function () {
        await this.market.banUser(this.bannedUser.address);
        expect(await this.market.blackList(this.bannedUser.address)).to.be.true;
      });

      it("Should unblacklist an address", async function () {
        await this.market.banUser(this.bannedUser.address);
        expect(await this.market.blackList(this.bannedUser.address)).to.be.true;

        await this.market.unbanUser(this.bannedUser.address);
        expect(await this.market.blackList(this.bannedUser.address)).to.be.false;
      });
    });

    describe("Trade", function () {
      beforeEach(async function () {
        await this.market.banUser(this.bannedUser.address);
      });

      describe("Sell and Buy", function () {
        it("Should revert if blacklisted", async function () {
          await expect(
            this.market
              .connect(this.bannedUser)
              .listForSale(ethers.ZeroAddress, await this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0, BigInt(1e18)),
          ).to.be.revertedWithCustomError(this.market, "UserBanned");

          await expect(this.market.connect(this.bannedUser).buyItem(0)).to.be.revertedWithCustomError(
            this.market,
            "UserBanned",
          );
        });

        it("Should revert if the erc721 is not approved", async function () {
          await expect(
            this.market
              .connect(this.seller)
              .listForSale(ethers.ZeroAddress, await this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0, BigInt(1e18)),
          ).to.be.revertedWith("NFTTrade: Caller has not approved NFTTrade contract for token transfer.");
        });

        it("Should revert if price is 0", async function () {
          // approve the erc721 token
          await this.erc721Token.connect(this.seller).approve(await this.market.getAddress(), ERC721_TOKEN_ID);

          await expect(
            this.market
              .connect(this.seller)
              .listForSale(ethers.ZeroAddress, await this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0, 0),
          ).to.be.revertedWithCustomError(this.market, "InvalidPrice");
        });

        it("Should revert if the token is not erc721 or erc1155", async function () {
          await expect(
            this.market
              .connect(this.seller)
              .listForSale(ethers.ZeroAddress, await this.erc20Token.getAddress(), ERC721_TOKEN_ID, 0, BigInt(1e18)),
          ).to.be.reverted;
        });

        it("Should revert if the erc721 nft is not owned by the seller", async function () {
          await expect(
            this.market
              .connect(this.seller)
              .listForSale(ethers.ZeroAddress, await this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0, BigInt(1e18)),
          ).to.be.revertedWith("NFTTrade: Caller has not approved NFTTrade contract for token transfer.");
        });

        it("Should list an erc721 token for sale", async function () {
          // approve the erc721 token
          await this.erc721Token.connect(this.seller).approve(await this.market.getAddress(), ERC721_TOKEN_ID);

          await this.market
            .connect(this.seller)
            .listForSale(ethers.ZeroAddress, await this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0, BigInt(1e18));

          const item = await this.market.directSales(0);
          expect(item.tokenId).to.equal(ERC721_TOKEN_ID);
          expect(item.nftAddress).to.equal(await this.erc721Token.getAddress());
          expect(item.erc1155Quantity).to.equal(0);
          expect(item.paymentToken).to.equal(ethers.ZeroAddress);
          expect(item.seller).to.equal(this.seller.address);
          expect(item.price).to.equal(BigInt(1e18));
          expect(item.isSold).to.be.false;
        });

        // Check sell for erc1155 token
        it("Should revert if the balance of erc1155 is not enough", async function () {
          await expect(
            this.market
              .connect(this.seller)
              .listForSale(
                ethers.ZeroAddress,
                await this.erc1155Token.getAddress(),
                ERC1155_TOKEN_ID,
                200,
                BigInt(1e18),
              ),
          ).to.be.revertedWithCustomError(this.market, "InsufficientBalance");
        });

        it("Should revert if the erc1155 token is not approved all for market", async function () {
          await expect(
            this.market
              .connect(this.seller)
              .listForSale(
                ethers.ZeroAddress,
                await this.erc1155Token.getAddress(),
                ERC1155_TOKEN_ID,
                ERC1155_QUANTITY,
                BigInt(1e18),
              ),
          ).to.be.revertedWithCustomError(this.market, "NftHasNotApproved");
        });

        it("Should list an erc1155 token for sale", async function () {
          await this.erc1155Token.connect(this.seller).setApprovalForAll(await this.market.getAddress(), true);

          await this.market
            .connect(this.seller)
            .listForSale(
              ethers.ZeroAddress,
              await this.erc1155Token.getAddress(),
              ERC1155_TOKEN_ID,
              ERC1155_QUANTITY,
              BigInt(1e18),
            );

          const item = await this.market.directSales(0);
          expect(item.tokenId).to.equal(ERC1155_TOKEN_ID);
          expect(item.nftAddress).to.equal(await this.erc1155Token.getAddress());
          expect(item.erc1155Quantity).to.equal(ERC1155_QUANTITY);
          expect(item.paymentToken).to.equal(ethers.ZeroAddress);
          expect(item.seller).to.equal(this.seller.address);
          expect(item.price).to.equal(BigInt(1e18));
          expect(item.isSold).to.be.false;
        });
      });
      describe("Cancel listing", function () {
        beforeEach(async function () {
          await this.erc721Token.connect(this.seller).approve(await this.market.getAddress(), ERC721_TOKEN_ID);

          await this.market
            .connect(this.seller)
            .listForSale(ethers.ZeroAddress, await this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0, BigInt(1e18));
        });

        it("Should revert if saleId is invalid", async function () {
          await expect(this.market.connect(this.seller).cancelListing(1)).to.be.revertedWith("Invalid sale id");
        });

        it("Should revert if not the seller", async function () {
          await expect(this.market.connect(this.buyer).cancelListing(0)).to.be.rejectedWith(
            "Cancel: should be the owner of the sell",
          );
        });

        it("Should revert if the item is already sold", async function () {
          await this.market.connect(this.buyer).buyItem(0, { value: BigInt(1e18) });

          await expect(this.market.connect(this.seller).cancelListing(0)).to.be.revertedWith("Cancel: already sold");
        });

        it("Should emit event when cancel listing", async function () {
          await expect(this.market.connect(this.seller).cancelListing(0))
            .to.emit(this.market, "ItemCanceled")
            .withArgs(this.seller.address, this.erc721Token.getAddress(), ERC721_TOKEN_ID, 0);
        });
      });
      describe("Auction", function () {});
    });
  });
});
