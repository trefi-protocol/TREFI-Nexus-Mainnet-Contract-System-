// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from,address to,uint256 amount) external returns (bool);
}

interface IUserInfo {
    function isUserExists(address addr) external view returns (bool);
    function upline(address addr) external view returns (address);
    function setIDOLevel(address addr, uint256 lvl) external;
}

contract IDO is Ownable {
    IUserInfo private constant c_user = IUserInfo(0x343E1eF3357051aE30404beaC71544d07b33567e);
    IERC20 private constant c_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 private constant c_erc20 = IERC20(0xe1ED729eAD2f59DBf643e011b606335F03Fc5606);
    
    address private constant operateFund = 0x28157EC41D2E6689Af87b931fC86B885B19B3657;
    address private constant liquidityAddress = 0x9a7DCD3dA1965E322368BA01f46e1F6F53f0A416;
    uint256 public startTime = 1764432000;

    struct User {
        uint32 levelRate;
        uint112 sumAmount;
        uint112 sumAmountReward;
        
        uint128 sumReward;
        uint128 withdrawnReward;
    }
    mapping(address => User) public users;
    uint256 public totalAmount;
    uint256 public totalAmountReward;
    uint256 public totalReward;
    uint256 public price;

    event IDOEvent(address from, uint256 amount, uint256 rate);

    function ido(uint256 amount) external {
        require(c_user.isUserExists(msg.sender), 'e');
        c_usdt.transferFrom(msg.sender, operateFund, amount/10);
        c_usdt.transferFrom(msg.sender, liquidityAddress, amount*9/10);
        _processIDO(msg.sender, amount, 0);
    }

    function idoOffline(address addr, uint256 amount, uint256 rate) external onlyOwner {
        require(c_user.isUserExists(addr), 'e');
        _processIDO(addr, amount, rate);
    }

    function idoOfflineBatch(address[] calldata addrs, uint256[] calldata amounts, uint256[] calldata rates) external onlyOwner {
        uint256 len = addrs.length;
        require(len == amounts.length, 'length err1');
        require(len == rates.length, 'length err2');

        for (uint256 i; i < len; ++i) {
            require(c_user.isUserExists(addrs[i]), 'e');
            _processIDO(addrs[i], amounts[i], rates[i]);
        }
    }

    function setPrice(uint256 p) external onlyOwner {
        price = p;
    }

    function setStartTime(uint256 s) external onlyOwner {
        startTime = s;
    }

    function _processIDO(address addr, uint256 amount, uint256 rate) private {
        uint256 lr;
        if(rate == 0) {
            rate = getRate();
            lr = calLevelRate(amount);
        }else {
            lr = calOfflineLevelRate(amount);
        }
        require(lr != 1, 'a');
        if(lr > users[addr].levelRate) {
            users[addr].levelRate = uint32(lr);
            c_user.setIDOLevel(addr, lr);
        }
        users[addr].sumAmount += uint112(amount);
        totalAmount += amount;

        uint256 ar = amount*(100+rate)/100;
        users[addr].sumAmountReward += uint112(ar);
        totalAmountReward += ar;
        emit IDOEvent(addr, amount, rate);

        address up = c_user.upline(addr);
        if(up == address(0)) {
            return;
        }
        uint256 ur = amount/10;
        users[up].sumReward += uint128(ur);

        uint256 pr;
        uint256 upAmount = users[up].sumAmount;
        if(upAmount < amount) {
            pr = upAmount/10;
        }else{
            pr = amount/10;
        }
        users[addr].sumReward += uint128(pr);
        totalReward += ur + pr;
    }

    function calLevelRate(uint256 amount) public pure returns(uint256) {
        if(amount == 10**20) {
            return 0;
        }
        if(amount == 5*10**20) {
            return 10; // 1
        }
        if(amount == 10**21) {
            return 15; // 2
        }
        if(amount == 5*10**21) {
            return 20; // 3
        }
        if(amount == 10**22) {
            return 25; // 4
        }
        return 1;
    }

    function calOfflineLevelRate(uint256 amount) public pure returns(uint256) {
        if(amount < 5*10**20) {
            return 0; // 0
        }
        if(amount < 10**21) {
            return 10; // 1
        }
        if(amount < 5*10**21) {
            return 15; // 2
        }
        if(amount < 10**22) {
            return 20; // 3
        }
        return 25;
    }

    function getRate() public view returns (uint256) {
        uint256 d = (block.timestamp - startTime)/86400;
        if(d > 15) {
            d = 15;
        }
        return 40-d;
    }

    function skim(uint256 amount) external {
        require(msg.sender == operateFund, 'r');
        c_usdt.transfer(msg.sender, amount);
    }

    function getTokenReward() external {
        uint256 r = users[msg.sender].sumReward;
        users[msg.sender].sumReward = 0;
        users[msg.sender].withdrawnReward += uint128(r);
        c_erc20.transfer(msg.sender, r*10**18/price);
    }

    function userInfo(address addr) external view returns (uint256, uint256, uint256, uint256, uint256) {
        User memory o = users[addr];
        return (uint256(o.levelRate), uint256(o.sumAmount), uint256(o.sumAmountReward), uint256(o.sumReward), uint256(o.withdrawnReward)); 
    }

    function contractInfo() external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (totalAmount, totalAmountReward, totalReward, price, getRate()); 
    }
}
