pragma solidity ^0.5.0;

import "github.com/OpenZeppelin/openzeppelin-contracts-ethereum-package/blob/master/contracts/token/ERC20/IERC20.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts-ethereum-package/blob/master/contracts/math/SafeMath.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol";
import "github.com/OpenZeppelin/openzeppelin-sdk/blob/6809ddbb8af07e9fcce99376cbbe75e542b50259/packages/lib/contracts/Initializable.sol";
import "./ICErc20.sol";

contract DaiPledge is Initializable, ReentrancyGuard {
    using SafeMath for uint256;
    
    uint256 private constant ETHER_IN_WEI = 1000000000000000000;
    
    /**
     * The Compound cToken that this contract is bound to.
     */
    ICErc20 public cToken;
    
    /**
     * The contract of a creator that holds the creator's pledges
     */
    mapping (address => address) public creatorContract;
    
    /**
     * The total of all balances for a creator
     */
    mapping (address => uint256) public creatorBalance;
    
    /**
     * The balance a user has pledged to a individual creator (user -> creator -> balance)
     */
     mapping(address => mapping(address => uint)) userPledgeBalance;
    
    /**
      * @notice Initializes a new DaiPledge contract.
      * @param _owner The owner of DaiPledge.  They are able to change settings and are set as the owner of DaiPledge.
      * @param _cToken The Compound Finance MoneyMarket contract to supply and withdraw tokens.
      * @param _feeFraction The fraction of the interest earned that should be transferred to the owner as the fee.  Is a fixed point 18 number.
      * @param _feeBeneficiary The address that will receive the fee fraction
      */
    function init (
        address _owner,
        address _cToken,
        uint256 _feeFraction,
        address _feeBeneficiary
    ) public initializer {
        require(_owner != address(0), "owner cannot be the null address");
        require(_cToken != address(0), "money market address is zero");
        cToken = ICErc20(_cToken);
        //_addAdmin(_owner);
        //_setNextFeeFraction(_feeFraction);
        //_setNextFeeBeneficiary(_feeBeneficiary);
    }
    
    /**
     * @notice Transfers tokens from the sender into the Compound cToken contract and updates the creatorBalance.
     * @param _amount The amount of the token underlying the cToken to deposit.
     * @param _creator The address of the creator being backed
     */
    function pledge(uint256 _amount, address _creator) public nonReentrant {
        require(_amount > 0, "deposit is not greater than zero");
        require(creatorContract[_creator] != address(0), "specified address is not a creator");
        
        // Transfer the tokens into this contract
        require(token().transferFrom(msg.sender, creatorContract[_creator], _amount), "token transfer failed");
        
        // Update the user's pledge balance
        userPledgeBalance[msg.sender][_creator] = userPledgeBalance[msg.sender][_creator].add(_amount);
        
        // Update the total of the creator's balance
        creatorBalance[_creator] = creatorBalance[_creator].add(_amount);
        
        // Deposit into Compound
        Creator(creatorContract[_creator]).deposit(_amount);
    }
    
    function withdrawPledge(uint256 _amount, address _creator) public nonReentrant {
        require(userPledgeBalance[msg.sender][_creator].sub(_amount) > 0, "attempting to withdraw more balance than exists");
        require(_amount > 0, "withdrawal is not greater than zero");
    
        // Update the user's balance
        userPledgeBalance[msg.sender][_creator] = userPledgeBalance[msg.sender][_creator].sub(_amount);
    
        // Update the total of this contract
        creatorBalance[_creator] = creatorBalance[_creator].sub(_amount);
        
        // Withdraw from Compound and transfer
        Creator(creatorContract[_creator]).withdraw(_amount, msg.sender);
    }
    
    
    function withdrawEarnings() public {
        require(creatorContract[msg.sender] != address(0), "specified address is not a creator");
        
        // Calculate the gross earnings
        uint256 underlyingBalance = balance(msg.sender);
        uint256 grossEarnings = underlyingBalance.sub(creatorBalance[msg.sender]);
        
        // Calculate the beneficiary fee
        // uint256 fee = calculateFee(draw.feeFraction, grossEarnings);
        
        // Update balance of the beneficiary
        // balances[draw.feeBeneficiary] = balances[draw.feeBeneficiary].add(fee);
        
        // Calculate the net earnings
        // uint256 netEarnings = grossEarnings.sub(fee);
        uint256 netEarnings = grossEarnings;
        
        // If there is a creator who is to receive non-zero earnings
        if (netEarnings != 0) {
          // Withdraw earnings
          Creator(creatorContract[msg.sender]).withdraw(netEarnings, msg.sender);
        }
    }
    
    function registerAsCreator() public {
        require(creatorContract[msg.sender] == address(0), "specified address is already a creator");
        creatorContract[msg.sender] = address(new Creator(address(cToken)));
    }
    
    /**
     * @notice Returns the underlying balance of the creater in the cToken.
     * @return The cToken underlying balance for the specified creator.
     */
    function balance(address _creator) public returns (uint256) {
        return cToken.balanceOfUnderlying(creatorContract[_creator]);
    }
    
    /**
     * @notice Returns the token underlying the cToken.
     * @return An ERC20 token address
     */
    function token() internal view returns (IERC20) {
        return IERC20(cToken.underlying());
    }

}

contract Creator is ReentrancyGuard {
    /**
    * The DaiPledge contract
    */
    address public owner;
    
    /**
     * The Compound cToken that this contract is bound to.
     */
    ICErc20 public cToken;

    constructor(address _cToken) public {
        owner = msg.sender;
        cToken = ICErc20(_cToken);
    }
    
    function deposit(uint256 _amount) public {
        require(msg.sender == owner, "Only DaiPledge can call this");
        require(token().approve(address(cToken), _amount), "could not approve money market spend");
        require(cToken.mint(_amount) == 0, "could not supply money market");
    }
    
    function withdraw(uint256 _amount, address _caller) public nonReentrant {
        require(msg.sender == owner, "Only DaiPledge can call this");
        require(_amount > 0, "withdrawal is not greater than zero");
        
        // Withdraw from Compound and transfer
        require(cToken.redeemUnderlying(_amount) == 0, "could not redeem from compound");
        require(token().transfer(_caller, _amount), "could not transfer winnings");
    }
    
    
    /**
     * @notice Returns the token underlying the cToken.
     * @return An ERC20 token address
     */
    function token() public view returns (IERC20) {
        return IERC20(cToken.underlying());
    }
}