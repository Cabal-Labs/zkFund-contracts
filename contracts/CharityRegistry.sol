// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IFundToken.sol";

import {IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {TransactionHelper, Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";





contract CharityRegistry is ReentrancyGuard, Ownable, IPaymaster {

    using SafeMath for uint256;

    uint256 constant PRICE_FOR_PAYING_FEES = 1;
    address public allowedTokenForFees;

    uint256 public feesPool;
    mapping(uint256 => bool) public isCharityIntoPool;
    uint256[] public charitiesIds;

    //TODO: Add check for donations into paymaster
    struct Charity {
        uint256 id;
        mapping(address => uint256) donationPools;
        mapping(address => bool) userHasDonated;
        string name;
        string info;
        address wallet;
        bool isRemoved;
        bool isEmergencyStopEnabled;
        bool isDonationReleasePaused;
    }

    struct TokenDonationPool {
        address token;
        uint256 amount;
    }

    mapping(address => bool) private whitelistedTokensM;

    mapping(uint256 => Charity) public charities;

    event CharityAdded(uint256 indexed id, string name, address indexed wallet, string indexed info);
    event CharityUpdated(uint256 indexed id, string name, address indexed wallet);
    event DonationMade(uint256 charityId, address donor, uint256 amount);
    event DonationsReleased(uint256 charityId, address wallet, uint256 amount);
    event CharityRemoved(uint256 id);
    event EmergencyStopEnabled(uint256 id);
    event EmergencyStopDisabled(uint256 id);

    address public votingContract;

    address[] public whitelistedTokens;

    constructor(address _votingContract, address _erc20) Ownable(){
        votingContract = _votingContract;
        allowedTokenForFees = _erc20;
        feesPool = 0;
    }

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        // Continue execution if called from the bootloader.
        _;
    }

    modifier onlyVotingContract() {
        require(msg.sender == votingContract, "Only voting contract can call this function");
        _;
    }

    function checkPoolUserDonation(address _user) private view returns (bool) {
        for (uint256 i = 0; i < charitiesIds.length; i++) {
            Charity storage charity = charities[charitiesIds[i]];
            if (charity.userHasDonated[_user]) {
                if(isCharityIntoPool[charity.id]){
                    return true;
                }
            }
        }
        return false;
    }

    function validateCharity(uint256 _charityId) private view returns (Charity storage) {
        Charity storage charity = charities[_charityId];
        require(charity.id != 0, "Charity does not exist");
        require(!charity.isRemoved, "Charity has been removed");
        return charity;
    }


    function addCharity(uint256 _id, string memory _name, address _wallet, string memory _info) external onlyVotingContract {
        require(charities[_id].id == 0, "Charity already exists");

        Charity storage newCharity = charities[_id];
        newCharity.id = _id;
        newCharity.name = _name;
        newCharity.info = _info;
        newCharity.wallet = _wallet;
        newCharity.isRemoved = false;
        newCharity.isEmergencyStopEnabled = false;
        newCharity.isDonationReleasePaused = false;
        charitiesIds.push(_id);
        
        emit CharityAdded(_id, _name, _wallet, _info);
    }

    function updateCharity(uint256 _charityId, string memory _name, address _wallet) external onlyVotingContract {
        Charity storage charity = validateCharity(_charityId);
        charity.name = _name;
        charity.wallet = _wallet;
        emit CharityUpdated(_charityId, _name, _wallet);
    }

    function removeCharity(uint256 _charityId) external onlyVotingContract {
        Charity storage charity = validateCharity(_charityId);
        charity.isRemoved = true;
        emit CharityRemoved(_charityId);
    }

    function enableEmergencyStop(uint256 _charityId) external onlyVotingContract {
        Charity storage charity = validateCharity(_charityId);
        charity.isEmergencyStopEnabled = true;
        emit EmergencyStopEnabled(_charityId);
    }

    function disableEmergencyStop(uint256 _charityId) external onlyVotingContract {
        Charity storage charity = validateCharity(_charityId);
        charity.isEmergencyStopEnabled = false;
        emit EmergencyStopDisabled(_charityId);
    }


    function isTokenWhitelisted(address _token) public view returns (bool) {
        return whitelistedTokensM[_token];
    }

    function addTokenToWhitelist(address _token) external onlyVotingContract {
        require(!isTokenWhitelisted(_token), "Token is already whitelisted");
        whitelistedTokensM[_token] = true;
        whitelistedTokens.push(_token);
    }

    function removeWhitelistedToken(address _token) external onlyVotingContract {
        uint256 tokenIndex = whitelistedTokens.length; // Set to an invalid index initially
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            if (whitelistedTokens[i] == _token) {
                tokenIndex = i;
                break;
            }
        }

        require(tokenIndex != whitelistedTokens.length, "Token not found in the whitelist");

        whitelistedTokens[tokenIndex] = whitelistedTokens[whitelistedTokens.length - 1];

    
        whitelistedTokens.pop();
        whitelistedTokensM[_token] = false;
    }

    function makeDonation(uint256 _charityId, address _token, uint256 _amount) external {
        require(isTokenWhitelisted(_token), "Token is not whitelisted");
        IERC20 token = IERC20(_token);

        Charity storage charity = validateCharity(_charityId);
        require(!charity.isEmergencyStopEnabled, "Charity has been paused due to emergency");

        require(token.transferFrom(msg.sender, address(this), _amount), "Token transfer failed");
        charity.donationPools[_token] = charity.donationPools[_token].add(_amount);

        if (isCharityIntoPool[_charityId]) {
            IFundToken fundToken = IFundToken(allowedTokenForFees);
            fundToken.mint(msg.sender);
            
        }
        emit DonationMade(_charityId, msg.sender, _amount);
    }

    function withdrawDonations(uint256 _charityId, address _token, uint256 _amount) external nonReentrant {
        require(isTokenWhitelisted(_token), "Token is not whitelisted");
        IERC20 token = IERC20(_token);
        Charity storage charity = validateCharity(_charityId);
        require(charity.wallet == msg.sender, "Only charity wallet can withdraw");
        require(_amount <= charity.donationPools[_token], "Amount requested exceeds donation pool");
        require(token.transfer(charity.wallet, _amount), "Token transfer failed");
        charity.donationPools[_token] = charity.donationPools[_token].sub(_amount); 
        emit DonationsReleased(_charityId, charity.wallet, _amount);
    }

    function getCharity(uint256 _charityId) external view returns (
        uint256 id,
        string memory name,
        string memory info,
        address wallet,
        bool isRemoved,
        bool isEmergencyStopEnabled,
        bool isDonationReleasePaused
    ) {
        Charity storage charity = charities[_charityId];
        require(charity.id != 0, "Charity does not exist");

        return (
            charity.id,
            charity.name,
            charity.info,
            charity.wallet,
            charity.isRemoved,
            charity.isEmergencyStopEnabled,
            charity.isDonationReleasePaused
        );
    }

    function getDonationPools(uint256 _charityId) external view returns (TokenDonationPool[] memory) {
        Charity storage charity = charities[_charityId];
        require(charity.id != 0, "Charity does not exist");

        TokenDonationPool[] memory donationPools = new TokenDonationPool[](whitelistedTokens.length);

        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            donationPools[i] = TokenDonationPool({
                token: whitelistedTokens[i],
                amount: charity.donationPools[whitelistedTokens[i]]
            });
        }

        return donationPools;
    }

    function getIntoFeePool(uint256 _charityId, uint256 _amount) public {
        Charity storage charity = validateCharity(_charityId);
        IERC20 token = IERC20(whitelistedTokens[0]);
        require(charity.wallet == msg.sender, "Only charity wallet can get into fee pool");
        require(token.transferFrom(msg.sender, address(this), _amount), "Token transfer failed");
        feesPool = feesPool.add(_amount);
        isCharityIntoPool[_charityId] = true;

    }




    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable returns (bytes4 magic, bytes memory context) {
        // By default we consider the transaction as accepted.
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        require(_transaction.paymasterInput.length >= 4, "The standard paymaster input must be at least 4 bytes long");

        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
        if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
            // While the transaction data consists of address, uint256 and bytes data,
            // the data is not needed for this paymaster
            (address token, uint256 amount, bytes memory data) = abi.decode(
                _transaction.paymasterInput[4:],
                (address, uint256, bytes)
            );

            // Verify if token is the correct one
            require(token == allowedTokenForFees, "Invalid token");

            // We verify that the user has provided enough allowance
            address userAddress = address(uint160(_transaction.from));

            address thisAddress = address(this);

            uint256 providedAllowance = IERC20(token).allowance(
                userAddress,
                thisAddress
            );
            require(
                providedAllowance >= PRICE_FOR_PAYING_FEES,
                "Min allowance too low"
            );

            // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
            // neither paymaster nor account are allowed to access this context variable.
            uint256 requiredETH = _transaction.gasLimit *
                _transaction.maxFeePerGas;

            try
                IERC20(token).transferFrom(userAddress, thisAddress, amount)
            {} catch (bytes memory revertReason) {
                // If the revert reason is empty or represented by just a function selector,
                // we replace the error with a more user-friendly message
                if (revertReason.length <= 4) {
                    revert("Failed to transferFrom from users' account");
                } else {
                    assembly {
                        revert(add(0x20, revertReason), mload(revertReason))
                    }
                }
            }
            require(requiredETH <= feesPool, "Not enough ETH in the fees pool");
            require(checkPoolUserDonation(userAddress), "User has not donated to any charity from the paymaster pool  ");
            // The bootloader never returns any data, so it can safely be ignored here.
            (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
                value: requiredETH
            }("");
            require(success, "Failed to transfer funds to the bootloader");
        } else {
            revert("Unsupported paymaster flow");
        }
    }
    

    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32,
        bytes32,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable override {
        // Refunds are not supported yet.
    }

    receive() external payable {}

}