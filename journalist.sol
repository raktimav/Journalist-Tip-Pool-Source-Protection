// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Journalist Tip Pool & Source Protection
 * @dev A smart contract system for anonymous journalist tipping and source protection
 */
contract Project {
    
    // Events
    event JournalistRegistered(address indexed journalist, string name);
    event TipSubmitted(bytes32 indexed tipId, address indexed journalist, uint256 amount);
    event TipWithdrawn(address indexed journalist, uint256 amount);
    event SourceProtected(bytes32 indexed sourceId, uint256 timestamp);
    
    // Structs
    struct Journalist {
        string name;
        string organization;
        bool isRegistered;
        uint256 totalTipsReceived;
        uint256 availableBalance;
        uint256 registrationTime;
    }
    
    struct AnonymousTip {
        bytes32 tipId;
        address journalist;
        uint256 amount;
        string encryptedMessage;
        uint256 timestamp;
        bool isWithdrawn;
    }
    
    struct ProtectedSource {
        bytes32 sourceId;
        bytes32 hashedIdentity;
        uint256 protectionLevel;
        uint256 timestamp;
        bool isActive;
    }
    
    // State variables
    mapping(address => Journalist) public journalists;
    mapping(bytes32 => AnonymousTip) public tips;
    mapping(bytes32 => ProtectedSource) public protectedSources;
    mapping(address => bytes32[]) public journalistTips;
    
    address public owner;
    uint256 public totalTipsPool;
    uint256 public platformFeePercentage = 2; // 2% platform fee
    uint256 public minimumTipAmount = 0.001 ether;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    modifier onlyRegisteredJournalist() {
        require(journalists[msg.sender].isRegistered, "Must be a registered journalist");
        _;
    }
    
    modifier validTipAmount() {
        require(msg.value >= minimumTipAmount, "Tip amount too small");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Core Function 1: Register a journalist in the system
     */
    function registerJournalist(string memory _name, string memory _organization) external {
        require(!journalists[msg.sender].isRegistered, "Journalist already registered");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_organization).length > 0, "Organization cannot be empty");
        
        journalists[msg.sender] = Journalist({
            name: _name,
            organization: _organization,
            isRegistered: true,
            totalTipsReceived: 0,
            availableBalance: 0,
            registrationTime: block.timestamp
        });
        
        emit JournalistRegistered(msg.sender, _name);
    }
    
    /**
     * @dev Core Function 2: Submit an anonymous tip to a journalist
     */
    function submitAnonymousTip(
        address _journalist, 
        string memory _encryptedMessage,
        bytes32 _sourceHash
    ) external payable validTipAmount {
        require(journalists[_journalist].isRegistered, "Target journalist not registered");
        require(bytes(_encryptedMessage).length > 0, "Message cannot be empty");
        
        // Generate unique tip ID (updated: using block.prevrandao instead of block.difficulty)
        bytes32 tipId = keccak256(abi.encodePacked(
            msg.sender, 
            _journalist, 
            block.timestamp, 
            block.prevrandao,
            _encryptedMessage
        ));
        
        // Calculate platform fee
        uint256 platformFee = (msg.value * platformFeePercentage) / 100;
        uint256 tipAmount = msg.value - platformFee;
        
        // Create anonymous tip
        tips[tipId] = AnonymousTip({
            tipId: tipId,
            journalist: _journalist,
            amount: tipAmount,
            encryptedMessage: _encryptedMessage,
            timestamp: block.timestamp,
            isWithdrawn: false
        });
        
        // Update journalist balance and stats
        journalists[_journalist].availableBalance += tipAmount;
        journalists[_journalist].totalTipsReceived += tipAmount;
        journalistTips[_journalist].push(tipId);
        
        // Update total tips pool
        totalTipsPool += tipAmount;
        
        // Protect source if hash provided
        if (_sourceHash != bytes32(0)) {
            _protectSource(_sourceHash, 3); // High protection level
        }
        
        emit TipSubmitted(tipId, _journalist, tipAmount);
    }
    
    /**
     * @dev Core Function 3: Withdraw accumulated tips (journalists only)
     */
    function withdrawTips(uint256 _amount) external onlyRegisteredJournalist {
        Journalist storage journalist = journalists[msg.sender];
        require(journalist.availableBalance > 0, "No tips available for withdrawal");
        
        uint256 withdrawAmount;
        if (_amount == 0) {
            withdrawAmount = journalist.availableBalance;
        } else {
            require(_amount <= journalist.availableBalance, "Insufficient balance");
            withdrawAmount = _amount;
        }
        
        // Update balances
        journalist.availableBalance -= withdrawAmount;
        totalTipsPool -= withdrawAmount;
        
        // Transfer funds
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "Withdrawal failed");
        
        emit TipWithdrawn(msg.sender, withdrawAmount);
    }
    
    /**
     * @dev Internal function to protect source identity
     */
    function _protectSource(bytes32 _sourceHash, uint256 _protectionLevel) internal {
        bytes32 sourceId = keccak256(abi.encodePacked(_sourceHash, block.timestamp));
        
        protectedSources[sourceId] = ProtectedSource({
            sourceId: sourceId,
            hashedIdentity: _sourceHash,
            protectionLevel: _protectionLevel,
            timestamp: block.timestamp,
            isActive: true
        });
        
        emit SourceProtected(sourceId, block.timestamp);
    }
    
    // View functions
    function getJournalistInfo(address _journalist) external view returns (
        string memory name,
        string memory organization,
        uint256 totalTipsReceived,
        uint256 availableBalance,
        uint256 registrationTime
    ) {
        Journalist memory j = journalists[_journalist];
        return (j.name, j.organization, j.totalTipsReceived, j.availableBalance, j.registrationTime);
    }
    
    function getTipInfo(bytes32 _tipId) external view returns (
        address journalist,
        uint256 amount,
        string memory encryptedMessage,
        uint256 timestamp,
        bool isWithdrawn
    ) {
        AnonymousTip memory tip = tips[_tipId];
        return (tip.journalist, tip.amount, tip.encryptedMessage, tip.timestamp, tip.isWithdrawn);
    }
    
    function getJournalistTipsCount(address _journalist) external view returns (uint256) {
        return journalistTips[_journalist].length;
    }
    
    function isSourceProtected(bytes32 _sourceHash) external view returns (bool, uint256) {
        bytes32 sourceId = keccak256(abi.encodePacked(_sourceHash, block.timestamp));
        ProtectedSource memory source = protectedSources[sourceId];
        return (source.isActive, source.protectionLevel);
    }
    
    // Owner functions
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance - totalTipsPool;
        require(balance > 0, "No platform fees to withdraw");
        
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Platform fee withdrawal failed");
    }
    
    function updateMinimumTip(uint256 _newMinimum) external onlyOwner {
        minimumTipAmount = _newMinimum;
    }
    
    // Emergency functions
    function emergencyPause() external onlyOwner {
        // Implementation for emergency pause functionality
    }
    
    // Fallback and receive functions
    receive() external payable {}
    
    fallback() external payable {
        revert("Function not found");
    }
}
