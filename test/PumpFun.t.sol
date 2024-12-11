// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PumpFun.sol";
import "../contracts/TokenFactory.sol";
import "../contracts/Token.sol";

contract PumpFunTest is Test {
    receive() external payable {}
    fallback() external payable {}

    PumpFun public pumpFun;
    TokenFactory public tokenFactory;
    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;

    uint256 constant POOL_CREATE_FEE = 0.1 ether;
    uint256 constant TOKEN_CREATE_FEE = 0.01 ether;
    uint256 constant BASIS_FEE = 100; // 1%
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**18;

    event CreatePool(address indexed mint, address indexed user);
    event Trade(address indexed mint, uint256 ethAmount, uint256 tokenAmount, bool isBuy, address indexed user, uint256 timestamp, uint256 virtualEthReserves, uint256 virtualTokenReserves);

    function setUp() public {
        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        pumpFun = new PumpFun(
            feeRecipient,
            POOL_CREATE_FEE,
            BASIS_FEE
        );

        tokenFactory = new TokenFactory();
        tokenFactory.setPoolAddress(address(pumpFun));
        tokenFactory.setCreationFee(TOKEN_CREATE_FEE);

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
    }

    function createTestToken(
        address creator,
        string memory name, 
        string memory symbol, 
        string memory description
    ) internal returns (address) {
        uint256 totalFee = tokenFactory.getTotalFeeRequired();
        console.log("Total fee required:", totalFee);
        
        vm.startPrank(creator);
        
        uint256 creatorBalance = creator.balance;
        console.log("Creator balance:", creatorBalance);
        require(creatorBalance >= totalFee, "Insufficient creator balance");

        console.log("PumpFun address:", address(pumpFun));
        console.log("TokenFactory address:", address(tokenFactory));
        console.log("Creator address:", creator);

        try tokenFactory.deployERC20Token{value: totalFee}(
            name,
            symbol,
            description
        ) {
            console.log("Token deployment successful");
        } catch Error(string memory reason) {
            console.log("Token deployment failed:", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("Token deployment failed with low-level error");
            revert("Low level error in token deployment");
        }
        
        // Get the newly created token address
        address[] memory tokens = pumpFun.getAllTokens();
        require(tokens.length > 0, "No token created");
        address tokenAddress = tokens[tokens.length - 1];
        console.log("Token created at:", tokenAddress);

        // Log token state
        Token token = Token(tokenAddress);
        console.log("Token balance of creator:", token.balanceOf(creator));
        console.log("Token balance of PumpFun:", token.balanceOf(address(pumpFun)));
        
        vm.stopPrank();
        return tokenAddress;
    }

    function test_CreateToken() public {
        console.log("Starting test_CreateToken");
        console.log("Initial state:");
        console.log("PumpFun address:", address(pumpFun));
        console.log("TokenFactory address:", address(tokenFactory));
        console.log("User1 address:", user1);
        console.log("Owner address:", owner);
        console.log("FeeRecipient address:", feeRecipient);

        vm.startPrank(user1);
        uint256 totalFee = tokenFactory.getTotalFeeRequired();
        assertEq(totalFee, POOL_CREATE_FEE + TOKEN_CREATE_FEE, "Total fee should match");
        
        address tokenAddress = createTestToken(
            user1,
            "Test Token",
            "TEST",
            "This is a test token"
        );

        // Log final state
        Token token = Token(tokenAddress);
        console.log("Final token balances:");
        console.log("PumpFun balance:", token.balanceOf(address(pumpFun)));
        console.log("Creator balance:", token.balanceOf(user1));
        
        address[] memory allTokens = pumpFun.getAllTokens();
        assertEq(allTokens.length, 1, "Should have one token");
        assertEq(token.balanceOf(address(pumpFun)), INITIAL_SUPPLY, "PumpFun should have all tokens");
        
        vm.stopPrank();
    }

    function test_BuyTokens() public {
        // First create a token
        address tokenAddress = createTestToken(
            user1,
            "Test Token",
            "TEST",
            "This is a test token"
        );

        // User2 buys tokens
        vm.startPrank(user2);
        uint256 buyAmount = 1000 * 10**18;
        
        // Calculate the exact ETH cost
        PumpFun.Token memory tokenInfo = pumpFun.getBondingCurve(tokenAddress);
        uint256 ethCost = pumpFun.calculateEthCost(tokenInfo, buyAmount);
        uint256 maxEthCost = ethCost * 11 / 10; // Allow 10% slippage
        
        // Calculate fee
        uint256 feeAmount = (ethCost * BASIS_FEE) / 10000;
        uint256 netEthAmount = ethCost - feeAmount;

        vm.expectEmit(true, true, false, true);
        emit Trade(
            tokenAddress, 
            ethCost, 
            buyAmount, 
            true, 
            user2, 
            block.timestamp, 
            tokenInfo.virtualEthReserves + netEthAmount,
            tokenInfo.virtualTokenReserves - buyAmount
        );
        
        pumpFun.buy{value: maxEthCost}(
            tokenAddress,
            buyAmount,
            maxEthCost
        );

        tokenInfo = pumpFun.getBondingCurve(tokenAddress);
        assertGt(tokenInfo.realEthReserves, 0, "Should have ETH reserves");
        assertLt(tokenInfo.realTokenReserves, 1_000_000 * 10**18, "Should have less tokens");
        
        vm.stopPrank();
    }

    function test_AddComment() public {
        // Fund the test contract (owner) directly
        vm.deal(address(this), 10 ether);
        
        // Create token first
        vm.startPrank(user1);
        uint256 totalFee = tokenFactory.getTotalFeeRequired();
        
        // Deploy token directly
        tokenFactory.deployERC20Token{value: totalFee}(
            "Test Token",
            "TEST",
            "This is a test token"
        );

        // Get the token address
        address[] memory tokens = pumpFun.getAllTokens();
        require(tokens.length > 0, "No token created");
        address tokenAddress = tokens[0];
        
        vm.stopPrank();

        // Add comment
        vm.startPrank(user2);
        pumpFun.addComment(tokenAddress, "Great token!");
        vm.stopPrank();

        // Verify comment
        PumpFun.Comment[] memory comments = pumpFun.getComments(tokenAddress);
        assertEq(comments.length, 1, "Should have one comment");
        assertEq(comments[0].user, user2, "Comment should be from user2");
        assertEq(comments[0].message, "Great token!", "Comment message should match");
    }

    function test_KingOfHill() public {
        // Create two tokens
        address token1 = createTestToken(
            user1,
            "Token1",
            "TK1",
            "First token"
        );
        
        address token2 = createTestToken(
            user1,
            "Token2",
            "TK2",
            "Second token"
        );

        // Buy tokens to increase market cap
        vm.startPrank(user2);
        uint256 buyAmount = 5_000 * 10**18;
        
        // Buy token1
        PumpFun.Token memory token1Info = pumpFun.getBondingCurve(token1);
        uint256 ethCost1 = pumpFun.calculateEthCost(token1Info, buyAmount);
        uint256 maxEthCost1 = ethCost1 * 11 / 10;
        
        pumpFun.buy{value: maxEthCost1}(
            token1,
            buyAmount,
            maxEthCost1
        );

        // Check if token1 is king
        (,,,,bool isKing1) = pumpFun.getTokenProgress(token1);
        assertTrue(isKing1, "Token1 should be king");

        // Buy more of token2
        PumpFun.Token memory token2Info = pumpFun.getBondingCurve(token2);
        uint256 largerAmount = buyAmount * 2;
        uint256 ethCost2 = pumpFun.calculateEthCost(token2Info, largerAmount);
        uint256 maxEthCost2 = ethCost2 * 12 / 10;

        vm.deal(user2, maxEthCost2);
        
        pumpFun.buy{value: maxEthCost2}(
            token2,
            largerAmount,
            maxEthCost2
        );

        // Check if token2 is now king
        (,,,,bool isKing2) = pumpFun.getTokenProgress(token2);
        assertTrue(isKing2, "Token2 should be king");
        
        // Token1 should no longer be king
        (,,,,bool isKing1After) = pumpFun.getTokenProgress(token1);
        assertFalse(isKing1After, "Token1 should no longer be king");
        
        vm.stopPrank();
    }

    function test_GetTokenDetails() public {
        // Create token
        address tokenAddress = createTestToken(
            user1,
            "Test Token",
            "TEST",
            "Test description"
        );

        // Get token details
        (
            PumpFun.Token memory tokenInfo,
            uint256 bondingCurveProgress,
            uint256 kingOfHillProgress,
            uint256 currentMcap,
            uint256 ethInCurve
        ) = pumpFun.getTokenDetails(tokenAddress);

        assertEq(tokenInfo.tokenMint, tokenAddress, "Token address should match");
        assertEq(tokenInfo.tokenTotalSupply, 1_000_000 * 10**18, "Total supply should be 1M");
        
        uint256 expectedInitialMcap = (tokenInfo.virtualEthReserves * tokenInfo.tokenTotalSupply) / tokenInfo.realTokenReserves;
        uint256 expectedProgress = (expectedInitialMcap * 100) / tokenInfo.mcapLimit;
        
        assertEq(bondingCurveProgress, expectedProgress, "Initial progress should match expected");
        assertEq(kingOfHillProgress, 0, "Initial king progress should be 0");
    }

    function testFail_InsufficientFee() public {
        vm.startPrank(user1);
        uint256 insufficientFee = POOL_CREATE_FEE + TOKEN_CREATE_FEE - 0.001 ether;
        
        tokenFactory.deployERC20Token{value: insufficientFee}(
            "Test Token",
            "TEST",
            "This should fail"
        );
        vm.stopPrank();
    }

    function testFuzz_InvalidTokenSupply(uint256 wrongSupply) public {
        vm.assume(wrongSupply != INITIAL_SUPPLY);
        vm.startPrank(user1);
        
        // Deploy a token with wrong supply
        Token wrongToken = new Token(
            "Wrong", 
            "WRG", 
            wrongSupply
        );
        
        // Fund user1 with enough ETH for the pool creation fee
        vm.deal(user1, POOL_CREATE_FEE);

        // Approve tokens
        wrongToken.approve(address(pumpFun), wrongSupply);

        // Try to create pool with wrong supply token
        vm.expectRevert("Invalid token supply");
        pumpFun.createPool{value: POOL_CREATE_FEE}(
            address(wrongToken),
            "This should fail"
        );
        
        vm.stopPrank();
    }
} 