// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for interacting with the CharityRegistry contract from the RequestCharities contract
interface ICharityRegistry {
    function addCharity(uint256 _id, string memory _name, address _wallet, string memory _info) external;
    function addTokenToWhitelist(address _token) external;
    
}