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
    
    address public contractAddress;
    address public taxAddress = 0x044421aAbF1c584CD594F9C10B0BbC98546CF8bc;
    
    struct TokenStructure {
        address tokenAddress;
        string tokenName;
        string tokenSymbol;
        string description;
    }

    TokenStructure[] public tokens;

    constructor() {}

    function deployERC20Token(
        string memory name,
        string memory ticker,
        string memory description
    ) public payable {
        Token token = new Token(name, ticker, INITIAL_SUPPLY);
        tokens.push(
            TokenStructure({
                tokenAddress: address(token),
                tokenName: name,
                tokenSymbol: ticker,
                description: description
            })
        );

        token.approve(contractAddress, INITIAL_SUPPLY);
        uint256 fee = IPumpFun(contractAddress).getCreateFee();

        require(msg.value >= fee, "Insufficient creation fee");
        IPumpFun(contractAddress).createPool{value: fee}(address(token), description);
    }

    function setPoolAddress(address newAddr) public {
        require(newAddr != address(0), "Non zero Address");
        contractAddress = newAddr;
    }
}