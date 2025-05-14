//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
/**
 * @title Cross-chain Rebase Token
 * @author Nikola Andreev
 * @notice This is cross-chain rebase token , that incetivises users to deposit
 * into a vualt and gain interest in rewards
 * @notice interest rate in this contract can only decrease
 * @notice each user will have their own interest rate that is global interest
 * rate at the time they have deposited
 */

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 interestRate, uint256 newInterestRate);

    event NewInterestRate(uint256 indexed newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1 * 10 ** 18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }
    /**
     * @notice set the interest rate in contract
     * @param _newInterestRate the new interest rate to set
     * @dev the interest rate can only decrease
     */

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit NewInterestRate(_newInterestRate);
    }
    /**
     * @notice The principle balance of a user.This is the number of tokens that have currently been minted
     * to the user not inlcuding any interest that has accrued since the last time user interacted with the
     * protocol
     * @param _user the user to get the balance for
     */

    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The user to mint the tokens to
     * @param _amount The amount of tokens to mint
     */

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // If this is the user's first interaction, initialize their timestamp
        if (s_userLastUpdatedTimestamp[_to] == 0) {
            s_userLastUpdatedTimestamp[_to] = block.timestamp;
        }
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }
    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The user to burn tokens from
     * @param _amount The amount of tokens to burn
     */

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }
    /**
     * @notice Calculate the balance of the user plus the interest that has accumulated since
     * the last update
     * (principle balance) + some interest that has accrued
     * @param _user The user to calculate balance for
     * @return uint256 the balance of the user including the interest that he accumulated since
     * the last update
     */

    function balanceOf(address _user) public view override returns (uint256) {
        //get the current principle balance of the user
        //(the number of tokens that have actually been minted to the user)
        //multiply the principle balance by the interest that has accumulated
        //in the time since the balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }
    /**
     * @notice transfer tokens from one user to another
     * @param _recipient The user to transfer tokens to
     * @param _amount The amount of tokens to transfer
     */

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }
    /**
     * @notice sends tokens from one user to another
     * @param _from The user who tokens are being sent from
     * @param _to The user who tokens are being sent to
     * @param _amount The amount of tokens being sent
     * @return bool returns true if tx successful
     */

    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRate[_to] = s_userInterestRate[msg.sender];
        }
        return super.transferFrom(_from, _to, _amount);
    }
    /**
     * @notice calculate the interest that has accumulated since the last update
     * @param _user the user to calculate the interest accumulated for
     * @return linearInterest the interest that has accumulated since the last update
     */

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        //we need to calculate the interest that has accumulated since the last update
        //this is going to be linear growth over time
        //1.calculate the time since the last update
        //2.calculate amount of linear growth
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }
    /**
     * @notice mint the accrued interest to the user since the last time they interacted with the protocol(e.g. mint,burn,transfer)
     * @param _user the user to mint the accrued interest to
     */

    function _mintAccruedInterest(address _user) internal {
        //(1)find their current balance of rebase token that have been minted - principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        //(2)calculate their current balance including any interest - balanceOf
        uint256 currentBalance = balanceOf(_user);
        //calculate the number of tokens that need to be minted to the user-> (2)-(1)
        uint256 numberOfTokens = currentBalance - previousPrincipleBalance;
        //call _mint to mint tokens to the user
        _mint(_user, numberOfTokens);
        // Update the user's last updated timestamp to reflect this most recent time their interest was minted to them.
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }
    /**
     * @notice get the interest rate for the conctract
     * @return uint256 returns interest rate of the contract
     */

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
    /**
     * @notice gets the interest rate for the user
     * @param _user the user to get the interest rate for
     */

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
    function principalBalanceOf(address _user) external view returns(uint256){
        return super.balanceOf(_user);
    }
}
