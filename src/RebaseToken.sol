// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Shoaib Khan
 * @notice This is a cross-chain rebase token incentivises uses to deposit into a vault and gain interest in rewards
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    ///////////////
    //  Errors   //
    ///////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 s_interestRate, uint256 _newInterestRate);

    /////////////////////
    // State Variables //
    /////////////////////
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;

    ///////////////
    //  Events   //
    ///////////////
    event InterestRateSet(uint256 newInterestRate);

    ///////////////
    // Functions //
    ///////////////
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    ////////////////////////
    // External Functions //
    ////////////////////////

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @param _newInterestRate The new interest rate to be set
     * @notice set the interest rate in the contract
     * @dev The interest rate can only be decreased
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user. This is the number of tokens that have currently been minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol.
     * @param _user The user to get the principle balance for
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     *
     * @param _to The address of the user to mint the tokens to
     * @param _amount  The amount of tokens to mint
     * @notice mint the user tokens when they deposit into the vault
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _from The address of the user to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * calculate the balance for the user including the interest that has accumulated since the last update
     * (principle balance) + some interest that has accrued
     * @param _user The user to calculate the balance for
     * @return The balance of the user including the interest that has accumulated since the last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (The numbers of tokens that have actually been minted to the user)
        // multiply the priciple balance by the interest that has accumulated in the time since balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return true if the transfer was successful
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
     * @notice Transfer tokens from one user to another
     * @param _sender The user to transfer the tokens from
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return true if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /////////////////////////////////////////
    /// Private & Internal View Functions ///
    /////////////////////////////////////////

    /**
     * @dev returns the interest accrued since the last update of the user's balance - aka since the last time the interest accrued was minted to the user.
     * @return linearInterest the interest accrued since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // principle amount(1 + (user interest rate * time elapsed))
        // deposit: 10 tokens
        // interest rate: 0.5 tokens per seconds
        // time elapsed is 2 seconds
        // 10 + (10 * 0.5 * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        linearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
        return linearInterest;
    }

    /**
     * @param _user The user to mint the accrued interest to
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (eg. mint, burn, transfer)
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> Principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimeStamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /////////////////////////////////////////
    /// Public & External View Functions  ///
    /////////////////////////////////////////

    /**
     * @param _user The address of the user
     * @return The interest rate of the user
     * @notice The interest rate is the global interest rate at the time of depositing
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        // get the user interest rate
        return s_userInterestRate[_user];
    }

    /**
     * @notice get the interest rate that is currently set for the contract. Any future depositors will recieve this interest rate
     * @return The ineterst rate for the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
