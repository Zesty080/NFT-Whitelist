// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IAvatarNFT.sol";
import "./interfaces/IRandomizer.sol";

contract AvatarNFT is
    IAvatarNFT,
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Burnable,
    Ownable,
    ReentrancyGuard
{
    using Counters for Counters.Counter;
    using Strings for uint256;

    string public baseUri;
    address public randomizer;
    address payable public manager;
    address public stakingAddr;
    uint256 public maxTotal;
    uint256 public maxLimit;
    uint256 public presaleLimit;
    uint256 public whitelistPrice;
    uint256 public publicSalePrice;
    uint256 public startTime;
    bytes32 public merkleRoot;

    Counters.Counter private _tokenIds;

    mapping(uint256 => avatarDetail) public avatarDetails;

    constructor(string memory _baseUri, address _randomizer, address payable _manager)
        ERC721("BKWZ-AVATAR", "BKWZ-A")
    {
        baseUri = _baseUri;
        randomizer = _randomizer;
        manager = _manager;

        maxTotal = 1000;
        maxLimit = 5;
        whitelistPrice = 0.75 ether;
        publicSalePrice = 1 ether;
        presaleLimit = 150;
        startTime = 1649880000;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function mint() internal returns (uint256) {
        _tokenIds.increment();

        require(_tokenIds.current() <= maxTotal, "Minting is already ended.");

        uint256 newNftId = _tokenIds.current();
        uint256 newAvatarId = IRandomizer(randomizer).getRandomAvatar();

        _safeMint(msg.sender, newNftId);

        // set avatar details
        avatarDetails[newNftId].id = newNftId;
        avatarDetails[newNftId].avatarId = newAvatarId;
        avatarDetails[newNftId].staked = false;

        return newNftId;
    }

    function presaleMint(uint256 amount, bytes32[] calldata merkleProof)
        public
        payable
    {
        require(block.timestamp > startTime, "Whitelist mint is not started yet");
        require(
            inWhitelist(merkleProof),
            "You are not registered to whitelist"
        );
        require(
            _tokenIds.current() + amount <= presaleLimit,
            "Your amount exceeds presale limit"
        );

        require(
            msg.value >= whitelistPrice * amount,
            "avax value is less than price"
        );
        require(
            (super.balanceOf(msg.sender) + amount) <= maxLimit,
            "You can't mint more than max limit"
        );

        for (uint256 i = 0; i < amount; i++) {
            mint();
        }

        (bool success, ) = manager.call{value: msg.value}("");
        require(success, "Failed to send AVAX");
    }

    function publicsaleMint(uint256 amount) public payable {
        require(
            msg.value >= publicSalePrice * amount,
            "avax value is less than price"
        );
        require(
            (super.balanceOf(msg.sender) + amount) <= maxLimit,
            "You can't mint more than max limit"
        );

        for (uint256 i = 0; i < amount; i++) {
            mint();
        }

        (bool success, ) = manager.call{value: msg.value}("");
        require(success, "Failed to send AVAX");
    }

    function presaleState() public view returns (bool) {
        if (_tokenIds.current() >= presaleLimit) return false;
        else return true;
    }

    function inWhitelist(bytes32[] calldata merkleProof)
        public
        view
        returns (bool)
    {
        return
            MerkleProof.verify(
                merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            );
    }

    function ownedAvatars(address purchaser)
        external
        view
        override
        returns (avatarDetail[] memory)
    {
        uint256 balance = super.balanceOf(purchaser);
        avatarDetail[] memory avatars = new avatarDetail[](balance);
        for (uint256 i = 0; i < balance; i++) {
            avatars[i] = avatarDetails[tokenOfOwnerByIndex(purchaser, i)];
        }
        return avatars;
    }

    function getAvatarDetail(uint256 id)
        external
        view
        override
        returns (avatarDetail memory)
    {
        return avatarDetails[id];
    }

    function stake(uint256 id, bool stakeStatus) external override {
        require(avatarDetails[id].id > 0, "Only minted avatar can be staked");
        require(msg.sender == stakingAddr, "EOA can't call this function");
        avatarDetails[id].staked = stakeStatus;
    }

    function changeAvatar(address holder, uint256 id) public onlyOwner {
        _tokenIds.increment();

        uint256 newNftId = _tokenIds.current();        

        _safeMint(holder, newNftId);

        IRandomizer(randomizer).removeBuffer(uint16(id));

        // set avatar details
        avatarDetails[newNftId].id = newNftId;
        avatarDetails[newNftId].avatarId = id;
        avatarDetails[newNftId].staked = false;
    }

    // Function to withdraw all AVAX from this contract.
    function withdraw() public onlyOwner nonReentrant {
        // get the amount of AVAX stored in this contract
        require(msg.sender == manager, "only manager can call withdraw");
        uint256 amount = address(this).balance;

        // send all AVAX to manager
        // manager can receive AVAX since the address of manager is payable
        (bool success, ) = manager.call{value: amount}("");
        require(success, "Failed to send AVAX");
    }

    function setRandomizer(address _randomizer) public onlyOwner {
        randomizer = _randomizer;
    }

    function setManager(address _manager) public onlyOwner {
        manager = payable(_manager);
    }

    function setBaseURI(string memory _baseUri) public onlyOwner {
        baseUri = _baseUri;
    }

    function setPriceByOwner(uint256 _whitelistPrice, uint256 _publicSalePrice)
        external
        onlyOwner
    {
        whitelistPrice = _whitelistPrice;
        publicSalePrice = _publicSalePrice;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setPresaleLimit(uint256 _presaleLimit) external onlyOwner {
        presaleLimit = _presaleLimit;
    }    

    function setMaxLimit(uint256 _maxLimit) external onlyOwner {
        maxLimit = _maxLimit;
    }  

    function setMaxTotal(uint256 _maxTotal) external onlyOwner {
        maxTotal = _maxTotal;
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        startTime = _startTime;
    }

    function setStakingAddr(address _stakingAddr) external onlyOwner {
        stakingAddr = _stakingAddr;
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return bytes(_baseURI()).length > 0 ? string(abi.encodePacked(_baseURI(), avatarDetails[tokenId].avatarId.toString(), ".json")) : "";
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
