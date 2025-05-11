//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import{IRebaseToken} from "./IRebaseToken.sol";
import {RebaseToken} from "./RebaseToken.sol";
contract Vault {
    error Vault__TrasnferFailed();
    event Deposit(address indexed user, uint256 value);
    event Redeem(address indexed user, uint256 _amount);
    IRebaseToken  private immutable i_rebaseToken;
//we need to pass the token address to the constructor
//create deposit function that mints tokens to the user
//create a redeem function that burns tokens from the user and sends the user ETH in return
//create a way to add rewards to the vault

constructor (IRebaseToken _rebaseToken){
    i_rebaseToken=_rebaseToken;
}
function deposit() external payable{
    //we need to use the amount of eth the user has sent to mint tokens to the user
    i_rebaseToken.mint(msg.sender,msg.value);
    emit Deposit(msg.sender,msg.value);
}
function redeem(uint256 _amount) external{
    //1.burn tokens of the user
    i_rebaseToken.burn(msg.sender,_amount);
    //2.send the user eth
   (bool success,) =payable(msg.sender).call{value: _amount}("");
   if(!success){
    revert Vault__TrasnferFailed();
   }
   emit Redeem(msg.sender,_amount);
    
}
receive()external payable{}
function getRebaseToken()external view returns (address){
    return address(i_rebaseToken);
}
}