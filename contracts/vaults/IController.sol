pragma solidity 0.5.17;

import "../IERC20.sol";


interface IController {
    function withdraw(address, uint) external;
    function balanceOf(address) external view returns (uint);
    function earn(address, uint) external;
    function getRewardAddress(IERC20 token) external view returns (address);
}
