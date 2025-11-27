// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";

interface ITurbine {
    function sendReward(address to, uint256 amount) external;
}

interface IUserInfo {
    function stake(address addr, uint256 amount, uint256 usdtAmount, uint256 lockDay) external;
    function sendReward(address addr, uint256 amount) external;
    function sendFOMOReward(address addr, uint256 r) external returns(uint256);
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

contract FOMO is OwnableShip {

    address private constant c_erc20 = 0xe1ED729eAD2f59DBf643e011b606335F03Fc5606;
    address private constant c_usdt = 0x55d398326f99059fF775485246999027B3197955;
    IPancakePair private constant c_pair = IPancakePair(0xEAB58C74b222C0657eE16FBA130FC117f9cACA81);

    ITurbine public c_turbine;
    IUserInfo public c_user;
    uint256 public thresholdUSDT = 5*10**22;
    uint256 private constant duration = 86400;

    uint256 public totalSupply;

    struct User {
        uint256 amount;
        uint256 circle;
        uint256 reward;
    }
    mapping(address => User) private users;

    uint256 private lastTime = 1761926400;
    uint256 private curCircle;
    address[5] public rankInfos = [address(0),address(0),address(0),address(0),address(0)];

    struct RecordRankInfo {
        address top;
        uint256 amount;
        uint256 reward;
    }
    RecordRankInfo[] public recordRankInfos;

    event Reward(address addr, uint256 amount);

    constructor() {
        for(uint256 i; i<5; i++) {
            recordRankInfos.push(RecordRankInfo(address(0), 0, 0));
        }
    }

    function setD(uint256 u) external onlyOwner {
        thresholdUSDT = u;
    }

    function setT(address t, address u) external onlyOwner {
        c_turbine = ITurbine(t);
        c_user = IUserInfo(u);
    }

    function sendToFOMO(uint256 amount) external {
        require(msg.sender == address(c_turbine), 't');
        totalSupply += amount;
    }

    function stake(address addr, uint256 amount) external onlyOwner {
        processTimePayout();

        uint256 curAmount;
        uint256 cc = curCircle;
        User storage s = users[addr];
        if(s.circle == cc) {
            curAmount = s.amount + amount;
            s.amount = curAmount;
        }else {
            s.circle = cc;
            s.amount = amount;
            curAmount = amount;
        }

        uint256 minAmount = users[rankInfos[4]].amount;
        if(minAmount > curAmount) {
            return;
        }

        if(!_updateArray(addr, curAmount)){
            _insertToArray(addr, curAmount);
        }
    }

    function _updateArray(address addr, uint256 amount) private returns(bool) {
        for(uint256 i; i < 5; ++i) {
            if(rankInfos[i] == addr) {
                if(i == 0) {
                    return true;
                }
                
                int256 j = int256(i) - 1;
                for(; j >= 0; j--){
                    if(users[rankInfos[uint256(j)]].amount >= amount) {
                        break;
                    }
                }

                uint256 newIdx = uint256(j + 1); 
                for(uint256 k = i; k > newIdx; k--){
                    rankInfos[k] = rankInfos[k-1];
                }
                rankInfos[newIdx] = addr;
                return true;
            }
        }
        return false;
    }

    function _insertToArray(address addr, uint256 amount) private {
        for(uint256 i; i < 5; ++i) {
            if(users[rankInfos[i]].amount < amount) {
                for(uint256 j = 4; j > i; j--) {
                    rankInfos[j] = rankInfos[j-1];
                }
                rankInfos[i] = addr;
                return;
            }
        }
    }

    function processTimePayout() public {
        if(block.timestamp < lastTime + duration) {
            return;
        }
        uint256 dividend = thresholdUSDT*10**18/getTokenPrice();
        if(totalSupply < dividend) {
            return;
        }
        totalSupply -= _rankPayout(dividend);
        lastTime = block.timestamp;
        curCircle++;
    }

    function _rankPayout(uint256 a) private returns(uint256){
        uint256 d;
        uint256 o = a/100;
        for(uint256 i; i < 5; ++i) {
            address addr = rankInfos[i];
            if(addr != address(0)) {
                uint256 r;
                if(i == 0) {
                    r = 30*o;
                }else if(i == 1) {
                    r = 25*o;
                }else if(i == 2) {
                    r = 20*o;
                }else if(i == 3){
                    r = 15*o;
                }else{
                    r = 10*o;
                }
                users[addr].reward += r;
                d += r;
                rankInfos[i] = address(0);
                recordRankInfos[i] = RecordRankInfo(addr, users[addr].amount, r);
            }else {
                clearRecordLast(recordRankInfos, i);
                break;
            }
        }
        return d;
    }

    function clearRecordLast(RecordRankInfo[] storage s, uint256 clearIdx) private {
        for(uint256 i = clearIdx; i < s.length; i++) {
            s[i].amount = 0;
        }
    }

    function getTokenPrice() public view returns(uint256) {
        address tokenA = c_usdt;
        address tokenB = c_erc20;
        (address token0, ) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = c_pair.getReserves();
        (uint256 reserveA, uint256 reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        return 10**18*reserveA/reserveB;
    }

    function getReward() external {
        processTimePayout();
        uint256 r = users[msg.sender].reward;
        if (r > 0) {
            r = c_user.sendFOMOReward(msg.sender, r);
            users[msg.sender].reward = 0;
            c_turbine.sendReward(msg.sender, r);
            emit Reward(msg.sender, r);
        }
    }

    function rankInfo() external view returns(RecordRankInfo[] memory rrInfos, address[5] memory rInfos, uint256[] memory amounts) {
        rrInfos = recordRankInfos;
        rInfos = rankInfos;
        amounts = new uint256[](5);
        for(uint256 i; i < 5; ++i) {
            amounts[i] = users[rInfos[i]].amount;
        }
    }

    function userInfo(address addr) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        User memory o = users[addr];
        return (o.amount, o.circle, o.reward, totalSupply, lastTime, curCircle, getTokenPrice());
    }
}
