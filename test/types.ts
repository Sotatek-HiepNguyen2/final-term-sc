import type { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/dist/src/signer-with-address";

import { ERC20Mock, ERC721Mock, ERC1155Mock, type Lock, type Marketplace } from "../types";

type Fixture<T> = () => Promise<T>;

declare module "mocha" {
  export interface Context {
    lock: Lock;
    market: Marketplace;
    loadFixture: <T>(fixture: Fixture<T>) => Promise<T>;
    signers: Signers;
    erc20Token: ERC20Mock;
    erc721Token: ERC721Mock;
    erc1155Token: ERC1155Mock;
  }
}

export interface Signers {
  admin: SignerWithAddress;
}
