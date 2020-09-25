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

import "./IController.sol";
import "./IVault.sol";
import "./IVaultRewards.sol";
import "../SafeMath.sol";
import "../zeppelin/SafeERC20.sol";

interface IStrategy {
    function want() external view returns (address);
    function deposit() external;
    function withdraw(address) external;
    function withdraw(uint) external;
    function withdrawAll() external returns (uint);
    function balanceOf() external view returns (uint);
}

contract Controller is IController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct TokenStratInfo {
        IVault vault;
        IVaultRewards rewards;
        IStrategy[] strategies;
        uint256 totalInvestedAmount;
        uint256 reinvestmentPercentage;
    }
    
    address public gov;
    address public strategist;
    address public treasury;
    
    mapping(address => TokenStratInfo) public tokenStratsInfo;
    mapping(address => uint256) public capAmounts;
    mapping(address => uint256) public investedAmounts;
    mapping(address => mapping(address => bool)) public approvedStrategies;
    
    uint public split = 500;
    uint public constant MAX = 10000;
    
    constructor(address _gov, address _strategist, address _treasury) public {
        gov = _gov;
        strategist = _strategist;
        treasury = _treasury;
    }
    
    function setTreasury(address _treasury) external {
        require(msg.sender == gov, "not gov");
        treasury = _treasury;
    }
    
    function setStrategist(address _strategist) external {
        require(msg.sender == gov, "not gov");
        strategist = _strategist;
    }
    
    function setGovernance(address _gov) external {
        require(msg.sender == gov, "not gov");
        gov = _gov;
    }

    function setRewards(address _token, IVaultRewards _rewards) external {
        require(msg.sender == strategist || msg.sender == gov, "not authorized");
        require(tokenStratsInfo[_token].rewards == address(0), "rewards exists");
        tokenStratsInfo[_token].rewards = _rewards;
    }
    
    function setVault(address _token, address _vault) public {
        require(msg.sender == strategist || msg.sender == gov, "not authorized");
        require(tokenStratsInfo[_token].vault == address(0), "vault exists");
        tokenStratsInfo[_token].vault = _vault;
    }
    
    function approveStrategy(address _token, IStrategy _strategy, uint256 _cap) external {
        require(msg.sender == gov, "not gov");
        require(!approvedStrategies[_token][_strategy], "strat approved");
        capAmounts[address(_strategy)] = _cap;
        tokenStratsInfo[_token].strategies.push(_strategy);
        approvedStrategies[_token][_strategy] = true;
    }
    
    function changeCap(address strategy, uint256 _cap) external {
        require(msg.sender == gov, "not gov");
        capAmounts[strategy] = _cap;
    }

    function revokeStrategy(address _token, address _strategy, uint256 _index) external {
        require(msg.sender == gov, "not gov");
        require(approvedStrategies[_token][_strategy], "strat revoked");
        IStrategy[] storage tokenStrategies = tokenStratsInfo[_token].strategies;
        // replace revoked strategy with last element in array
        tokenStrategies[_index] = tokenStrategies[tokenStrategies.length - 1];
        delete tokenStrategies[tokenStrategies.length - 1];
        tokenStrategies.length--;
        approvedStrategies[_token][_strategy] = false;
    }
    
    /// @dev check that vault has sufficient funds is done by the call to vault
    function earn(address strategy, uint amount) public {
        address token = IStrategy(strategy).want();
        TokenStratInfo storage info = tokenStratsInfo[token];
        uint256 newInvestedAmount = investedAmounts[strategy].add(amount);
        require(newInvestedAmount <= capAmounts[strategy], "hit strategy cap");
        // update invested amount variables
        investedAmounts[strategy] = newInvestedAmount;
        info.totalInvestedAmount = info.totalInvestedAmount.add(amount);
        // transfer funds to strategy
        info.vault.transferFundsToStrategy(strategy, amount);
    }
    
    function balanceOf(address token) external view returns (uint256) {
        return tokenStratsInfo[token].totalInvestedAmount;
    }
    
    function withdrawAll(address strategy, address token) public {
        require(msg.sender == strategist || msg.sender == gov, "not authorized");
        // TODO: update invested amount variables
        Strategy(strategies[_token]).withdrawAll();
    }
    
    function inCaseTokensGetStuck(address _token, uint _amount) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    
    function inCaseStrategyTokenGetStuck(address _strategy, address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        Strategy(_strategy).withdraw(_token);
    }
    
    // Only allows to withdraw non-core strategy tokens ~ this is over and above normal yield
    function yearn(address _strategy, address _token, uint parts) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        // This contract should never have value in it, but just incase since this is a public call
        uint _before = IERC20(_token).balanceOf(address(this));
        Strategy(_strategy).withdraw(_token);
        uint _after =  IERC20(_token).balanceOf(address(this));
        if (_after > _before) {
            uint _amount = _after.sub(_before);
            address _want = Strategy(_strategy).want();
            uint[] memory _distribution;
            uint _expected;
            _before = IERC20(_want).balanceOf(address(this));
            IERC20(_token).safeApprove(onesplit, 0);
            IERC20(_token).safeApprove(onesplit, _amount);
            (_expected, _distribution) = OneSplitAudit(onesplit).getExpectedReturn(_token, _want, _amount, parts, 0);
            OneSplitAudit(onesplit).swap(_token, _want, _amount, _expected, _distribution, 0);
            _after = IERC20(_want).balanceOf(address(this));
            if (_after > _before) {
                _amount = _after.sub(_before);
                uint _reward = _amount.mul(split).div(max);
                earn(_want, _amount.sub(_reward));
                IERC20(_want).safeTransfer(rewards, _reward);
            }
        }
    }
    
    function withdraw(address _token, uint _amount) public {
        require(msg.sender == vaults[_token], "!vault");
        Strategy(strategies[_token]).withdraw(_amount);
    }
}