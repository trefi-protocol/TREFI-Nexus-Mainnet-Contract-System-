// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";
import "./IERC20.sol";

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
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

interface ITurbine {
    function sendReward(address to, uint256 amount) external;
    function getCoolRateTime() external view returns(uint256, uint256);
}

contract UserInfo is OwnableShip {
    address private constant c_erc20 = 0xe1ED729eAD2f59DBf643e011b606335F03Fc5606;
    address private constant c_usdt = 0x55d398326f99059fF775485246999027B3197955;
    IPancakePair private constant c_pair = IPancakePair(0xEAB58C74b222C0657eE16FBA130FC117f9cACA81);
    
    ITurbine public c_turbine;
    address public admin;
    
    struct User {
        uint128 id;
        uint128 isValid;
        address upline;
        uint256 levelRate;

        uint256 stakeAmount;
        uint256 stakeSumUSDT;
        uint256 validDirectNum;

        uint256 downline198;
        uint256 downline199;
        address maxDirectAddr;
        uint256 smallArea;
        uint256 downlineBond;

        uint256 totalReward;
        uint256 refReward;
        uint256 refReward2;
        uint256 levelReward;

        address[] directs;
    }
    mapping(address => User) private users; 
    mapping(uint256 => address) public id2Address;
    uint256 public nextUserId = 2;

    event Register(address addr, address up);
    event Reward(address addr, uint256 rewardType, uint256 amount, uint256 timestamp);

    constructor() {
        users[address(0)].id = 1;
        id2Address[1] = address(0);
        admin = msg.sender;
    }

    function setT(address t) external onlyOwner {
        c_turbine = ITurbine(t);
    }

    function register(address up) external {
        address down = msg.sender;
        if (!isUserExists(down)) {
            require(isUserExists(up), "r");
            _register(down, up);
        }
    }

    function _register(address down, address up) private {
        uint256 id = nextUserId++;
        users[down].id = uint128(id);
        users[down].upline = up;
        id2Address[id] = down;
        users[up].directs.push(down);
        emit Register(down, up);
    }

    function isUserExists(address addr) public view returns (bool) {
        return (users[addr].id != 0);
    }

    function upline(address addr) public view returns (address) {
        return users[addr].upline;
    }

    function multiSetLevel(address[] calldata addrs, uint256[] calldata lvls) external {
        require(msg.sender == admin, 'a');
        uint256 len = addrs.length;
        require(len == lvls.length, 'length err');
        for (uint256 i; i < len; ++i) {
            require(lvls[i] <= 130, 'lvl');
            users[addrs[i]].levelRate = lvls[i];
        }
    }

    function setLevel(address addr, uint256 lvl) external {
        require(msg.sender == admin, 'a');
        require(lvl <= 130, 'lvl');
        users[addr].levelRate = lvl;
    }

    function setAdmin(address addr) external {
        require(msg.sender == admin, 'a');
        admin = addr;
    }

    function setIDOLevel(address addr, uint256 lvl) external onlyOwner {
        users[addr].levelRate = lvl;
    }

    function stake(address addr, uint256 amount, uint256 usdtAmount, uint256 lockDay) external onlyOwner {
        uint256 bondUSDT = usdtAmount;
        if(usdtAmount == 0) {
            usdtAmount = amount*getTokenPrice()/10**18;
        }else {
            bondUSDT = calTeamAmount(bondUSDT, lockDay);
        }

        User storage s = users[addr];
        require(s.id > 0, 'r');
        s.stakeAmount += amount;

        if(s.isValid == 0 && usdtAmount >= 10**20) {
            s.isValid = 1;
            users[s.upline].validDirectNum++;
        }

        if(lockDay >= 90) {
            uint256 upAmount = users[s.upline].stakeAmount;
            if(upAmount > amount) {
                upAmount = amount;
            }

            uint256 rewardType;
            (uint256 buyRate, ) = c_turbine.getCoolRateTime();
            if(buyRate >= 300) {
                rewardType = 2;
            }
            _sendReward(addr, rewardType, upAmount/10);
            _sendReward(s.upline, rewardType, amount/10);
        }
        
        usdtAmount = calTeamAmount(usdtAmount, lockDay);
        if(usdtAmount > 0) {
            s.stakeSumUSDT += usdtAmount;
            if(bondUSDT == 0) {
                _addGen200(addr, usdtAmount);
            }else {
                _addGenBond200(addr, usdtAmount, bondUSDT);
            }
        }
    }

    function _sendReward(address addr, uint256 rewardType, uint256 r) private {
        User storage s = users[addr];
        uint256 a = 5*s.stakeAmount;
        uint256 t = s.totalReward;
        if(a <= t) {
            return;
        }
        a -= t;
        if(r > a) {
            r = a;
        }
        s.totalReward += r;
        if(rewardType == 1) {
            s.levelReward += r;
        }else if(rewardType == 0){
            s.refReward += r;
        }else {
            s.refReward2 += r;
        }
    }

    function sendFOMOReward(address addr, uint256 r) external onlyOwner returns(uint256) {
        User storage s = users[addr];
        uint256 a = 5*s.stakeAmount;
        uint256 t = s.totalReward;
        if(a <= t) {
            return 0;
        }
        a -= t;
        if(r > a) {
            r = a;
        }
        s.totalReward += r;
        return r;
    }

    function calTeamAmount(uint256 a, uint256 lockDay) public pure returns(uint256) {
        if(lockDay == 30) {
            return a/10;
        }else if(lockDay == 90) {
            return a*3/10;
        }else if(lockDay == 180) {
            return a*6/10;
        }else if(lockDay == 360) {
            return a;
        }
        return 0;
    }

    function _addGenBond200(address addr, uint256 amount, uint256 bondUSDT) private{
        address up = users[addr].upline;
        for(uint256 i; i < 200; ++i) {
            if(up == address(0)) break;
            if(i != 199) {
                users[up].downline198 += amount;
            }else {
                users[up].downline199 += amount;
            }
            _calMaxDirect(addr, up);
            users[up].downlineBond += bondUSDT;
            addr = up;
            up = users[up].upline;
        }
    }

    function _addGen200(address addr, uint256 amount) private{
        address up = users[addr].upline;
        for(uint256 i; i < 200; ++i) {
            if(up == address(0)) break;
            if(i != 199) {
                users[up].downline198 += amount;
            }else {
                users[up].downline199 += amount;
            }
            _calMaxDirect(addr, up);
            addr = up;
            up = users[up].upline;
        }
    }

    function _calMaxDirect(address addr, address up) private{
        address m = users[up].maxDirectAddr;
        if(m != addr) {
            uint256 mAmount = users[m].stakeSumUSDT + users[m].downline198;
            uint256 aAmount = users[addr].stakeSumUSDT + users[addr].downline198;
            uint256 smallAreaAmount = users[up].downline198 + users[up].downline199;

            if(mAmount >= aAmount) {
                smallAreaAmount -= mAmount;
            }else{
                users[up].maxDirectAddr = addr;
                smallAreaAmount -= aAmount;
            }
            users[up].smallArea = smallAreaAmount;
        }
    }

    function redeem(address addr, uint256 amount) external onlyOwner {
        users[addr].stakeAmount -= amount;
    }

    function sendReward(address addr, uint256 amount) external onlyOwner {
        uint256 p = getTokenPrice();
        address up = users[addr].upline;

        uint256 curLevel;
        uint256 curLevelReward;

        for(uint256 i; i < 200; ++i) {
            if(up == address(0)) break;

            uint256 lr = users[up].levelRate;
            uint256 curLR = calUserCurLevelRate(up, p);
            if(lr < curLR) {
                lr = curLR;
            }

            if(lr > curLevel) {
                uint256 r = amount*(lr-curLevel)/100;
                _sendReward(up, 1, r);
                curLevelReward = r;
                curLevel = lr;
            }else if(lr == curLevel && lr > 0) {
                uint256 r = curLevelReward/5;
                _sendReward(up, 1, r);
                curLevelReward = r;
            }else if(lr > 0) {
                uint256 r = curLevelReward/10;
                _sendReward(up, 1, r);
                curLevelReward = r;
            }
            up = users[up].upline;
        }
    }

    function calUserCurLevelRate(address addr, uint256 tokenPrice) public view returns(uint256) {
        User storage s = users[addr];
        uint256 usdtValue = s.stakeAmount*tokenPrice/10**36;
        return calLevelRateByAmount(usdtValue, s.validDirectNum, s.smallArea);
    }

    function calLevelRateByAmount(uint256 p, uint256 v, uint256 s) public pure returns(uint256){
        if(p >= 20000 && v >= 25 && s >= 3500*10**22) {
            return 130; // 15
        }
        if(p >= 20000 && v >= 25 && s >= 2900*10**22) {
            return 120; // 14
        }
        if(p >= 20000 && v >= 23 && s >= 2200*10**22) {
            return 110; // 13
        }
        if(p >= 20000 && v >= 21 && s >= 1600*10**22) {
            return 100; // 12
        }

        if(p >= 17000 && v >= 19 && s >= 1100*10**22) {
            return 90; // 11
        }
        if(p >= 15000 && v >= 17 && s >= 700*10**22) {
            return 80; // 10
        }
        if(p >= 13000 && v >= 15 && s >= 400*10**22) {
            return 70; // 9
        }
        if(p >= 10000 && v >= 13 && s >= 200*10**22) {
            return 60; // 8
        }
        if(p >= 7000 && v >= 11 && s >= 100*10**22) {
            return 50; // 7
        }

        if(p >= 5000 && v >= 9 && s >= 50*10**22) {
            return 40; // 6
        }
        if(p >= 3000 && v >= 7 && s >= 25*10**22) {
            return 30; // 5
        }
        if(p >= 2000 && v >= 6 && s >= 10*10**22) {
            return 25; // 4
        }
        if(p >= 1000 && v >= 5 && s >= 5*10**22) {
            return 20; // 3
        }
        if(p >= 500 && v >= 4 && s >= 2*10**22) {
            return 15; // 2
        }
        if(p >= 100 && v >= 3 && s >= 5*10**21) {
            return 10; // 1
        }
        return 0;
    }

    function getTokenPrice() public view returns(uint256) {
        address tokenA = c_usdt;
        address tokenB = c_erc20;
        (address token0, ) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = c_pair.getReserves();
        (uint256 reserveA, uint256 reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return 10**18*reserveA/reserveB;
    }

    function subRefReward2(address addr, uint256 amount) external {
        require(msg.sender == address(c_turbine), 'o');
        users[addr].refReward2 -= amount;
    }

    function getRefReward() external {
        User storage s = users[msg.sender];
        uint256 r = s.refReward;
        if(r > 0) {
            s.refReward = 0;
            c_turbine.sendReward(msg.sender, r);
            emit Reward(msg.sender, 0, r, block.timestamp);
        }
    }

    function getLevelReward() external {
        User storage s = users[msg.sender];
        uint256 r = s.levelReward;
        if(r > 0) {
            s.levelReward = 0;
            c_turbine.sendReward(msg.sender, r);
            emit Reward(msg.sender, 1, r, block.timestamp);
        }
    }

    function getAllReward() external {
        User storage s = users[msg.sender];
        uint256 r = s.refReward + s.levelReward;
        if(r > 0) {
            s.refReward = 0;
            s.levelReward = 0;
            c_turbine.sendReward(msg.sender, r);
            emit Reward(msg.sender, 2, r, block.timestamp);
        }
    }

    function userInfo(address addr) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        User memory o = users[addr];
        return (o.levelRate, o.stakeAmount, o.downlineBond, o.validDirectNum, o.smallArea, o.totalReward, o.refReward, o.levelReward);
    }

    function userOtherInfo(address addr) external view returns(uint128, uint128, address, uint256, uint256, address, uint256, uint256) {
        User memory o = users[addr];
        return (o.id, o.isValid, o.upline, o.downline198, o.downline199, o.maxDirectAddr, o.stakeSumUSDT, o.refReward2);
    }

    function getDirectsByPage(address addr, uint256 pageNum, uint256 pageSize) external view returns (address[] memory directAddrs, 
        uint256[] memory personalAmounts, uint256[] memory downlineAmounts, uint256 total) {
        User storage s = users[addr];
        total = s.directs.length;
        uint256 from = pageNum*pageSize;
        if (total <= from) {
            return (new address[](0), new uint256[](0), new uint256[](0), total);
        }
        uint256 minNum = Math.min(total - from, pageSize);
        directAddrs = new address[](minNum);
        personalAmounts = new uint256[](minNum);
        downlineAmounts = new uint256[](minNum);
        
        for (uint256 i = 0; i < minNum; i++) {
            address one = s.directs[from++];
            directAddrs[i] = one;
            personalAmounts[i] = users[one].stakeSumUSDT;
            downlineAmounts[i] = users[one].downline198;
        }
    }
}
