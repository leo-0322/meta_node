// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFT is ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 private _tokenIds;

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC721(name_, symbol_) Ownable(owner_) {}

    function mintNFT(
        address to,
        string memory tokenURI_
    ) public onlyOwner nonReentrant {
        _tokenIds++;
        _safeMint(to, _tokenIds);
        _setTokenURI(_tokenIds, tokenURI_);
    }
}
