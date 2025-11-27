// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";
import "./IERC20.sol";
import "./Ownable.sol";

interface IRebase {
    function rebase() external;
    function stakeRate(uint256 stakeType, uint256 lockDay) external view returns (uint256);
}

interface ITurbine {
    function sendPrincipal(address to, uint256 amount) external;
    function sendBond(address to, uint256 amount) external;
    function sendReward(address to, uint256 amount) external;
}

interface IUserInfo {
    function stake(address addr, uint256 amount, uint256 usdtAmount, uint256 lockDay) external;
    function redeem(address addr, uint256 amount) external;
    function sendReward(address addr, uint256 amount) external;
}

interface IFOMO {
    function sendToFOMO(uint256 amount) external;
    function stake(address addr, uint256 amount) external;
}

contract LockedStaking is Ownable {
    IERC20 private constant c_erc20 = IERC20(0xe1ED729eAD2f59DBf643e011b606335F03Fc5606);
    IERC20 private constant c_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    address private constant pair = 0xEAB58C74b222C0657eE16FBA130FC117f9cACA81;
    IPancakeRouter02 private constant uniswapV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    IRebase private constant c_rebase = IRebase(0xA3e44d2D2b72d952eBc63B7034Eb2352c3857eE9);
    ITurbine private constant c_turbine = ITurbine(0x6A0D9BFAC4376468aBc50A214bbdEAD089971807);

    IUserInfo private constant c_user = IUserInfo(0x343E1eF3357051aE30404beaC71544d07b33567e);
    IFOMO private constant c_fomo = IFOMO(0xBf5A7BDEeAb857b974819c906f9439B83f5Aa11A);

    address private constant fund = 0x28157EC41D2E6689Af87b931fC86B885B19B3657;
    address private constant market = 0x070efAA8C7BC6e2117b2C176edf501E2A4E66F8e;
    address private constant arbitrage = 0xEc8886213C08F2E4DeE58D61a600a8abb95FDB0f;
    
    uint256 private rewardPer = 1e9;
    uint256 private constant denominator = 1000000;
    uint256 private constant lockDay = 30;
    uint256 private constant hour = 3600;
    uint256[4] public stakeTotals;
    uint256[4] public redeemAmounts;

    struct StakeInfo {
        uint128 stakeTime;
        uint128 circle;
        uint128 stakeAmount;
        uint128 withdrawn;

        uint256 userRewardPer;
        uint256 reward;
    }
    mapping(address => StakeInfo[]) public tokenBond;
    mapping(address => StakeInfo[]) public treasury;
    mapping(address => StakeInfo[]) public burnBond;
    mapping(address => StakeInfo[]) public lpBond;

    event Stake(address addr, uint256 stakeType, uint256 idx,  uint256 amount, uint256 usdtAmount, uint256 timestamp);
    event Redeem(address addr, uint256 stakeType, uint256 idx, uint256 amount, uint256 timestamp);
    event Reward(address addr, uint256 stakeType, uint256 idx, uint256 amount, uint256 timestamp);
    event Rebase(uint256 amount, uint256 timestamp);

    function updateAllowance() external {
        c_erc20.approve(address(uniswapV2Router), type(uint256).max);
        c_usdt.approve(address(uniswapV2Router), type(uint256).max);
    }

    function stakeIDO(address addr, uint256 usdtAmount, uint256 amount) external onlyOwner {
        stake(addr, amount, usdtAmount, lpBond[addr], 3);
    }

    function stakeToken(uint256 amount) external {
        c_rebase.rebase();
        c_erc20.transferFrom(msg.sender, address(this), amount);
        stake(msg.sender, amount, 0, tokenBond[msg.sender], 0);
    }

    function stakeTreasury(uint256 usdtAmount) external {
        c_rebase.rebase();
        c_usdt.transferFrom(msg.sender, address(this), usdtAmount);
        c_usdt.transfer(fund, usdtAmount/10);
        c_usdt.transfer(market, usdtAmount*3/10);
        c_usdt.transfer(arbitrage, usdtAmount*6/10);

        uint256 tokenAmount = usdtAmount*10**18/getTokenPrice();
        tokenAmount = tokenAmount*c_rebase.stakeRate(1, lockDay)/10000;
        stake(msg.sender, tokenAmount, usdtAmount, treasury[msg.sender], 1);
    }

    function stakeBurn(uint256 usdtAmount, uint256 minTokenAmount, uint256 deadline) external {
        c_rebase.rebase();
        c_usdt.transferFrom(msg.sender, address(this), usdtAmount);
        c_usdt.transfer(fund, usdtAmount/10);
        
        uint256 tokenAmount = swapUSDTForToken(usdtAmount - usdtAmount/10, minTokenAmount, deadline);
        c_erc20.burn(tokenAmount);
        tokenAmount = tokenAmount*c_rebase.stakeRate(2, lockDay)/9000;
        stake(msg.sender, tokenAmount, usdtAmount, burnBond[msg.sender], 2);
    }

    function stakeLP(uint256 usdtAmount, uint256 minTokenAmount, uint256 deadline) external {
        c_rebase.rebase();
        c_usdt.transferFrom(msg.sender, address(this), usdtAmount);
        c_usdt.transfer(fund, usdtAmount/10);
        c_usdt.transfer(market, usdtAmount/5);
        c_usdt.transfer(arbitrage, usdtAmount*3/10);

        uint256 tokenAmount = swapAndLiquify(usdtAmount*4/10, minTokenAmount, deadline);
        tokenAmount = tokenAmount*c_rebase.stakeRate(3, lockDay)/2000; 
        stake(msg.sender, tokenAmount, usdtAmount, lpBond[msg.sender], 3);
    }

    function stake(address addr, uint256 amount, uint256 usdtAmount, StakeInfo[] storage s, uint256 stakeType) private {
        require(amount < type(uint128).max, 'a');
        if(stakeType > 0) {
            stakeTotals[stakeType] += usdtAmount;
        }else {
            stakeTotals[stakeType] += amount;
        }
        s.push(StakeInfo(uint128(block.timestamp), 0, uint128(amount), 0, rewardPer, 0));

        c_user.stake(addr, amount, usdtAmount, lockDay);
        if(lockDay >= 90) {
            c_fomo.stake(addr, amount);
        }
        emit Stake(addr, stakeType, s.length, amount, usdtAmount, block.timestamp);
    }

    function swapAndLiquify(uint256 usdtAmount, uint256 minTokenAmount, uint256 deadline) private returns(uint256) {
        uint256 half = usdtAmount/2;
        uint256 tokenAmount = swapUSDTForToken(half, minTokenAmount, deadline);
        addLiquidity(half, tokenAmount);
        return tokenAmount;
    }

    function swapUSDTForToken(uint256 usdtAmount, uint256 minTokenAmount, uint256 deadline) private returns(uint256){
        address[] memory path = new address[](2);
        path[0] = address(c_usdt);
        path[1] = address(c_erc20);
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
            usdtAmount,
            minTokenAmount,
            path,
            address(this),
            deadline
        );
        return amounts[1];
    }

    function addLiquidity(uint256 usdtAmount, uint256 tokenAmount) private {
        uniswapV2Router.addLiquidity(
            address(c_usdt),
            address(c_erc20),
            usdtAmount,
            tokenAmount,
            0,
            0,
            address(0xdEaD),
            block.timestamp
        );
    }

    function getTokenPrice() public view returns(uint256) {
        address tokenA = address(c_usdt);
        address tokenB = address(c_erc20);
        (address token0, ) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();
        (uint256 reserveA, uint256 reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return 10**18*reserveA/reserveB;
    }

    function updateRewardPer(uint256 r) external {
        require(msg.sender == address(c_rebase), 'c');
        uint256 rp = rewardPer*(denominator+r)/denominator;
        rewardPer = rp;
        emit Rebase(rp, block.timestamp);
    }

    function redeem(uint256 stakeType, uint256 idx) external {
        c_rebase.rebase();

        StakeInfo[] storage sa = getStakeArray(msg.sender, stakeType);
        StakeInfo storage s = sa[idx];
        _updateReward(s);
        uint256 w = _redeem(s);
        redeemAmounts[stakeType] += w;

        c_user.redeem(msg.sender, w);

        if(stakeType == 0) {
            c_erc20.transfer(address(c_turbine), w);
            c_turbine.sendPrincipal(msg.sender, w);
        }else {
            c_turbine.sendBond(msg.sender, w);
        }
        
        emit Redeem(msg.sender, stakeType, idx, w, block.timestamp);
    }

    function getStakeArray(address addr, uint256 stakeType) private view returns(StakeInfo[] storage) {
        StakeInfo[] storage sa;
        if(stakeType == 0) {
            sa = tokenBond[addr];
        }else if(stakeType == 1) {
            sa = treasury[addr];
        }else if(stakeType == 2) {
            sa = burnBond[addr];
        }else {
            sa = lpBond[addr];
        }
        return sa;
    }

    function _updateReward(StakeInfo storage s) private {
        s.reward = (s.stakeAmount + s.reward) * rewardPer/s.userRewardPer - s.stakeAmount;
        s.userRewardPer = rewardPer;
    }

    function _redeem(StakeInfo storage s) private returns(uint256) {
        (uint256 w, uint256 cur) = getWithdrawable(s.stakeTime, s.stakeAmount, s.withdrawn, s.circle);
        s.stakeAmount -= uint128(w);
        if(cur == 0) {
            s.withdrawn += uint128(w);
        }else {
            s.withdrawn = uint128(w);
            s.circle = uint128(cur);
        }
        return w;
    }

    function getWithdrawable(uint256 stakeTime, uint256 stakeAmount, uint256 withdrawn, uint256 last) public view returns(uint256, uint256) {
        uint256 t = lockDay*24*hour;
        uint256 interval = block.timestamp - stakeTime;
        uint256 num = interval/t;
        if(num > 0 && interval <= num*t + 36*hour) {
            return (stakeAmount, 0);
        }

        if(num == last) {
            return (((stakeAmount+withdrawn)*(interval - num*t)/t - withdrawn), 0);
        }
        return (stakeAmount*(interval - num*t)/t, num);
    }

    function getReward(uint256 stakeType, uint256 idx) external {
        c_rebase.rebase();
        StakeInfo[] storage sa = getStakeArray(msg.sender, stakeType);
        StakeInfo storage s = sa[idx];
        _updateReward(s);
        uint256 r = s.reward;
        if (r > 0) {
            s.reward = 0;
            c_turbine.sendReward(msg.sender, r);
            c_user.sendReward(msg.sender, r);
            emit Reward(msg.sender, stakeType, idx, r, block.timestamp);
        }
    }

    function skim(uint256 amount) external {
        c_usdt.transfer(arbitrage, amount);
    }

    function userBondInfo(address addr) external view returns(StakeInfo[] memory t, StakeInfo[] memory b, StakeInfo[] memory l) {
        t = treasury[addr];
        b = burnBond[addr];
        l = lpBond[addr];
    }

    function userStakeInfoByType(address addr, uint256 stakeType) external view returns(StakeInfo[] memory o) {
        if(stakeType == 0) {
            o = tokenBond[addr];
        }else if(stakeType == 1) {
            o = treasury[addr];
        }else if(stakeType == 2) {
            o = burnBond[addr];
        }else {
            o = lpBond[addr];
        }
    }

    function userStakeInfo() external view returns(uint256[4] memory s, uint256[4] memory r) {
        s = stakeTotals;
        r = redeemAmounts;
    }

    function stakeInfo(address addr, uint256 stakeType, uint256 pageNum, uint256 pageSize) external view returns(uint256[] memory stakeTimes, uint256[] memory stakeAmounts, 
        uint256[] memory withdrawns, uint256[] memory withdrawables, uint256[] memory rewards, uint256 total) {

        StakeInfo[] storage sa = getStakeArray(addr, stakeType);
        total = sa.length;
        uint256 from = pageNum*pageSize;
        if (total <= from) {
            return (new uint256[](0), new uint256[](0), new uint256[](0), new uint256[](0), new uint256[](0), total);
        }
        uint256 minNum = total - from < pageSize ? total - from : pageSize;
        from = total - from - 1;

        stakeTimes = new uint256[](minNum);
        stakeAmounts = new uint256[](minNum);
        withdrawns = new uint256[](minNum);
        withdrawables = new uint256[](minNum);
        rewards = new uint256[](minNum);
        
        for(uint256 i; i < minNum; i++) {
            StakeInfo storage s = sa[from];

            stakeTimes[i] = s.stakeTime;
            stakeAmounts[i] = s.stakeAmount;
            withdrawns[i] = s.withdrawn;

            (withdrawables[i], ) = getWithdrawable(s.stakeTime, s.stakeAmount, s.withdrawn, s.circle);
            rewards[i] = (s.stakeAmount + s.reward) * rewardPer/s.userRewardPer - s.stakeAmount;
            if(from > 0) {
                from--;
            }
        }
    }
}
