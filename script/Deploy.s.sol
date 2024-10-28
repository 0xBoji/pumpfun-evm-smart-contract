// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/PumpFun.sol";
import "../contracts/TokenFactory.sol";

contract PumpFunFactory {
    event Deployed(address indexed pumpFun, address indexed tokenFactory);
    
    function deploy(
        address feeRecipient,
        uint256 feeAmount,
        uint256 basisFee
    ) external returns (address pumpFun, address tokenFactory) {
        // Deploy PumpFun
        PumpFun _pumpFun = new PumpFun(
            feeRecipient,
            feeAmount,
            basisFee
        );
        
        // Deploy TokenFactory
        TokenFactory _tokenFactory = new TokenFactory();
        
        // Set pool address in TokenFactory
        _tokenFactory.setPoolAddress(address(_pumpFun));
        
        emit Deployed(address(_pumpFun), address(_tokenFactory));
        
        return (address(_pumpFun), address(_tokenFactory));
    }
}