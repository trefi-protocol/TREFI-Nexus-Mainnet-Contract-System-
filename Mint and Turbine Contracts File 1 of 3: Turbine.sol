// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";
import "./IERC20.sol";

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

interface IArbitrageTreasury {
    function getValue() external view returns(uint256);
}

interface IFOMO {
    function sendToFOMO(uint256 amount) external;
    function stake(address addr, uint256 amount) external;
}

interface IUserInfo {
    function subRefReward2(address addr, uint256 amount) external;
}

contract OwnableShip {
    mapping (address => bool) private ownerShips;

    constructor () {
        ownerShips[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(ownerShips[msg.sender], "Ownable: caller is not the owner");
        _;
    }

    function addOwnership(address newOwner) public onlyOwner {
        ownerShips[newOwner] = true;
    }

    function removeOwnership(address oldOwner) public onlyOwner {
        ownerShips[oldOwner] = false;
    }
}

contract Turbine is OwnableShip {
    IERC20 private constant c_erc20 = IERC20(0xe1ED729eAD2f59DBf643e011b606335F03Fc5606);
    IERC20 private constant c_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    address private constant pair = 0xEAB58C74b222C0657eE16FBA130FC117f9cACA81;

    address private constant market = 0x070efAA8C7BC6e2117b2C176edf501E2A4E66F8e;
    IArbitrageTreasury private constant c_arbitrage = IArbitrageTreasury(0xEc8886213C08F2E4DeE58D61a600a8abb95FDB0f);
    IFOMO private constant c_fomo = IFOMO(0xBf5A7BDEeAb857b974819c906f9439B83f5Aa11A);
    address private constant feeAddress = 0xF656b1e6504147D161129C272706a1A000EB909c;
    IPancakeRouter02 private constant uniswapV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IUserInfo public c_user;
    
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    uint256 public lastPrice;
    uint256 public lastTime = 1762790400;

    struct CoolInfo {
        uint128 buyTime;
        uint64  lockHour;
        uint64  isRedeem;
        uint256 buyAmount;
        uint256 reward;
    }
    mapping(address => CoolInfo[]) public cools;
    uint256 public totalCool;
    uint256 public totalBuy;

    constructor() {
    }

    function updateAllowance() external {
        c_erc20.approve(address(uniswapV2Router), type(uint256).max);
        c_usdt.approve(address(uniswapV2Router), type(uint256).max);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function setUser(address u) external onlyOwner {
        c_user = IUserInfo(u);
    }

    function setT(uint256 t) external onlyOwner {
        lastTime = t;
    }

    function sendPrincipal(address to, uint256 amount) external onlyOwner {
        _balances[to] += amount;
        _totalSupply += amount;
        updatePrice();
    }

    function sendBond(address to, uint256 amount) external onlyOwner {
        _balances[to] += amount;
        _totalSupply += amount;
        c_erc20.mint(address(this), amount);
        updatePrice();
    }

    function sendReward(address to, uint256 amount) external onlyOwner {
        c_erc20.mint(feeAddress, amount/20);

        (uint256 fomo, uint256 burn, uint256 curPrice) = getFeeRate();
        _updatePrice(curPrice);
        fomo = amount*fomo/1000;
        c_fomo.sendToFOMO(fomo);

        uint256 r = amount - amount/20 - fomo - amount*burn/1000;
        c_erc20.mint(address(this), r);

        _balances[to] += r;
        _totalSupply += r;
    }

    function buyByToken(uint256 usdtAmountMax, uint256 tokenAmount, uint256 deadline) external {
        (uint256 buyRate, uint256 lockHour) = getCoolRateTime();
        uint256 buyAmount = tokenAmount*buyRate/100;
        _balances[msg.sender] -= tokenAmount;
        _totalSupply -= tokenAmount;
        totalCool += tokenAmount;
        totalBuy += buyAmount;
        cools[msg.sender].push(CoolInfo(uint128(block.timestamp), uint64(lockHour), 0, buyAmount, tokenAmount));

        c_usdt.transferFrom(msg.sender, address(this), usdtAmountMax);
        uint256 usdtBuy = swapUSDTForExactToken(usdtAmountMax, buyAmount, deadline);
        usdtBuy = usdtAmountMax - usdtBuy;
        if(usdtBuy > 0) {
            c_usdt.transfer(msg.sender, usdtBuy);
        }
    }

    function buyByReward(uint256 tokenAmount) external {
        c_user.subRefReward2(msg.sender, tokenAmount);

        (, uint256 lockHour) = getCoolRateTime();
        _balances[msg.sender] -= tokenAmount;
        _totalSupply -= tokenAmount;
        totalCool += tokenAmount;
        totalBuy += tokenAmount;
        cools[msg.sender].push(CoolInfo(uint128(block.timestamp), uint64(lockHour), 0, tokenAmount, tokenAmount));
    }

    function swapUSDTForExactToken(uint256 usdtAmountMax, uint256 tokenAmount, uint256 deadline) private returns(uint256){
        address[] memory path = new address[](2);
        path[0] = address(c_usdt);
        path[1] = address(c_erc20);
        uint256[] memory amounts = uniswapV2Router.swapTokensForExactTokens(
            tokenAmount,
            usdtAmountMax,
            path,
            address(this),
            deadline
        );
        return amounts[0];
    }

    function getTotalUSDT() public view returns(uint256) {
        (uint256 pairUSDT,) = getReserves(address(c_usdt), address(c_erc20));
        return c_usdt.balanceOf(market) + pairUSDT + c_arbitrage.getValue();
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        (address token0, ) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getCoolRateTime() public view returns(uint256, uint256) {
        (uint256 buyRate, uint256 lockHour) = getCoolRateTimeByAmount(_totalSupply+totalCool+totalBuy);
        return (buyRate, lockHour);
    }

    function getCoolRateTimeByAmount(uint256 amount) public view returns(uint256, uint256) {
        uint256 rate = 1000*amount*getTokenPrice()/(10**18*getTotalUSDT());
        if(rate < 10) {
            return (50, 24);
        }else if(rate < 20) {
            return (60, 30);
        }else if(rate < 30) {
            return (70, 36);
        }else if(rate < 40) {
            return (80, 42);
        }else if(rate < 50) {
            return (90, 48);
        }else if(rate < 55) {
            return (100, 54);
        }
        uint256 r = (rate - 55)/5;
        uint256 buyRate = 130 + 30*r;
        if(buyRate > 500) {
            buyRate = 500;
            r = 12;
        }
        return (buyRate, 60+6*r);
    }

    function getTokenPrice() public view returns(uint256) {
        address tokenA = address(c_usdt);
        address tokenB = address(c_erc20);
        (address token0, ) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();
        (uint256 reserveA, uint256 reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return 10**18*reserveA/reserveB;
    }

    function getFinalReward(uint256 idx) external {
        CoolInfo storage s = cools[msg.sender][idx];
        require(s.isRedeem == 0, 'r');
        require(block.timestamp >= s.buyTime + s.lockHour*3600, 't');
        s.isRedeem = 1;

        uint256 r = s.reward;
        uint256 b = s.buyAmount;
        c_erc20.transfer(msg.sender, b+r);
        totalCool -= r;
        totalBuy -= b;
    }

    function getFeeRate() public view returns(uint256, uint256, uint256) {
        uint256 curPrice = getTokenPrice();
        (uint256 fomo1, uint256 burn1) = getFeeRateByUSDT(curPrice, _totalSupply+totalCool+totalBuy);
        (uint256 fomo2, uint256 burn2) = getFeeRateByPrice(curPrice);
        if(fomo2 > fomo1) {
            fomo1 = fomo2;
        }
        if(burn2 > burn1) {
            burn1 = burn2;
        }
        return (fomo1, burn1, curPrice);
    }

    function updatePrice() public {
        uint256 curPrice = getTokenPrice();
        _updatePrice(curPrice);
    }

    function _updatePrice(uint256 curPrice) private {
        if(block.timestamp >= lastTime + 86400) {
            lastTime += 86400;
            lastPrice = curPrice;
        }
    }

    function getFeeRateByUSDT(uint256 price, uint256 amount) public view returns(uint256, uint256) {
        uint256 r = 1000*amount*price/(10**18*getTotalUSDT());
        if(r < 30) {
            return (10, 0);
        }
        if(r < 40) {
            return (30, 20);
        }
        if(r < 50) {
            return (30, 70);
        }
        if(r < 60) {
            return (30, 120);
        }
        if(r < 70) {
            return (30, 170);
        }
        if(r < 80) {
            return (30, 220);
        }
        if(r < 90) {
            return (30, 320);
        }
        return (30, 420);
    }

    function getFeeRateByPrice(uint256 price) public view returns(uint256, uint256) {
        uint256 lastP = lastPrice;
        if(price >= lastP) {
            return (10, 0);
        }
        uint256 d = 1000*(lastP - price)/lastP; // decline‌
        if(d < 30) {
            return (10, 0);
        }
        if(d < 40) {
            return (30, 20);
        }
        if(d < 50) {
            return (30, 70);
        }
        if(d < 60) {
            return (30, 120);
        }
        if(d < 70) {
            return (30, 170);
        }
        if(d < 80) {
            return (30, 220);
        }
        if(d < 90) {
            return (30, 320);
        }
        return (30, 420);
    }

    function contractInfo() external view returns(uint256, uint256, uint256, uint256, uint256) {
        (uint256 buyRate, uint256 lockHour) = getCoolRateTime();
        return (_totalSupply, totalCool, totalBuy, buyRate, lockHour);
    }

    function userBalanceInfo(address addr) external view returns(uint256, uint256) {
        return (_balances[addr], c_usdt.balanceOf(addr));
    }

    function userCoolInfo(address addr) external view returns(CoolInfo[] memory) {
        CoolInfo[] memory o = cools[addr];
        return o;
    }

    function userCoolInfoByPage(address addr, uint256 pageNum, uint256 pageSize) external view returns(uint256[] memory buyTimes, uint256[] memory lockHours, 
        uint256[] memory isRedeems, uint256[] memory buyAmounts, uint256[] memory rewards, uint256 total) {

        CoolInfo[] storage ca = cools[addr];
        total = ca.length;
        uint256 from = pageNum*pageSize;
        if (total <= from) {
            return (new uint256[](0), new uint256[](0), new uint256[](0), new uint256[](0), new uint256[](0), total);
        }
        uint256 minNum = Math.min(total - from, pageSize);
        from = total - from - 1;

        buyTimes = new uint256[](minNum);
        lockHours = new uint256[](minNum);
        isRedeems = new uint256[](minNum);
        buyAmounts = new uint256[](minNum);
        rewards = new uint256[](minNum);
        
        for(uint256 i; i < minNum; i++) {
            CoolInfo storage s = ca[from];
            buyTimes[i] = uint256(s.buyTime);
            lockHours[i] = uint256(s.lockHour);
            isRedeems[i] = uint256(s.isRedeem);
            buyAmounts[i] = s.buyAmount;
            rewards[i] = s.reward;
            if(from > 0) {
                from--;
            }
        }
    }

    function getAmountIn(uint256 amount) external view returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = address(c_usdt);
        path[1] = address(c_erc20);
        uint[] memory amounts = new uint[](2);
        amounts = uniswapV2Router.getAmountsIn(amount, path);
        return amounts[0];
    }

    function getAmountOut(uint256 amount) external view returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = address(c_usdt);
        path[1] = address(c_erc20);
        uint[] memory amounts = new uint[](2);
        amounts = uniswapV2Router.getAmountsOut(amount, path);
        return amounts[1];
    }
}
