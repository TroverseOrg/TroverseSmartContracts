// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ERC721A.sol";


interface IYieldToken {
    function burn(address _from, uint256 _amount) external;
}


contract TroversePlanets is Ownable, ERC721A, ReentrancyGuard {

    uint256 public constant TOTAL_PLANETS = 10000;
    uint256 public constant MAX_MINT_PER_ADDRESS = 5;
    uint256 public constant RESERVED_PLANETS = 200;
    uint256 public constant RESERVED_OR_AUCTION_PLANETS = 7300;

    uint256 public constant AUCTION_START_PRICE = 1 ether;
    uint256 public constant AUCTION_END_PRICE = 0.1 ether;
    uint256 public constant AUCTION_PRICE_CURVE_LENGTH = 180 minutes;
    uint256 public constant AUCTION_DROP_INTERVAL = 20 minutes;
    uint256 public constant AUCTION_DROP_PER_STEP = 0.1 ether;

    string private _baseTokenURI;

    struct SaleConfig {
        uint32 auctionSaleStartTime;
        uint32 publicSaleStartTime;
        uint64 whitelistPrice;
        uint64 publicPrice;
        uint32 publicSaleKey;
    }

    SaleConfig public saleConfig;

    uint256 private _lastAuctionSalePrice = AUCTION_START_PRICE;
    mapping(address => uint256) public credits;
    mapping(address => uint256) public creditCount;
    uint256 private _totalCredits = 0;
    uint256 private _totalCreditCount = 0;

    bool private isRefundActive = false;

    mapping(address => uint256) public whitelist;


    IYieldToken public yieldToken;

    mapping (uint256 => string) private _planetName;
    mapping (string => bool) private _nameReserved;
    mapping (uint256 => string) private _planetDescription;

    uint256 public nameChangePrice = 100 ether;
    uint256 public descriptionChangePrice = 100 ether;

    event NameChanged(uint256 planetId, string planetName);
    event NameCleared(uint256 planetId);
    event DescriptionChanged(uint256 planetId, string planetDescription);
    event DescriptionCleared(uint256 planetId);
    

    constructor() ERC721A("Troverse Planets", "PLANET", MAX_MINT_PER_ADDRESS) { }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    /**
    * @dev Set the YieldToken address to be burnt for changing name or description
    */
    function setYieldToken(address yieldTokenAddress) external onlyOwner {
        yieldToken = IYieldToken(yieldTokenAddress);
    }
    
    /**
    * @dev Update the price for changing the planet's name
    */
    function updateNameChangePrice(uint256 price) external onlyOwner {
        nameChangePrice = price;
    }

    /**
    * @dev Update the price for changing the planet's description
    */
    function updateDescriptionChangePrice(uint256 price) external onlyOwner {
        descriptionChangePrice = price;
    }

    /**
    * @dev Change the name of a planet
    */
    function changeName(uint256 planetId, string memory newName) external {
        require(_msgSender() == ownerOf(planetId), "Caller is not the owner");
        require(validateName(newName) == true, "Not a valid new name");
        require(sha256(bytes(newName)) != sha256(bytes(_planetName[planetId])), "New name is same as the current one");
        require(isNameReserved(newName) == false, "Name already reserved");

        if (bytes(_planetName[planetId]).length > 0) {
                toggleReserveName(_planetName[planetId], false);
        }
        toggleReserveName(newName, true);

        yieldToken.burn(msg.sender, nameChangePrice);
        _planetName[planetId] = newName;

        emit NameChanged(planetId, newName);
    }

    /**
    * @dev Clear the name of a planet
    */
    function clearName(uint256 planetId) external onlyOwner {
        delete _planetName[planetId];
        emit NameCleared(planetId);
    }

    /**
    * @dev Change the description of a planet
    */
    function changeDescription(uint256 planetId, string memory newDescription) external {
        require(_msgSender() == ownerOf(planetId), "Caller is not the owner");

        yieldToken.burn(msg.sender, descriptionChangePrice);
        _planetDescription[planetId] = newDescription;

        emit DescriptionChanged(planetId, newDescription);
    }

    /**
    * @dev Clear the description of a planet
    */
    function clearDescription(uint256 planetId) external onlyOwner {
        delete _planetDescription[planetId];
        emit DescriptionCleared(planetId);
    }

    /**
    * @dev Change a name reserve state
    */
    function toggleReserveName(string memory name, bool isReserve) internal {
        _nameReserved[toLower(name)] = isReserve;
    }

    /**
    * @dev Returns name of the planet at index
    */
    function planetNameByIndex(uint256 index) public view returns (string memory) {
        return _planetName[index];
    }

    /**
    * @dev Returns description of the planet at index
    */
    function planetDescriptionByIndex(uint256 index) public view returns (string memory) {
        return _planetDescription[index];
    }

    /**
    * @dev Returns if the name has been reserved.
    */
    function isNameReserved(string memory nameString) public view returns (bool) {
        return _nameReserved[toLower(nameString)];
    }

    /**
    * @dev Validating a name string
    */
    function validateName(string memory newName) public pure returns (bool) {
        bytes memory b = bytes(newName);
        if (b.length < 1) return false;
        if (b.length > 25) return false; // Cannot be longer than 25 characters
        if (b[0] == 0x20) return false; // Leading space
        if (b[b.length - 1] == 0x20) return false; // Trailing space

        bytes1 lastChar = b[0];

        for(uint256 i; i < b.length; i++){
            bytes1 char = b[i];

            if (char == 0x20 && lastChar == 0x20) return false; // Cannot contain continous spaces

            if(
                !(char >= 0x30 && char <= 0x39) && //9-0
                !(char >= 0x41 && char <= 0x5A) && //A-Z
                !(char >= 0x61 && char <= 0x7A) && //a-z
                !(char == 0x20) //space
            )
            return false;

            lastChar = char;
        }

        return true;
    }

    /**
    * @dev Converts a string to lowercase
    */
    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
                if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                        bLower[i] = bytes1(uint8(bStr[i]) + 32);
                } else {
                        bLower[i] = bStr[i];
                }
        }
        return string(bLower);
    }

    /**
    * @dev Try to mint NFTs during the dutch auction sale
    *      Based on the price of last mint, extra credits could be refunded after the auction finshied
    *      Any extra funds will be transferred back to the sender's address
    */
    function auctionMint(uint256 quantity) external payable callerIsUser {
        uint256 _saleStartTime = uint256(saleConfig.auctionSaleStartTime);

        require(_saleStartTime != 0 && block.timestamp >= _saleStartTime, "sale has not started yet");
        require(totalSupply() + quantity <= RESERVED_OR_AUCTION_PLANETS, "not enough remaining reserved for auction to support desired mint amount");
        require(numberMinted(msg.sender) + quantity <= MAX_MINT_PER_ADDRESS, "can not mint this many");

        _lastAuctionSalePrice = getAuctionPrice(_saleStartTime);
        uint256 totalCost = _lastAuctionSalePrice * quantity;

        if (_lastAuctionSalePrice > AUCTION_END_PRICE) {
            credits[msg.sender] += totalCost;
            _totalCredits += totalCost;

            creditCount[msg.sender] += quantity;
            _totalCreditCount += quantity;
        }

        _safeMint(msg.sender, quantity);
        refundIfOver(totalCost);
    }
    
    /**
    * @dev Try to mint NFTs during the whitelist phase
    *      Any extra funds will be transferred back to the sender's address
    */
    function whitelistMint() external payable callerIsUser {
        uint256 price = uint256(saleConfig.whitelistPrice);

        require(price != 0, "Whitelist sale has not begun yet");
        require(whitelist[msg.sender] > 0, "not eligible for whitelist mint");
        require(totalSupply() + 1 <= TOTAL_PLANETS, "reached max supply");

        whitelist[msg.sender]--;
        _safeMint(msg.sender, 1);
        refundIfOver(price);
    }

    /**
    * @dev Try to mint NFTs during the public sale
    *      Any extra funds will be transferred back to the sender's address
    */
    function publicSaleMint(uint256 quantity, uint256 callerPublicSaleKey) external payable callerIsUser {
        SaleConfig memory config = saleConfig;
        uint256 publicSaleKey = uint256(config.publicSaleKey);
        uint256 publicPrice = uint256(config.publicPrice);
        uint256 publicSaleStartTime = uint256(config.publicSaleStartTime);
        
        require(publicSaleKey == callerPublicSaleKey, "called with incorrect public sale key");

        require(isPublicSaleOn(publicPrice, publicSaleKey, publicSaleStartTime), "public sale has not begun yet");
        require(totalSupply() + quantity <= TOTAL_PLANETS, "reached max supply");
        require(numberMinted(msg.sender) + quantity <= MAX_MINT_PER_ADDRESS, "can not mint this many");

        _safeMint(msg.sender, quantity);
        refundIfOver(publicPrice * quantity);
    }

    /**
    * @dev Try to transfer back extra funds, if the paying amount is more than the needed cost
    */
    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");

        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    /**
    * @dev Check if the public sale is active
    */
    function isPublicSaleOn(uint256 publicPriceWei, uint256 publicSaleKey, uint256 publicSaleStartTime) public view returns (bool) {
        return publicPriceWei != 0 && publicSaleKey != 0 && block.timestamp >= publicSaleStartTime;
    }

    /**
    * @dev Calculate auction price 
    */
    function getAuctionPrice(uint256 _saleStartTime) public view returns (uint256) {
        if (block.timestamp < _saleStartTime) {
            return AUCTION_START_PRICE;
        }
        
        if (block.timestamp - _saleStartTime >= AUCTION_PRICE_CURVE_LENGTH) {
            return AUCTION_END_PRICE;
        } else {
            uint256 steps = (block.timestamp - _saleStartTime) / AUCTION_DROP_INTERVAL;
            return AUCTION_START_PRICE - (steps * AUCTION_DROP_PER_STEP);
        }
    }

    /**
    * @dev Ending the dutch auction phase and setting up the whitelist and public sale
    */
    function endAuctionAndSetupNonAuctionSaleInfo(uint64 whitelistPriceWei, uint64 publicPriceWei, uint32 publicSaleStartTime) external onlyOwner {
        saleConfig = SaleConfig(0, publicSaleStartTime, whitelistPriceWei, publicPriceWei, saleConfig.publicSaleKey);
    }

    /**
    * @dev Set if buyer can now claim their extra funds from the auction phase
    */
    function setRefundActive(bool state) external onlyOwner {
        isRefundActive = state;
    }

    /**
    * @dev Set the dutch auction start time
    */
    function setAuctionSaleStartTime(uint32 timestamp) external onlyOwner {
        saleConfig.auctionSaleStartTime = timestamp;
    }

    /**
    * @dev Set the key for accessing the public sale
    */
    function setPublicSaleKey(uint32 key) external onlyOwner {
        saleConfig.publicSaleKey = key;
    }

    /**
    * @dev Adding or updating new whitelisted wallets
    */
    function addWhitelist(address[] memory addresses, uint256 limit) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = limit;
        }
    }

    /**
    * @dev Mint for marketing and giveaways
    */
    function reserveMint(uint256 quantity) external onlyOwner {
        require(totalSupply() + quantity <= RESERVED_PLANETS, "too many already minted before dev mint");
        require(quantity % maxBatchSize == 0, "can only mint a multiple of the maxBatchSize");

        uint256 numChunks = quantity / maxBatchSize;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(msg.sender, maxBatchSize);
        }
    }

    /**
    * @dev Get the price for refunding credits after the auction phase
    */
    function getCreditRefundPrice() public view returns(uint256) {
        return totalSupply() >= RESERVED_OR_AUCTION_PLANETS ? _lastAuctionSalePrice : AUCTION_END_PRICE;
    }

    /**
    * @dev Get remaining credits to refund after the auction phase
    */
    function getRemainingCredit(address owner) public view returns(uint256) {
        return credits[owner] - getCreditRefundPrice() * creditCount[owner];
    }
    
    /**
    * @dev Get total remaining credits to refund after the auction phase
    */
    function getTotalRemainingCredits() public view returns(uint256) {
        return _totalCredits - getCreditRefundPrice() * _totalCreditCount;
    }

    /**
    * @dev Refund remaining credits after the auction phase
    */
    function refundRemainingCredit() external payable nonReentrant {
        require(isRefundActive, "Auction price is not finalized yet!");
        
        uint256 remaininCredits = credits[msg.sender];
        uint256 remaininCreditCount = creditCount[msg.sender];
        uint256 toSendCredits = remaininCredits - getCreditRefundPrice() * remaininCreditCount;

        require(toSendCredits > 0, "No credits to refund!");

        delete credits[msg.sender];
        delete creditCount[msg.sender];

        _totalCredits -= remaininCredits;
        _totalCreditCount -= remaininCreditCount;

        require(payable(msg.sender).send(toSendCredits));
    }

    /**
     * @dev See {ERC721A-_baseURI}.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Set the base URI of the metadata
     */
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Withdraw an specific amount to an external address
     */
    function withdrawManual(address to, uint256 amount) external payable onlyOwner {
        require(to != address(0));
        require(payable(to).send(amount), "Transfer failed");
    }

    /**
     * @dev Withdraw all collected funds excluding the remaining credits
     */
    function withdrawAll(address to) external payable onlyOwner {
        uint256 totalRemainingCredits = getTotalRemainingCredits();
        require(address(this).balance > totalRemainingCredits, "No funds to withdraw");

        uint256 toWithdrawFunds = address(this).balance - totalRemainingCredits;
        require(payable(to).send(toWithdrawFunds), "Transfer failed");
    }

    /**
     * @dev See {ERC721A-_setOwnersExplicit}.
     */
    function setOwnersExplicit(uint256 quantity) external onlyOwner {
        _setOwnersExplicit(quantity);
    }

    /**
     * @dev Get total mints ba an address
     */
    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    /**
     * @dev Get ownership info of a planet
     */
    function getOwnershipData(uint256 tokenId) external view returns (TokenOwnership memory) {
        return ownershipOf(tokenId);
    }
}
