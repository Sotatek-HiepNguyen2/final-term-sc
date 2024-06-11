import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { describe } from "mocha";

import { ERC721_TOKEN_ID, ERC1155_TOKEN_ID, deployMarketFixture } from "./Market.fixture";
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
      const { market, treasury, owner } = await this.loadFixture(deployMarketFixture);
      this.market = market;
      this.treasury = treasury;
      this.owner = owner;
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
          ).to.be.revertedWithCustomError(this.market, "PriceMustBeAboveZero");
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
      });
      describe("Auction", function () {});
    });
  });
});
