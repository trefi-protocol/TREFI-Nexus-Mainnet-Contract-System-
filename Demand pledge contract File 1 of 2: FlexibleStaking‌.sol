// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface IRebase {
    function rebase() external;
}

interface IUserInfo {
    function isUserExists(address addr) external view returns (bool);
    function stake(address addr, uint256 amount, uint256 usdtAmount, uint256 lockDay) external;
    function redeem(address addr, uint256 amount) external;
    function sendReward(address addr, uint256 amount) external;
}

interface ITurbine {
    function sendPrincipal(address to, uint256 amount) external;
    function sendReward(address to, uint256 amount) external;
}

contract FlexibleStaking {
    IERC20 private constant c_erc20 = IERC20(0xe1ED729eAD2f59DBf643e011b606335F03Fc5606);
    IRebase private constant c_rebase = IRebase(0xA3e44d2D2b72d952eBc63B7034Eb2352c3857eE9);
    ITurbine private constant c_turbine = ITurbine(0x6A0D9BFAC4376468aBc50A214bbdEAD089971807);
    IUserInfo private constant c_user = IUserInfo(0x343E1eF3357051aE30404beaC71544d07b33567e);

    uint256 public rewardPer;
    uint256 private constant denominator = 1000000;
    uint256 private constant oneToken = 10**18;

    struct UserInfo {
        uint256 stakeTime;
        uint256 stakeAmount;
        uint256 userRewardPer;
        uint256 reward;
    }
    mapping(address => UserInfo) public users;

    event Stake(address addr, uint256 amount, uint256 timestamp);
    event Redeem(address addr, uint256 amount, uint256 timestamp);
    event Reward(address addr, uint256 amount, uint256 timestamp);
    event Rebase(uint256 amount, uint256 timestamp);

    function stake(uint256 amount) external {
        require(c_user.isUserExists(msg.sender), "e");
        _updateReward(msg.sender);

        c_erc20.transferFrom(msg.sender, address(this), amount);
        users[msg.sender].stakeTime = block.timestamp;
        users[msg.sender].stakeAmount += amount;
        emit Stake(msg.sender, amount, block.timestamp);
    }

    function _updateReward(address addr) private {
        c_rebase.rebase();
        UserInfo storage s = users[addr];
        s.reward += s.stakeAmount * (rewardPer - s.userRewardPer)/1e18;
        s.userRewardPer = rewardPer;
    }

    function updateRewardPer(uint256 r) external {
        require(msg.sender == address(c_rebase), 'c');
        uint256 rp = oneToken*r/denominator;
        rewardPer += rp;
        emit Rebase(rp, block.timestamp);
    }

    function redeem(uint256 amount) public {
        require(block.timestamp >= users[msg.sender].stakeTime + 24*3600, 't');
        _updateReward(msg.sender);

        users[msg.sender].stakeAmount -= amount;
        c_erc20.transfer(address(c_turbine), amount);
        c_turbine.sendPrincipal(msg.sender, amount);
        emit Redeem(msg.sender, amount, block.timestamp);
    }

    function getReward() public {
        _updateReward(msg.sender);

        uint256 r = users[msg.sender].reward;
        if (r > 0) {
            users[msg.sender].reward = 0;
            c_turbine.sendReward(msg.sender, r);
            c_user.sendReward(msg.sender, r);
            emit Reward(msg.sender, r, block.timestamp);
        }
    }
    
    function userInfo(address addr) public view returns(uint256, uint256, uint256, uint256) {
        UserInfo storage s = users[addr];
        uint256 earned = s.reward + s.stakeAmount*(rewardPer - s.userRewardPer)/1e18;
        return (s.stakeTime, s.stakeAmount, earned, c_erc20.balanceOf(address(this)));
    }
}
