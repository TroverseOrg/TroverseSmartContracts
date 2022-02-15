// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface INFTContract {
    function Mint(address _to, uint256 _quantity) external payable;
    function numberMinted(address owner) external view returns (uint256);
    function totalSupplyExternal() external view returns (uint256);
}


contract TroverseMinter is Ownable, ReentrancyGuard {

    INFTContract public NFTContract;

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant TOTAL_PLANETS = 10000;
    uint256 public constant MAX_MINT_PER_ADDRESS = 5;
    uint256 public constant RESERVED_PLANETS = 300;
    uint256 public constant RESERVED_OR_AUCTION_PLANETS = 7300;

    uint256 public constant AUCTION_START_PRICE = 1 ether;
    uint256 public constant AUCTION_END_PRICE = 0.1 ether;
    uint256 public constant AUCTION_PRICE_CURVE_LENGTH = 180 minutes;
    uint256 public constant AUCTION_DROP_INTERVAL = 20 minutes;
    uint256 public constant AUCTION_DROP_PER_STEP = 0.1 ether;

    uint256 public auctionSaleStartTime;
    uint256 public publicSaleStartTime;
    uint256 public whitelistPrice;
    uint256 public publicSalePrice;
    uint256 private publicSaleKey;

    mapping(address => uint256) public whitelist;

    uint256 public lastAuctionSalePrice = AUCTION_START_PRICE;
    mapping(address => uint256) public credits;
    EnumerableSet.AddressSet private _creditOwners;
    uint256 private _totalCredits = 0;
    uint256 private _totalCreditCount = 0;

    event CreditRefunded(address indexed owner, uint256 value);
    
    

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    constructor() { }

    /**
    * @dev Set the NFT contract address
    */
    function setNFTContract(address _NFTContract) external onlyOwner {
        NFTContract = INFTContract(_NFTContract);
    }

    /**
    * @dev Try to mint NFTs during the dutch auction sale
    *      Based on the price of last mint, extra credits could be refunded after the auction finshied
    *      Any extra funds will be transferred back to the sender's address
    */
    function auctionMint(uint256 quantity) external payable callerIsUser {
        require(auctionSaleStartTime != 0 && block.timestamp >= auctionSaleStartTime, "Sale has not started yet");
        require(totalSupply() + quantity <= RESERVED_OR_AUCTION_PLANETS, "Not enough remaining reserved for auction to support desired mint amount");
        require(numberMinted(msg.sender) + quantity <= MAX_MINT_PER_ADDRESS, "Can not mint this many");

        lastAuctionSalePrice = getAuctionPrice();
        uint256 totalCost = lastAuctionSalePrice * quantity;

        if (lastAuctionSalePrice > AUCTION_END_PRICE) {
            _creditOwners.add(msg.sender);

            credits[msg.sender] += totalCost;
            _totalCredits += totalCost;
            _totalCreditCount += quantity;
        }

        NFTContract.Mint(msg.sender, quantity);
        refundIfOver(totalCost);
    }
    
    /**
    * @dev Try to mint NFTs during the whitelist phase
    *      Any extra funds will be transferred back to the sender's address
    */
    function whitelistMint(uint256 quantity) external payable callerIsUser {
        require(whitelistPrice != 0, "Whitelist sale has not begun yet");
        require(whitelist[msg.sender] > 0, "Not eligible for whitelist mint");
        require(whitelist[msg.sender] >= quantity, "Can not mint this many");
        require(totalSupply() + quantity <= TOTAL_PLANETS, "Reached max supply");

        whitelist[msg.sender] -= quantity;
        NFTContract.Mint(msg.sender, quantity);
        refundIfOver(whitelistPrice * quantity);
    }

    /**
    * @dev Try to mint NFTs during the public sale
    *      Any extra funds will be transferred back to the sender's address
    */
    function publicSaleMint(uint256 quantity, uint256 key) external payable callerIsUser {
        require(publicSaleKey == key, "Called with incorrect public sale key");

        require(isPublicSaleOn(), "Public sale has not begun yet");
        require(totalSupply() + quantity <= TOTAL_PLANETS, "Reached max supply");
        require(numberMinted(msg.sender) + quantity <= MAX_MINT_PER_ADDRESS, "Can not mint this many");

        NFTContract.Mint(msg.sender, quantity);
        refundIfOver(publicSalePrice * quantity);
    }

    /**
    * @dev Try to transfer back extra funds, if the paying amount is more than the needed cost
    */
    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Insufficient funds");

        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    /**
    * @dev Check if the public sale is active
    */
    function isPublicSaleOn() public view returns (bool) {
        return publicSalePrice != 0 && block.timestamp >= publicSaleStartTime && publicSaleStartTime != 0;
    }

    /**
    * @dev Calculate auction price 
    */
    function getAuctionPrice() public view returns (uint256) {
        if (block.timestamp < auctionSaleStartTime) {
            return AUCTION_START_PRICE;
        }
        
        if (block.timestamp - auctionSaleStartTime >= AUCTION_PRICE_CURVE_LENGTH) {
            return AUCTION_END_PRICE;
        } else {
            uint256 steps = (block.timestamp - auctionSaleStartTime) / AUCTION_DROP_INTERVAL;
            return AUCTION_START_PRICE - (steps * AUCTION_DROP_PER_STEP);
        }
    }

    /**
    * @dev Set the dutch auction start time
    */
    function setAuctionSaleStartTime(uint256 timestamp) external onlyOwner {
        auctionSaleStartTime = timestamp;
    }

    /**
    * @dev Set the price for the whitlisted buyers
    *      Whitelist sale will be active if the price is not 0
    */
    function setWhitelistPrice(uint256 price) external onlyOwner {
        whitelistPrice = price;
    }

    /**
    * @dev Set the price for the public sale
    */
    function setPublicSalePrice(uint256 price) external onlyOwner {
        publicSalePrice = price;
    }

    /**
    * @dev Set the public sale start time
    */
    function setPublicSaleStartTime(uint256 timestamp) external onlyOwner {
        publicSaleStartTime = timestamp;
    }

    /**
    * @dev Set the key for accessing the public sale
    */
    function setPublicSaleKey(uint256 key) external onlyOwner {
        publicSaleKey = key;
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
    * @dev Mint the reserved planets, which will be used for promotions, marketing, strategic partnerships, giveaways, airdrops and also for Troverse team allocation
    */
    function reserveMint(uint256 quantity) external onlyOwner {
        require(totalSupply() + quantity <= RESERVED_PLANETS, "Too many already minted before dev mint");
        NFTContract.Mint(msg.sender, quantity);
    }

    /**
    * @dev Check if the auction refund price is finalized
    */
    function isAuctionPriceFinalized() public view returns(bool) {
        return totalSupply() >= RESERVED_OR_AUCTION_PLANETS || lastAuctionSalePrice == AUCTION_END_PRICE;
    }

    /**
    * @dev Get remaining credits to refund after the auction phase
    */
    function getRemainingCredits(address owner) external view returns(uint256) {
        if (credits[owner] > 0) {
            return credits[owner] - lastAuctionSalePrice * numberMinted(owner);
        }
        return 0;
    }
    
    /**
    * @dev Get total remaining credits to refund after the auction phase
    */
    function getTotalRemainingCredits() public view returns(uint256) {
        return _totalCredits - lastAuctionSalePrice * _totalCreditCount;
    }
    
    /**
    * @dev Get the maximum possible credits to refund after the auction phase
    */
    function getMaxPossibleCredits() public view returns(uint256) {
        if (isAuctionPriceFinalized()) {
            return getTotalRemainingCredits();
        }

        return _totalCredits - AUCTION_END_PRICE * _totalCreditCount;
    }

    /**
    * @dev Refund remaining credits after the auction phase
    */
    function refundRemainingCredits() external nonReentrant {
        require(isAuctionPriceFinalized(), "Auction price is not finalized yet!");
        require(_creditOwners.contains(msg.sender), "Not a credit owner!");
        
        uint256 remaininCredits = credits[msg.sender];
        uint256 remaininCreditCount = numberMinted(msg.sender);
        uint256 toSendCredits = remaininCredits - lastAuctionSalePrice * remaininCreditCount;

        require(toSendCredits > 0, "No credits to refund!");

        delete credits[msg.sender];

        _creditOwners.remove(msg.sender);

        _totalCredits -= remaininCredits;
        _totalCreditCount -= remaininCreditCount;

        emit CreditRefunded(msg.sender, toSendCredits);

        require(payable(msg.sender).send(toSendCredits));
    }

    /**
    * @dev Refund the remaining ethereum balance for unclaimed addresses
    */
    function refundAllRemainingCreditsByCount(uint256 count) external onlyOwner {
        require(isAuctionPriceFinalized(), "Auction price is not finalized yet!");
        
        address toSendWallet;
        uint256 toSendCredits;
        uint256 remaininCredits;
        uint256 remaininCreditCount;
        
        uint256 j = 0;
        while (_creditOwners.length() > 0 && j < count) {
            toSendWallet = _creditOwners.at(0);
            
            remaininCredits = credits[toSendWallet];
            remaininCreditCount = numberMinted(toSendWallet);
            toSendCredits = remaininCredits - lastAuctionSalePrice * remaininCreditCount;
            
            delete credits[toSendWallet];
            _creditOwners.remove(toSendWallet);

            if (toSendCredits > 0) {
                require(payable(toSendWallet).send(toSendCredits));
                emit CreditRefunded(toSendWallet, toSendCredits);

                _totalCredits -= toSendCredits;
                _totalCreditCount -= remaininCreditCount;
            }
            j++;
        }
    }
    
    /**
     * @dev Withdraw all collected funds excluding the remaining credits
     */
    function withdrawAll(address to) external onlyOwner {
        uint256 maxPossibleCredits = getMaxPossibleCredits();
        require(address(this).balance > maxPossibleCredits, "No funds to withdraw");

        uint256 toWithdrawFunds = address(this).balance - maxPossibleCredits;
        require(payable(to).send(toWithdrawFunds), "Transfer failed");
    }
    
    /**
     * @dev Get total mints by an address
     */
    function numberMinted(address owner) public view returns (uint256) {
        return NFTContract.numberMinted(owner);
    }

    /**
     * @dev Get total supply from NFT contract
     */
    function totalSupply() public view returns (uint256) {
        return NFTContract.totalSupplyExternal();
    }
}
