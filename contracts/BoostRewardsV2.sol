//SPDX-License-Identifier: MIT
/*
* MIT License
* ===========
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

pragma solidity 0.5.17;

import "./zeppelin/SafeMath.sol";
import "./zeppelin/Ownable.sol";
import "./zeppelin/SafeERC20.sol";
import "./IERC20Burnable.sol";
import "./ITreasury.sol";
import "./IUniswapRouter.sol";
import "./LPTokenWrapper.sol";


contract BoostRewardsV2 is LPTokenWrapper, Ownable {
    IERC20 public boostToken;
    address public treasury;
    address public treasurySetter;
    UniswapRouter public uniswapRouter;
    address public stablecoin;
    
    uint256 public constant MAX_NUM_BOOSTERS = 5;
    uint256 public tokenCapAmount;
    uint256 public starttime;
    uint256 public duration;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    
    // booster variables
    // variables to keep track of totalSupply and balances (after accounting for multiplier)
    uint256 public boostedTotalSupply;
    mapping(address => uint256) public boostedBalances;
    mapping(address => uint256) public numBoostersBought; // each booster = 5% increase in stake amt
    mapping(address => uint256) public nextBoostPurchaseTime; // timestamp for which user is eligible to purchase another booster
    uint256 public boosterPrice = PRECISION;
    uint256 internal constant PRECISION = 1e18;

    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);

    modifier checkStart() {
        require(block.timestamp >= starttime,"not start");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(
        uint256 _tokenCapAmount,
        IERC20 _stakeToken,
        IERC20 _boostToken,
        address _treasurySetter,
        UniswapRouter _uniswapRouter,
        uint256 _starttime,
        uint256 _duration
    ) public LPTokenWrapper(_stakeToken) {
        tokenCapAmount = _tokenCapAmount;
        boostToken = _boostToken;
        boostToken.approve(address(_uniswapRouter), uint256(-1));
        treasurySetter = _treasurySetter;
        uniswapRouter = _uniswapRouter;
        starttime = _starttime;
        duration = _duration;
    }
    
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (boostedTotalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(boostedTotalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            boostedBalances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public updateReward(msg.sender) checkStart {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);

        // check user cap
        require(
            balanceOf(msg.sender) <= tokenCapAmount || block.timestamp >= starttime.add(86400),
            "token cap exceeded"
        );

        // update boosted balance and supply
        updateBoostBalanceAndSupply(msg.sender);
        
        // transfer token last, to follow CEI pattern
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) checkStart {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        
        // update boosted balance and supply
        updateBoostBalanceAndSupply(msg.sender);
        
        stakeToken.safeTransfer(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            boostToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }
    
    function boost() external updateReward(msg.sender) checkStart {
        require(
            // 2 days after starttime
            block.timestamp > starttime.add(172800) &&
            block.timestamp > nextBoostPurchaseTime[msg.sender],
            "early boost purchase"
        );
        
        // increase next purchase eligibility by an hour
        nextBoostPurchaseTime[msg.sender] = block.timestamp.add(3600);
        
        // increase no. of boosters bought
        uint256 booster = numBoostersBought[msg.sender].add(1);
        numBoostersBought[msg.sender] = booster;
        require(booster <= MAX_NUM_BOOSTERS, "max boosters bought");

        // save current booster price, since transfer is done last
        booster = boosterPrice;
        // increase next booster price by 5%
        boosterPrice = boosterPrice.mul(105).div(100);
        
        // update boosted balance and supply
        updateBoostBalanceAndSupply(msg.sender);
        
        boostToken.safeTransferFrom(msg.sender, address(this), booster);
        
        IERC20Burnable burnableBoostToken = IERC20Burnable(address(boostToken));
        // if treasury not set, burn all
        if (treasury == address(0)) {
            burnableBoostToken.burn(booster);
            return;
        }

        // otherwise, burn 50%
        uint256 burnAmount = booster.div(2);
        burnableBoostToken.burn(burnAmount);
        booster = booster.sub(burnAmount);
        
        // swap to stablecoin, transferred to treasury
        address[] memory routeDetails = new address[](3);
        routeDetails[0] = address(boostToken);
        routeDetails[1] = uniswapRouter.WETH();
        routeDetails[2] = stablecoin;
        uniswapRouter.swapExactTokensForTokens(
            booster,
            0,
            routeDetails,
            treasury,
            block.timestamp + 100
        );
    }

    function notifyRewardAmount(uint256 reward)
        external
        onlyOwner
        updateReward(address(0))
    {
        rewardRate = reward.div(duration);
        lastUpdateTime = starttime;
        periodFinish = starttime.add(duration);
        emit RewardAdded(reward);
    }
    
    function setTreasury(address _treasury)
        external
    {
        require(msg.sender == treasurySetter, "only setter");
        treasury = _treasury;
        stablecoin = ITreasury(treasury).defaultToken();
        treasurySetter = address(0);
    }
    
    function updateBoostBalanceAndSupply(address user) internal {
         // subtract existing balance from boostedSupply
        boostedTotalSupply = boostedTotalSupply.sub(boostedBalances[user]);
        // calculate and update new boosted balance (user's balance has been updated by parent method)
        // each booster adds 5% to stake amount
        uint256 newBoostBalance = balanceOf(user).mul(numBoostersBought[user].mul(5).add(100)).div(100);
        boostedBalances[user] = newBoostBalance;
        // update boostedSupply
        boostedTotalSupply = boostedTotalSupply.add(newBoostBalance);
    }
}
