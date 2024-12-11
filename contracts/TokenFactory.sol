// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./Token.sol";
interface IPumpFun {
    function createPool(
        address token,
        string memory description
    ) external payable;
    function getCreateFee() external view returns(uint256);
}

contract TokenFactory {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18; // 1 million tokens with 18 decimals
    uint256 public tokenCreationFee = 0.01 ether; // Initial creation fee (can be updated by owner)
    
    address public contractAddress;
    address public owner;
    
    struct TokenStructure {
        address tokenAddress;
        string tokenName;
        string tokenSymbol;
        string description;
    }

    TokenStructure[] public tokens;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokenCreated(address indexed tokenAddress, string name, string symbol, address indexed creator);
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function deployERC20Token(
        string memory name,
        string memory ticker,
        string memory description
    ) public payable {
        require(contractAddress != address(0), "PumpFun address not set");
        
        // Check if total fee is sufficient
        uint256 poolFee = IPumpFun(contractAddress).getCreateFee();
        require(msg.value >= tokenCreationFee + poolFee, "Insufficient fee");

        // Create token and mint to this contract
        Token token = new Token(name, ticker, INITIAL_SUPPLY);
        
        // Store token info
        tokens.push(
            TokenStructure({
                tokenAddress: address(token),
                tokenName: name,
                tokenSymbol: ticker,
                description: description
            })
        );

        // Send creation fee to owner
        (bool success, ) = owner.call{value: tokenCreationFee}("");
        require(success, "Fee transfer failed");

        // Approve PumpFun to spend tokens
        require(token.approve(contractAddress, INITIAL_SUPPLY), "PumpFun approval failed");

        // Create pool
        IPumpFun(contractAddress).createPool{value: poolFee}(
            address(token),
            description
        );

        emit TokenCreated(address(token), name, ticker, msg.sender);
    }

    function setPoolAddress(address newAddr) public onlyOwner {
        require(newAddr != address(0), "Non zero Address");
        contractAddress = newAddr;
    }

    function setCreationFee(uint256 newFee) public onlyOwner {
        emit CreationFeeUpdated(tokenCreationFee, newFee);
        tokenCreationFee = newFee;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getDeployedTokens() external view returns (TokenStructure[] memory) {
        return tokens;
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner).transfer(balance);
    }

    function getTotalFeeRequired() public view returns (uint256) {
        return tokenCreationFee + IPumpFun(contractAddress).getCreateFee();
    }
}