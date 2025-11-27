// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";
import "./AccessControl.sol";
import "./IERC20.sol";

contract TraderAccessControl is AccessControl {
    bytes32 public constant Trader = keccak256("Trader");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Trader, msg.sender);
    }

    modifier onlyTrader() {
        require(hasRole(Trader, msg.sender), "Trader");
        _;
    }
}

contract MarketTreasury is TraderAccessControl {
    IERC20 private constant c_erc20 = IERC20(0xe1ED729eAD2f59DBf643e011b606335F03Fc5606);
    IERC20 private constant c_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IPancakeRouter02 private constant uniswapV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    function updateAllowance() external {
        c_erc20.approve(address(uniswapV2Router), type(uint256).max);
        c_usdt.approve(address(uniswapV2Router), type(uint256).max);
    }

    function swapUSDTForToken(uint256 usdtAmount, uint256 minTokenAmount, uint256 deadline) external onlyTrader {
        address[] memory path = new address[](2);
        path[0] = address(c_usdt);
        path[1] = address(c_erc20);
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            usdtAmount,
            minTokenAmount,
            path,
            address(this),
            deadline
        );
    }

    function swapTokenForUSDT(uint256 tokenAmount, uint256 minUSDTAmount, uint256 deadline) external onlyTrader {
        address[] memory path = new address[](2);
        path[0] = address(c_erc20);
        path[1] = address(c_usdt);
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            minUSDTAmount,
            path,
            address(this),
            deadline
        );
    }

    function burn(uint256 amount) external onlyTrader {
        c_erc20.burn(amount);
    }

    function getTokenBalance() external view returns(uint256 u, uint256 er) {
        u = c_usdt.balanceOf(address(this));
        er = c_erc20.balanceOf(address(this));
    }

    function getAmountOut(uint256 tradeSide, uint256 amount) external view returns(uint256) {
        address[] memory path = new address[](2);
        if(tradeSide == 0) {
            path[0] = address(c_usdt);
            path[1] = address(c_erc20);
        }else {
            path[0] = address(c_erc20);
            path[1] = address(c_usdt);
        }
        uint[] memory amounts = new uint[](2);
        amounts = uniswapV2Router.getAmountsOut(amount, path);
        return amounts[1];
    }
}
