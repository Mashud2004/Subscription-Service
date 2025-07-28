// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract SubscriptionService is Ownable, ReentrancyGuard, Pausable {
    
    // Subscription Plan Structure
    struct Plan {
        uint256 price;        // Price in wei
        uint256 duration;     // Duration in seconds
        string name;          // Plan name
        bool active;          // Plan status
    }
    
    // User Subscription Structure
    struct Subscription {
        uint256 planId;       // Subscribed plan ID
        uint256 startTime;    // Subscription start time
        uint256 endTime;      // Subscription end time
        bool isActive;        // Current status
    }
    
    // State Variables
    mapping(uint256 => Plan) public plans;
    mapping(address => Subscription) public subscriptions;
    uint256 public planCount;
    uint256 public totalRevenue;
    
    // Events
    event PlanCreated(uint256 indexed planId, string name, uint256 price, uint256 duration);
    event SubscriptionCreated(address indexed user, uint256 indexed planId, uint256 endTime);
    event SubscriptionRenewed(address indexed user, uint256 indexed planId, uint256 newEndTime);
    event SubscriptionCancelled(address indexed user, uint256 indexed planId);
    event PlanUpdated(uint256 indexed planId, uint256 newPrice, bool active);
    event RevenueWithdrawn(address indexed owner, uint256 amount);
    
    constructor() Ownable(msg.sender) {
        // Create default plans
        _createPlan("Basic Monthly", 0.01 ether, 30 days);
        _createPlan("Premium Monthly", 0.02 ether, 30 days);
        _createPlan("Annual", 0.2 ether, 365 days);
    }
    
    /**
     * @dev Subscribe to a specific plan
     * @param _planId The ID of the plan to subscribe to
     */
    function subscribe(uint256 _planId) external payable nonReentrant whenNotPaused {
        require(_planId > 0 && _planId <= planCount, "Invalid plan ID");
        require(plans[_planId].active, "Plan is not active");
        require(msg.value >= plans[_planId].price, "Insufficient payment");
        require(!isSubscribed(msg.sender), "Already have active subscription");
        
        Plan memory plan = plans[_planId];
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + plan.duration;
        
        // Create subscription
        subscriptions[msg.sender] = Subscription({
            planId: _planId,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });
        
        // Update revenue
        totalRevenue += plan.price;
        
        // Refund excess payment
        if (msg.value > plan.price) {
            payable(msg.sender).transfer(msg.value - plan.price);
        }
        
        emit SubscriptionCreated(msg.sender, _planId, endTime);
    }
    
    /**
     * @dev Renew existing subscription
     */
    function renewSubscription() external payable nonReentrant whenNotPaused {
        Subscription storage userSub = subscriptions[msg.sender];
        require(userSub.planId > 0, "No existing subscription");
        
        Plan memory plan = plans[userSub.planId];
        require(plan.active, "Plan is no longer active");
        require(msg.value >= plan.price, "Insufficient payment");
        
        // Extend subscription from current end time or now (whichever is later)
        uint256 extensionStart = userSub.endTime > block.timestamp ? userSub.endTime : block.timestamp;
        userSub.endTime = extensionStart + plan.duration;
        userSub.isActive = true;
        
        // Update revenue
        totalRevenue += plan.price;
        
        // Refund excess payment
        if (msg.value > plan.price) {
            payable(msg.sender).transfer(msg.value - plan.price);
        }
        
        emit SubscriptionRenewed(msg.sender, userSub.planId, userSub.endTime);
    }
    
    /**
     * @dev Check if user has active subscription
     * @param _user Address to check
     * @return bool True if user has active subscription
     */
    function isSubscribed(address _user) public view returns (bool) {
        Subscription memory userSub = subscriptions[_user];
        return userSub.isActive && userSub.endTime > block.timestamp;
    }
    
    /**
     * @dev Get user's subscription details
     * @param _user Address to check
     * @return planId Plan ID, startTime Start timestamp, endTime End timestamp, active Status
     */
    function getSubscriptionDetails(address _user) external view returns (
        uint256 planId,
        uint256 startTime,
        uint256 endTime,
        bool active,
        string memory planName,
        uint256 timeRemaining
    ) {
        Subscription memory userSub = subscriptions[_user];
        bool isCurrentlyActive = isSubscribed(_user);
        
        planId = userSub.planId;
        startTime = userSub.startTime;
        endTime = userSub.endTime;
        active = isCurrentlyActive;
        planName = userSub.planId > 0 ? plans[userSub.planId].name : "";
        timeRemaining = isCurrentlyActive ? (userSub.endTime - block.timestamp) : 0;
    }
    
    /**
     * @dev Cancel subscription (user can call this)
     */
    function cancelSubscription() external {
        Subscription storage userSub = subscriptions[msg.sender];
        require(userSub.planId > 0, "No active subscription");
        require(userSub.isActive, "Subscription already cancelled");
        
        userSub.isActive = false;
        
        emit SubscriptionCancelled(msg.sender, userSub.planId);
    }
    
    /**
     * @dev Create or update subscription plans (Owner only)
     * @param _planId Plan ID to update (0 for new plan)
     * @param _name Plan name
     * @param _price Plan price in wei
     * @param _duration Plan duration in seconds
     * @param _active Plan status
     */
    function managePlan(
        uint256 _planId,
        string calldata _name,
        uint256 _price,
        uint256 _duration,
        bool _active
    ) external onlyOwner {
        require(_price > 0, "Price must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        
        if (_planId == 0) {
            // Create new plan
            _createPlan(_name, _price, _duration);
        } else {
            // Update existing plan
            require(_planId <= planCount, "Invalid plan ID");
            plans[_planId].name = _name;
            plans[_planId].price = _price;
            plans[_planId].duration = _duration;
            plans[_planId].active = _active;
            
            emit PlanUpdated(_planId, _price, _active);
        }
    }
    
    /**
     * @dev Withdraw contract revenue (Owner only)
     */
    function withdrawRevenue() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        payable(owner()).transfer(balance);
        emit RevenueWithdrawn(owner(), balance);
    }
    
    /**
     * @dev Internal function to create new plan
     */
    function _createPlan(string memory _name, uint256 _price, uint256 _duration) internal {
        planCount++;
        plans[planCount] = Plan({
            price: _price,
            duration: _duration,
            name: _name,
            active: true
        });
        
        emit PlanCreated(planCount, _name, _price, _duration);
    }
    
    /**
     * @dev Get all active plans information
     * @return planIds Array of plan IDs, names Array of plan names, prices Array of prices, durations Array of durations
     */
    function getActivePlans() external view returns (
        uint256[] memory planIds,
        string[] memory names,
        uint256[] memory prices,
        uint256[] memory durations
    ) {
        // Count active plans
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= planCount; i++) {
            if (plans[i].active) {
                activeCount++;
            }
        }
        
        // Initialize arrays
        planIds = new uint256[](activeCount);
        names = new string[](activeCount);
        prices = new uint256[](activeCount);
        durations = new uint256[](activeCount);
        
        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 1; i <= planCount; i++) {
            if (plans[i].active) {
                planIds[index] = i;
                names[index] = plans[i].name;
                prices[index] = plans[i].price;
                durations[index] = plans[i].duration;
                index++;
            }
        }
    }
    
    // Emergency functions
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // Get contract statistics
    function getContractStats() external view returns (
        uint256 totalPlans,
        uint256 contractBalance,
        uint256 totalEarned
    ) {
        totalPlans = planCount;
        contractBalance = address(this).balance;
        totalEarned = totalRevenue;
    }
}
