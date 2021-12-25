// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface IYieldToken {
    function burn(address _from, uint _amount) external;
}


contract TroversePlanets is ERC721Enumerable, Ownable, ReentrancyGuard {

    using Strings for uint;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    
	mapping (uint => string) private _planetName;
	mapping (string => bool) private _nameReserved;
	mapping (uint => string) private _planetDescription;
    
    IYieldToken public yieldToken;
    
    uint public nameChangePrice = 100 ether;
    uint public descriptionChangePrice = 100 ether;

    event NameChanged(uint planetId, string planetName);
    event DescriptionChanged(uint planetId, string planetDescription);
    

    uint public constant TOTAL_PLANETS = 10000;
    uint public constant RESERVED_PLANETS = 200;
    uint public constant MAX_UNITS_PER_TRANSACTION = 5;

    uint private _reservedMints = 0;

    uint public constant SALE_INITIAL_PRICE = 2 ether;
    uint public constant SALE_ENDING_PRICE = 0.2 ether;
    uint public constant SALE_DROP_PRICE = 0.1 ether;
    uint public constant SALE_DROP_PRICE_TIME = 5 minutes;
    uint public constant PRE_SALE_PRICE = 0.2 ether;

    uint private _lastAuctionSalePrice = SALE_INITIAL_PRICE;
    uint public auctionStartTime = 0;

    mapping(address => uint) public credits;
    mapping(address => uint) public creditCount;
    EnumerableSet.AddressSet private _creditOwners;
    uint private _totalCredits = 0;
    uint private _totalCreditCount = 0;

    EnumerableSet.AddressSet private _preSaleList;
    mapping(address => uint) private _preSaleCounts;

    EnumerableSet.AddressSet private _freeMintList;
    mapping(address => uint) private _freeMintCounts;

    bool private _preSaleOpen = false;
    bool private _freeMintOpen = false;

    string public baseURI;


    constructor() ERC721("Troverse Planets", "PLANET") { }
    

    /**
    * @dev Set the YieldToken address to be burnt for changing name or description
    * @param yieldTokenAddress new YieldToken address to be replaced
    */
    function setYieldToken(address yieldTokenAddress) external onlyOwner {
        yieldToken = IYieldToken(yieldTokenAddress);
    }
    
    /**
    * @dev Update the price for changing the planet's name
    * @param price New name change price
    */
	function updateNameChangePrice(uint price) external onlyOwner {
		nameChangePrice = price;
	}

    /**
    * @dev Update the price for changing the planet's description
    * @param price New description change price
    */
	function updateDescriptionChangePrice(uint price) external onlyOwner {
		descriptionChangePrice = price;
    }

    /**
    * @dev Change the name of a planet
    * @param planetId Target Planet NFT ID
    * @param newName The new name of the planet
    */
    function changeName(uint planetId, string memory newName) external {
		require(_msgSender() == ownerOf(planetId), "ERC721: caller is not the owner");
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
    * @dev Change the description of a planet
    * @param planetId Target Planet NFT ID
    * @param newDescription The new description of the planet
    */
    function changeDescription(uint planetId, string memory newDescription) external {
        require(_msgSender() == ownerOf(planetId), "ERC721: caller is not the owner");

        yieldToken.burn(msg.sender, descriptionChangePrice);
        _planetDescription[planetId] = newDescription;

        emit DescriptionChanged(planetId, newDescription);
    }

	/**
	 * @dev Change a name reserve state
	 * @param name Target reserve name
	 * @param isReserve The new reserve state
	 */
	function toggleReserveName(string memory name, bool isReserve) internal {
		_nameReserved[toLower(name)] = isReserve;
	}

	/**
	 * @dev Returns name of the planet at index
     * @param index Target planet index
	 */
	function planetNameByIndex(uint index) public view returns (string memory) {
		return _planetName[index];
	}

	/**
	 * @dev Returns description of the planet at index
     * @param index Target planet index
	 */
	function planetDescriptionByIndex(uint index) public view returns (string memory) {
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
    * @param newName Target name to be validated
    */
	function validateName(string memory newName) public pure returns (bool) {
		bytes memory b = bytes(newName);
		if (b.length < 1) return false;
		if (b.length > 25) return false; // Cannot be longer than 25 characters
		if (b[0] == 0x20) return false; // Leading space
		if (b[b.length - 1] == 0x20) return false; // Trailing space

		bytes1 lastChar = b[0];

		for(uint i; i < b.length; i++){
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
	 * @param str Target string to be converted to lowercase
	 */
	function toLower(string memory str) public pure returns (string memory) {
		bytes memory bStr = bytes(str);
		bytes memory bLower = new bytes(bStr.length);
		for (uint i = 0; i < bStr.length; i++) {
			// Uppercase character
			if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
				bLower[i] = bytes1(uint8(bStr[i]) + 32);
			} else {
				bLower[i] = bStr[i];
			}
		}
		return string(bLower);
	}

    /**
    * @dev Get number of reserved NFTs which will be used for gifts or giveaways
    */
    function getTotalReservedMints() private view returns(uint) {
        return _reservedMints > RESERVED_PLANETS ? _reservedMints : RESERVED_PLANETS;
    }

    /**
    * @dev Get number of NFTs which are minted or reserved
    */
    function getMintedOrReservedPlanets() private view returns(uint) {
        return totalSupply() + getTotalReservedMints() - _reservedMints;
    }

    /**
    * @dev Get remaining number of NFTs which can be minted in the public sale
    */
    function getRemainingPlanets() public view returns(uint) {
        return TOTAL_PLANETS - getMintedOrReservedPlanets();
    }

    /**
    * @dev Check if the public sale auction is sold-out
    */
    function isAuctionSoldOut() private view returns(bool) {
        return getRemainingPlanets() == 0;
    }

    /**
    * @dev List all eligible addresses for the free-mint
    */
    function FreeMintList() public view returns (address[] memory) {
        return _freeMintList.values();
    }

    /**
    * @dev List all eligible addresses for the pre-sale
    */
    function PreSaleList() public view returns (address[] memory) {
        return _preSaleList.values();
    }

    /**
    * @dev Add eligible addresses for the free-mint
    * @param list List of addresses to be added for the free-mint
    * @param limit Number of eligible mints per address
    */
    function addFreeMintList(address[] memory list, uint limit) external onlyOwner {
        for (uint i; i < list.length; i++) {
            if (!_freeMintList.contains(list[i])) {
                _freeMintList.add(list[i]);
            }
            _freeMintCounts[list[i]] += limit;
        }
    }

    /**
    * @dev Add eligible addresses for the pre-sale
    * @param list List of addresses to be added for the pre-sale
    * @param limit Number of eligible mints per address
    */
    function addPreSaleList(address[] memory list, uint limit) external onlyOwner {
        for (uint i; i < list.length; i++) {
            if (!_preSaleList.contains(list[i])) {
                _preSaleList.add(list[i]);
            }
            _preSaleCounts[list[i]] += limit;
        }
    }

    /**
    * @dev Returns how many NFTs can be free-minted by an address
    * @param owner The target address
    */
    function getFreeMintCount(address owner) public view returns (uint) {
        return _freeMintCounts[owner];
    }

    /**
    * @dev Returns how many NFTs can be minted during pre-sale by an address
    * @param owner The target address
    */
    function getPreSaleCount(address owner) public view returns (uint) {
        return _preSaleCounts[owner];
    }

    /**
    * @dev Mint for gifts and giveaways
    * @param to The target address
    * @param count The number of NFTs to be minted
    */
    function reserveMint(address to, uint count) external onlyOwner {
        uint lastTotalSupply = totalSupply();
        require(lastTotalSupply + count <= TOTAL_PLANETS);
        
        for (uint i; i < count; i++) {
            _safeMint(to, lastTotalSupply + i);
            _reservedMints++;
        }
    }

    /**
    * @dev Try to free-mint NFTs if the sender is whitelisted
    * @param count The number of NFTs to be minted
    */
    function freeMint(uint count) external nonReentrant {
        uint lastTotalSupply = totalSupply();

        require(isFreeMintOpen(), "Free mint is currently closed");
        require(lastTotalSupply + count <= TOTAL_PLANETS);
        require(_freeMintList.contains(msg.sender), "You are not on the free-mint whitelist");
        require(count <= _freeMintCounts[msg.sender], "Exceeded allowed amount");

        _freeMintCounts[msg.sender] -= count;
        
        for (uint i; i < count; i++) {
            _safeMint(msg.sender, lastTotalSupply + i);
            _reservedMints++;
        }
    }

    /**
    * @dev Try to mint NFTs during the pre-sale if the sender is whitelisted
    *      Any extra funds will be transferred back to the sender's address
    * @param count The number of NFTs to be minted
    */
    function preSale(uint count) external payable nonReentrant {
        require(isPreSaleOpen(), "Pre sale is currently closed");
        require(!isAuctionSoldOut(), "Sold-out!");
        require(_preSaleList.contains(msg.sender), "You are not on the pre-sale whitelist");
        require(count <= _preSaleCounts[msg.sender], "Exceeded allowed amount");

        uint requiredFunds = PRE_SALE_PRICE * count;
        require(msg.value >= requiredFunds, "Insufficient ether");

        _preSaleCounts[msg.sender] -= count;
        
        uint lastTotalSupply = totalSupply();
        for (uint i; i < count; i++) {
            _safeMint(msg.sender, lastTotalSupply + i);
        }

        if (msg.value > requiredFunds) {
            require(payable(msg.sender).send(msg.value - requiredFunds));
        }
    }

    /**
    * @dev Try to mint NFTs during the public sale
    *      During the dutch auction phase, credits can be considered for future mints until it has been sold-out
    *      Any extra funds will be transferred back to the sender's address
    * @param count The number of NFTs to be minted
    */
    function sale(uint count) external payable nonReentrant {
        require(isSaleOpen(), "Sale is currently closed");
        require(!isAuctionSoldOut(), "Sold-out!");

        count = count <= getRemainingPlanets() ? count : getRemainingPlanets();
        require(count <= MAX_UNITS_PER_TRANSACTION, "Can mint up to 5");

        uint currentSalePrice = getAuctionPrice();
        uint requiredFunds = currentSalePrice * count;
        uint remainingCredits = getRemainingCredit(msg.sender);

        if (remainingCredits > 0) {
            if (remainingCredits >= requiredFunds) {
                requiredFunds = 0;
            } else {
                requiredFunds -= remainingCredits;
            }
        }
        
        require(msg.value >= requiredFunds, "Insufficient funds");

        _lastAuctionSalePrice = currentSalePrice;
        
        if (currentSalePrice > SALE_ENDING_PRICE) {
            _creditOwners.add(msg.sender);
            
            credits[msg.sender] += requiredFunds;
            _totalCredits += requiredFunds;

            creditCount[msg.sender] += count;
            _totalCreditCount += count;
        }
        
        uint lastTotalSupply = totalSupply();
        for (uint i; i < count; i++) {
            _safeMint(msg.sender, lastTotalSupply + i);
        }

        if (msg.value > requiredFunds) {
            require(payable(msg.sender).send(msg.value - requiredFunds));
        }
    }

    /**
    * @dev Get the refundable amount in the auction for an address
    * @param owner The target address
    */
    function getRemainingCredit(address owner) public view returns(uint) {
        return credits[owner] - getCreditRefundPrice() * creditCount[owner];
    }

    /**
    * @dev Get the refundable amount in the auction for all addresses
    */
    function getTotalRemainingCredits() public view returns(uint) {
        return _totalCredits - getCreditRefundPrice() * _totalCreditCount;
    }

    /**
    * @dev Set pre-sale state
    * @param state New state
    */
    function setPreSaleOpen(bool state) external onlyOwner {
        _preSaleOpen = state;
    }

    /**
    * @dev Set free-mint state
    * @param state New state
    */
    function setFreeMintOpen(bool state) external onlyOwner {
        _freeMintOpen = state;
    }

    /**
    * @dev Check if the pre-sale is started
    */
    function isPreSaleOpen() public view returns(bool) {
        return _preSaleOpen;
    }

    /**
    * @dev Check if the pre-sale is started
    */
    function isFreeMintOpen() public view returns(bool) {
        return _freeMintOpen;
    }

    /**
    * @dev Check if the sale is started
    */
    function isSaleOpen() public view returns(bool) {
        return block.timestamp >= auctionStartTime && auctionStartTime > 0;
    }

    /**
    * @dev Set the auction start time
    * @param time Start time
    */
    function setSaleTime(uint time) external onlyOwner {
        auctionStartTime = time;
    }
    
    /**
    * @dev Calculate auction price on current time.
    */
    function getAuctionPrice() public view returns(uint) {
        return getPriceOnTime(block.timestamp);
    }
	
    /**
    * @dev Calculate auction price with a timestamp
    * @param time The target timestamp
    */
    function getPriceOnTime(uint time) public view returns(uint) {
        if(time < auctionStartTime) {
            return SALE_INITIAL_PRICE;
        }

        uint maxRange = (SALE_INITIAL_PRICE - SALE_ENDING_PRICE) / SALE_DROP_PRICE;
        uint currentRange = (time - auctionStartTime) / SALE_DROP_PRICE_TIME;

        if(currentRange >= maxRange) {
            return SALE_ENDING_PRICE;
        }

        return SALE_INITIAL_PRICE - (currentRange * SALE_DROP_PRICE);
    }

    /**
    * @dev Get the auction refund price at this moment
    */
    function getCreditRefundPrice() public view returns(uint) {
        return isAuctionSoldOut() ? _lastAuctionSalePrice : getAuctionPrice();
    }

    /**
    * @dev Check if the auction refund price is finalized
    */
    function isAuctionPriceFinalized() internal view returns(bool) {
         return isAuctionSoldOut() || getAuctionPrice() <= SALE_ENDING_PRICE;
    }

    /**
    * @dev List the tokens owned by an address
    * @param owner The target address
    */
    function tokensOfOwner(address owner) public view returns (uint[] memory) {
        uint count = balanceOf(owner);
        uint[] memory ids = new uint[](count);
        for (uint i; i < count; i++) {
            ids[i] = tokenOfOwnerByIndex(owner, i);
        }
        return ids;
    }

    /**
    * @dev Update the metadata with a new URI
    * @param newBaseURI New BaseURI
    */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    /**
    * @dev See {IERC721Metadata-_baseURI}.
    */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
    * @dev Refund the remaining ethereum balance if the auction price is finalized
    */
    function refundRemainingCredit() external payable nonReentrant {
        require(isAuctionPriceFinalized(), "Auction price is not finalized yet!");
        require(_creditOwners.contains(msg.sender), "Not a credit owner!");
        
        uint toSendCredits = getRemainingCredit(msg.sender);
        require(toSendCredits > 0, "No credits to refund!");

        _creditOwners.remove(msg.sender);

        credits[msg.sender] -= toSendCredits;
        _totalCredits -= toSendCredits;
        require(payable(msg.sender).send(toSendCredits));
    }
    
    /**
    * @dev Withdraw a specific amount of funds from the smart contract to an address
    * @param to The target address
    * @param amount Amount to be withdrawn
    */
    function withdraw(address to, uint amount) public payable onlyOwner {
        require(to != address(0));
        require(payable(to).send(amount));
    }

    /**
    * @dev Withdraw all eligible funds to an address
    * @param to The target address
    */
    function withdrawAll(address to) external payable onlyOwner {
        uint toWithdrawFunds = address(this).balance - getTotalRemainingCredits();
        require(toWithdrawFunds > 0);

        withdraw(to, toWithdrawFunds);
    }
}
