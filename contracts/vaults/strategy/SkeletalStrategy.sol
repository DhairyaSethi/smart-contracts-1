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

import "../IStrategy.sol";
import "../IController.sol";
import "../../SafeMath.sol";
import "../../zeppelin/SafeERC20.sol";

// To implement a strategy, kindly implement all TODOs
// This contract can either be inherited or modified
contract SkeletalStrategy is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public constant PERFORMANCE_FEE = 500; // 5%
    uint256 public constant DENOM = 10000;
    uint256 public lastHurdleUpdateTime;
    uint256 public harvestAmountThisEpoch;
    uint256 public strategistCollectedFee;
    IERC20 public want; // should be set only in constructor
    IController public controller; // should be set only in constructor
    address public strategist; // mutable, but only by strategist

    // want must be equal to an underlying vault token
    constructor(IController _controller, IERC20 _want) public {
        controller = _controller;
        strategist = msg.sender;
        want = _want;
    }

    function getName() external pure returns (string memory) {
        // TODO: change return value
        return "SkeletalStrategy";
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }

    // Example: Check availability in vault, then send it all to this contract
    function deposit() public {
        uint256 availFunds = controller.vault(address(want)).availableFunds();
        controller.earn(address(this), availFunds);
        // TODO: funds would be sent here.. convert to desired token (if needed) for investment
    }

    function withdraw(address token) external {
        IERC20 erc20Token = IERC20(token);
        require(msg.sender == address(controller), "!controller");
        require(erc20Token != want, "want");
        // TODO: should exclude more tokens, such as the farmed token
        // and other intermediary tokens used
        erc20Token.safeTransfer(address(controller), erc20Token.balanceOf(address(this)));
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == address(controller), "!controller");
        // TODO: process the withdrawal

        // send funds to vault
        want.safeTransfer(address(controller.vault(address(want))), amount);
    }

    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == address(controller), "!controller");
        // TODO: process the withdrawal
        
        // exclude collected strategist fee
        balance = want.balanceOf(address(this)).sub(strategistCollectedFee);
        // send funds to vault
        want.safeTransfer(address(controller.vault(address(want))), balance);
    }

    function harvest(address harvester) external {
        require(
            msg.sender == harvester || msg.sender == address(controller.vault(address(want))),
            "invalid harvester"
        );
        // TODO: collect farmed tokens and sell for want token

        uint256 remainingWantAmount = want.balanceOf(address(this)).sub(strategistCollectedFee);
        uint256 vaultRewardPercentage;
        uint256 hurdleAmount;
        uint256 harvestPercentage;
        uint256 epochTime;
        (vaultRewardPercentage, hurdleAmount, harvestPercentage) = 
            controller.getHarvestInfo(address(this), harvester);

        // check if harvest amount has to be reset
        if (lastHurdleUpdateTime < epochTime) {
            // reset collected amount
            harvestAmountThisEpoch = 0;
        }
        // update variables
        lastHurdleUpdateTime = block.timestamp;
        harvestAmountThisEpoch = harvestAmountThisEpoch.add(remainingWantAmount);

        // first, take harvester fee
        uint256 harvestFee = remainingWantAmount.mul(harvestPercentage).div(DENOM);
        want.safeTransfer(harvester, harvestFee);

        uint256 fee;
        // then, if hurdle amount has been exceeded, take performance fee
        if (harvestAmountThisEpoch >= hurdleAmount) {
            fee = remainingWantAmount.mul(PERFORMANCE_FEE).div(DENOM);
            strategistCollectedFee = strategistCollectedFee.add(fee);
        }
        
        // do the subtraction of harvester and strategist fees
        remainingWantAmount = remainingWantAmount.sub(harvestFee).sub(fee);

        // finally, calculate how much is to be re-invested
        // fee = vault reward amount, reusing variable
        fee = remainingWantAmount.mul(vaultRewardPercentage).div(DENOM);
        want.safeTransfer(address(controller.rewards(address(want))), fee);
        // devTODO: Call vault rewards notifyRewardDistribution
        remainingWantAmount = remainingWantAmount.sub(fee);

        // TODO: finally, use remaining want amount for reinvestment
    }

    function withdrawStrategistFee() external {
        strategistCollectedFee = 0;
        want.safeTransfer(strategist, strategistCollectedFee);
    }
}
