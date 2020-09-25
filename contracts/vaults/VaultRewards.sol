// //SPDX-License-Identifier: MIT
// /*
// * MIT License
// * ===========
// *
// * Permission is hereby granted, free of charge, to any person obtaining a copy
// * of this software and associated documentation files (the "Software"), to deal
// * in the Software without restriction, including without limitation the rights
// * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// * copies of the Software, and to permit persons to whom the Software is
// * furnished to do so, subject to the following conditions:
// *
// * The above copyright notice and this permission notice shall be included in all
// * copies or substantial portions of the Software.
// *
// * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// */

// pragma solidity 0.5.17;

// import "../SafeMath.sol";
// import "../zeppelin/Ownable.sol";
// import "../zeppelin/SafeERC20.sol";
// import "../IERC20Burnable.sol";
// import "../ITreasury.sol";
// import "./IVault.sol";
// import "../ISwapRouter.sol";
// import "../LPTokenWrapper.sol";


// contract VaultRewards is LPTokenWrapper, Ownable {
//     struct EpochRewards {
//         uint256 rewardsAvailable;
//         uint256 rewardsClaimed;
//         uint256 rewardPerToken;
//         mapping(address => uint256) userRewardPerTokenPaid;
//         mapping(address => uint256) rewardsClaimable;
//     }

//     IERC20 public boostToken;
//     IERC20 public rewardToken;
//     address public treasury;
//     SwapRouter public swapRouter;
    
//     EpochRewards public previousEpoch;
//     EpochRewards public currentEpoch;
    
//     uint256 public constant EPOCH_DURATION = 4 weeks;
//     // booster variables
//     // variables to keep track of totalSupply and balances (after accounting for multiplier)
//     uint256 public boostedTotalSupply;
//     mapping(address => uint256) public boostedBalances;
//     mapping(address => uint256) public numBoostersBought; // each booster = 5% increase in stake amt
//     uint256 internal constant PRECISION = 1e18;

//     event RewardAdded(uint256 reward);
//     event RewardPaid(address indexed user, uint256 reward);

//     constructor(
//         IERC20 _stakeToken, // bf-token
//         IERC20 _boostToken,
//         address _treasury,
//         SwapRouter _swapRouter
//     ) public LPTokenWrapper(_stakeToken) {
//         boostToken = _boostToken;
//         rewardToken = IVault(address(_stakeToken)).token();
//         boostToken.approve(address(_swapRouter), uint256(-1));
//         treasury = _treasury;
//         swapRouter = _swapRouter;
//     }

//     // stake visibility is public as overriding LPTokenWrapper's stake() function
//     function stake(uint256 amount) public {
//         require(amount > 0, "Cannot stake 0");
//         updateUserReward(msg.sender);
//         super.stake(amount);

//         // update boosted balance and supply
//         updateBoostBalanceAndSupply(msg.sender);
        
//         // transfer token last, to follow CEI pattern
//         stakeToken.safeTransferFrom(msg.sender, address(this), amount);
//     }

//     function earned(address user) external view returns (uint256) {
//         return (block.timestamp > currentEpochStarttime + EPOCH_DURATION) ?
//             _earned(user, currentEpoch) :
//             _earned(user, previousEpoch).add(_earned(user, currentEpoch));
//     }

//     function getReward(address user) external {
//         updateUserReward(user);
//         _getReward(user);
//     }

//     function withdraw(uint256 amount) public {
//         require(amount > 0, "Cannot withdraw 0");
//         updateUserReward(msg.sender);
//         _getReward(msg.sender);
//         super.withdraw(amount);
        
//         // update boosted balance and supply
//         updateBoostBalanceAndSupply(msg.sender);
        
//         stakeToken.safeTransfer(msg.sender, amount);
//     }

//     function exit() external {
//         withdraw(balanceOf(msg.sender));
//     }
    
//     function boost() external {
//         // TODO: give portion to strategist
//     }

//     function notifyRewardAmount(uint256 reward)
//         external
//     {
//         rewardToken.safeTransferFrom(msg.sender, address(this), reward);
//         // TODO: take cut and give to treasury X%
//         totalEpochRewards = totalEpochRewards.add(reward);
//         rewardPerToken = rewardPerToken.add(
//             totalEpochRewards.mul(PRECISION).div(boostedTotalSupply)
//             );
//         emit RewardAdded(reward);
//     }
    
//     function updateBoostBalanceAndSupply(address user) internal {
//          // subtract existing balance from boostedSupply
//         boostedTotalSupply = boostedTotalSupply.sub(boostedBalances[user]);
//         // calculate and update new boosted balance (user's balance has been updated by parent method)
//         // TODO: update how boosters affect stake
//         uint256 newBoostBalance = balanceOf(user);
//         boostedBalances[user] = newBoostBalance;
//         // update boostedSupply
//         boostedTotalSupply = boostedTotalSupply.add(newBoostBalance);
//     }

//     function updateUserReward(address user) internal {
//         if (lastActionTime[user] < currentEpochStarttime) {
//             previousEpoch.rewardsClaimable[user] = _earned(user, previousEpoch);
//             previousEpoch.userRewardPerTokenPaid[user] = previousEpoch.rewardPerToken;
//         }
//         currentEpoch.rewardsClaimable[user] = _earned(user, currentEpoch);
//         currentEpoch.userRewardPerTokenPaid[user] = currentEpoch.rewardPerToken;
//         lastActionTime[user] = block.timestamp;
//     }

//     // @dev updateUserReward should have been called prior to this function call
//     function _getReward(address user) internal {
//         uint256 reward = getUpdateEpochRewardsClaim(user, previousEpoch);
//         reward = reward.add(getUpdateEpochRewardsClaim(user, currentEpoch));

//         if (reward > 0) {
//             rewardToken.safeTransfer(user, reward);
//             emit RewardPaid(user, reward);
//         }
//     }

//     function getUpdateEpochRewardsClaim(address user, EpochRewards storage epochRewards)
//         internal returns (uint256 rewardAmount)
//     {
//         rewardAmount = epochRewards.rewardsClaimable[user];
//         if (rewardAmount == 0) return;
//         epochRewards.rewardsClaimed = epochRewards.rewardsClaimed.add(rewardAmount);
//         epochRewards.rewardsClaimable[user] = 0;
//     }

//     function _earned(address account, EpochRewards memory epochRewards) internal view returns (uint256) {
//         return
//             boostedBalances[account]
//                 .mul(epochRewards.rewardPerToken.sub(epochRewards.userRewardPerTokenPaid[account]))
//                 .div(1e18)
//                 .add(epochRewards.rewards[account]);
//     }
// }
