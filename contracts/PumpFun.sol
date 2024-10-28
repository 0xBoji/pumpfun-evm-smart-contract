// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);
}

contract PumpFun is ReentrancyGuard {
    receive() external payable {}

    address private owner;
    address private feeRecipient;
    uint256 private initialVirtualTokenReserves;
    uint256 private initialVirtualEthReserves;

    uint256 private tokenTotalSupply;
    uint256 private mcapLimit;
    uint256 private feeBasisPoint;
    uint256 private createFee;

    // Coinflip related variables
    uint256 private constant MINIMUM_BET = 0.01 ether;
    uint256 private constant MAXIMUM_BET = 1 ether;
    uint256 private nonce = 0;

    IUniswapV2Router02 private uniswapV2Router;
    address[] private allTokens;

    struct Profile {
        address user;
        Token[] tokens;
    }

    struct Token {
        address tokenMint;
        uint256 virtualTokenReserves;
        uint256 virtualEthReserves;
        uint256 realTokenReserves;
        uint256 realEthReserves;
        uint256 tokenTotalSupply;
        uint256 mcapLimit;
        bool complete;
    }

    struct Comment {
        address user;
        string message;
        uint256 timestamp;
    }

    struct TokenDetail {
        Token tokenInfo;
        Comment[] comments;
        address[] buyers;
        address[] sellers;
    }

    mapping (address => Token) public bondingCurve;
    mapping(address => TokenDetail) private tokenDetails;
    mapping(address => mapping(address => bool)) private hasTraded;
    

    event CreatePool(address indexed mint, address indexed user);
    event Complete(address indexed user, address indexed  mint, uint256 timestamp);
    event Trade(address indexed mint, uint256 ethAmount, uint256 tokenAmount, bool isBuy, address indexed user, uint256 timestamp, uint256 virtualEthReserves, uint256 virtualTokenReserves);
    event CoinFlipBet(address indexed player, uint256 amount, bool choice, bool result, uint256 timestamp);
    event CoinFlipWin(address indexed player, uint256 amount);

    modifier onlyOwner {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    constructor(
        address newAddr,
        uint256 feeAmt, 
        uint256 basisFee
    ){
        owner = msg.sender;
        feeRecipient = newAddr;
        createFee = feeAmt;
        feeBasisPoint = basisFee;
        initialVirtualTokenReserves = 10**27;
        initialVirtualEthReserves = 3*10**21;
        tokenTotalSupply = 10**27;
        mcapLimit = 10**23;
    }
        function createPool(
        address token,
        uint256 amount
    ) payable public {
        require(amount > 0, "CreatePool: Larger than Zero");
        require(feeRecipient != address(0), "CreatePool: Non Zero Address");
        require(msg.value >= createFee, "CreatePool: Value Amount");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        payable(feeRecipient).transfer(createFee);

        bondingCurve[token] = Token ({
            tokenMint: token,
            virtualTokenReserves: initialVirtualTokenReserves, 
            virtualEthReserves: initialVirtualEthReserves,
            realTokenReserves: amount,
            realEthReserves: 0,
            tokenTotalSupply: tokenTotalSupply,
            mcapLimit: mcapLimit,
            complete: false
        });

        allTokens.push(token);
        tokenDetails[token].tokenInfo = bondingCurve[token];

        emit CreatePool(token, msg.sender);
    }

    function buy(
        address token,
        uint256 amount,
        uint256 maxEthCost
    ) payable public {
        Token storage tokenCurve = bondingCurve[token];
        require(amount > 0, "Should Larger than zero");
        require(tokenCurve.complete == false, "Should Not Completed");

        uint256 featureAmount = tokenCurve.realTokenReserves - amount;
        uint256 featurePercentage = featureAmount * 100 / tokenCurve.tokenTotalSupply;
        require(featurePercentage > 20, "Buy Amount Over");

        uint256 ethCost = calculateEthCost(tokenCurve, amount);

        require(ethCost <= maxEthCost, "Max Eth Cost");

        uint256 feeAmount = feeBasisPoint * ethCost / 10000;
        uint256 ethAmount = ethCost- feeAmount;

        require(msg.value >= ethCost, "Exceed ETH Cost");

        payable(feeRecipient).transfer(feeAmount);

        IERC20(token).transfer(msg.sender, amount);

        if (!hasTraded[token][msg.sender]) {
            tokenDetails[token].buyers.push(msg.sender);
            hasTraded[token][msg.sender] = true;
        }

        tokenCurve.realTokenReserves -= amount;
        tokenCurve.virtualTokenReserves -= amount;
        tokenCurve.virtualEthReserves += ethAmount;
        tokenCurve.realEthReserves += ethAmount;

        uint256 mcap = tokenCurve.virtualEthReserves * tokenCurve.tokenTotalSupply / tokenCurve.realTokenReserves;
        uint256 percentage = tokenCurve.realTokenReserves * 100 / tokenCurve.tokenTotalSupply;

        if (mcap > tokenCurve.mcapLimit || percentage < 20) {
            tokenCurve.complete = true;
            
            emit Complete(msg.sender, token, block.timestamp);
        }

        emit Trade(token, ethCost, amount, true, msg.sender, block.timestamp, tokenCurve.virtualEthReserves, tokenCurve.virtualTokenReserves);
    }

    function sell(
        address token,
        uint256 amount,
        uint256 minEthOutput
    ) public {
        Token storage tokenCurve = bondingCurve[token];
        require(tokenCurve.complete == false, "Should Not Completed");
        require(amount > 0, "Should Larger than zero");

        uint256 ethCost = calculateEthCost(tokenCurve, amount);
        if (tokenCurve.realEthReserves < ethCost) {
            ethCost = tokenCurve.realEthReserves;
        }

        require(ethCost >= minEthOutput, "Should Be Larger than Min");

        uint256 feeAmount = feeBasisPoint * ethCost / 10000;

        payable(feeRecipient).transfer(feeAmount);
        payable(msg.sender).transfer(ethCost - feeAmount);

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        if (!hasTraded[token][msg.sender]) {
            tokenDetails[token].sellers.push(msg.sender);
            hasTraded[token][msg.sender] = true;
        }

        tokenCurve.realTokenReserves += amount;
        tokenCurve.virtualTokenReserves += amount;
        tokenCurve.virtualEthReserves -= ethCost;
        tokenCurve.realEthReserves -= ethCost;

        emit Trade(token, ethCost, amount, false, msg.sender, block.timestamp, tokenCurve.virtualEthReserves, tokenCurve.virtualTokenReserves);
    }


    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Other utility functions
    function withdraw(address token) public onlyOwner {
        Token storage tokenCurve = bondingCurve[token];
        require(tokenCurve.complete == true, "Should Be Completed");
        payable(owner).transfer(tokenCurve.realEthReserves);
        IERC20(token).transfer(owner, tokenCurve.realTokenReserves);
    }

    function calculateEthCost(Token memory token, uint256 tokenAmount) public pure returns (uint256) {
        uint256 virtualTokenReserves = token.virtualTokenReserves;
        uint256 pricePerToken = virtualTokenReserves - tokenAmount;
        uint256 totalLiquidity = token.virtualEthReserves * token.virtualTokenReserves;
        uint256 newEthReserves = totalLiquidity/pricePerToken;
        uint256 ethCost = newEthReserves - token.virtualEthReserves;
        return ethCost;
    }

    // Comment system functions
    function addComment(address token, string memory message) external {
        require(bytes(message).length > 0, "Comment cannot be empty");
        require(bytes(message).length <= 280, "Comment too long");
        
        Comment memory newComment = Comment({
            user: msg.sender,
            message: message,
            timestamp: block.timestamp
        });
        
        tokenDetails[token].comments.push(newComment);
    }

    function getTokenDetail(address token) external view returns (
        Token memory tokenInfo,
        Comment[] memory comments,
        address[] memory buyers,
        address[] memory sellers
    ) {
        TokenDetail storage detail = tokenDetails[token];
        return (
            detail.tokenInfo,
            detail.comments,
            detail.buyers,
            detail.sellers
        );
    }

    function getComments(address token) external view returns (Comment[] memory) {
        return tokenDetails[token].comments;
    }

    function getTraders(address token) external view returns (
        address[] memory buyers,
        address[] memory sellers
    ) {
        return (
            tokenDetails[token].buyers,
            tokenDetails[token].sellers
        );
    }

    // Setter functions
    function setFeeRecipient(address newAddr) external onlyOwner {
        require(newAddr != address(0), "Non zero Address");
        feeRecipient = newAddr;
    }
    
    function setOwner(address newAddr) external onlyOwner {
        require(newAddr != address(0), "Non zero Address");
        owner = newAddr;
    }

    function setInitialVirtualReserves(uint256 initToken, uint256 initEth) external onlyOwner {
        require(initEth > 0 && initToken > 0, "Should Larger than zero");
        initialVirtualTokenReserves = initToken;
        initialVirtualEthReserves = initEth;
    }

    function setTotalSupply(uint256 newSupply) external onlyOwner {
        require(newSupply > 0, "Should Larger than zero");
        tokenTotalSupply = newSupply;
    }

    function setMcapLimit(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "Should Larger than zero");
        mcapLimit = newLimit;
    }

    function setFeeAmount(uint256 newBasisPoint, uint256 newCreateFee) external onlyOwner {
        require(newBasisPoint > 0 && newCreateFee > 0, "Should Larger than zero");
        feeBasisPoint = newBasisPoint;
        createFee = newCreateFee;
    }

    // Getter functions
    function getCreateFee() external view returns(uint256){
        return createFee;
    }

    function getBondingCurve(address mint) external view returns (Token memory) {
        return bondingCurve[mint];
    }

    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }
}