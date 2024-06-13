// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constants {
    uint16 constant TAX_BASE = 10000;
    address constant ETH = address(0);

    // These are the interface identifiers for ERC721 and ERC1155, calculated as follows:
    // bytes4(keccak256('balanceOf(address)')) ^ bytes4(keccak256('ownerOf(uint256)')) for ERC721
    // bytes4(keccak256('balanceOf(address,uint256)')) ^ bytes4(keccak256('safeTransferFrom(address,address,uint256,uint256,bytes)')) for ERC1155
    bytes4 constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
}
