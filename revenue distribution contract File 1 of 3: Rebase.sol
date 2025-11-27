// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";
import "./IERC20.sol";

interface IStaking {
    function updateRewardPer(uint256 r) external;
}

contract Ownable {
    address private _owner;

    constructor () {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _owner = newOwner;
    }
}

contract Rebase is Ownable {
    IERC20 private constant c_erc20 = IERC20(0xe1ED729eAD2f59DBf643e011b606335F03Fc5606);
    address private constant c_usdt = 0x55d398326f99059fF775485246999027B3197955;
    address private constant pair = 0xEAB58C74b222C0657eE16FBA130FC117f9cACA81;
    address private constant market = 0x070efAA8C7BC6e2117b2C176edf501E2A4E66F8e;
    address private constant arbitrage = 0xEc8886213C08F2E4DeE58D61a600a8abb95FDB0f;

    mapping(uint256 => mapping(uint256 => uint256)) public stakeRate;
    address public adminAddr = msg.sender;

    uint256 public epochEnd = 1762790400;
    uint256 private constant epochSecond = 12*3600;
    address[] public pools;

    constructor() {
        stakeRate[1][30] = 10309;
        stakeRate[2][30] = 10309;
        stakeRate[3][30] = 10309;

        stakeRate[1][90] = 10752;
        stakeRate[2][90] = 10752;
        stakeRate[3][90] = 10752;

        stakeRate[1][180] = 11494;
        stakeRate[2][180] = 11494;
        stakeRate[3][180] = 11494;

        stakeRate[1][360] = 12500;
        stakeRate[2][360] = 12500;
        stakeRate[3][360] = 12500;
    }

    function clearPools() external onlyOwner {
        delete pools;
    }

    function setPools(address[] memory addrs) external onlyOwner {
        pools = addrs;
    }

    function setAdmin(address addr) external {
        require(msg.sender == adminAddr, 'a');
        adminAddr = addr;
    }

    function setEpochEnd(uint256 e) external onlyOwner {
        epochEnd = e;
    }

    function setStakeRate(uint256 stakeType, uint256 lockDay, uint256 rate) external {
        require(msg.sender == adminAddr, 'a');
        require(rate >= 8000 && rate <= 20000, 'r');
        stakeRate[stakeType][lockDay] = rate;
    }

    function getStakeRate(uint256 stakeType) external view returns(uint256, uint256, uint256, uint256) {
        return (stakeRate[stakeType][30], stakeRate[stakeType][90], stakeRate[stakeType][180], stakeRate[stakeType][360]);
    }

    function rebase() external {
        if (block.timestamp < epochEnd) {
            return;
        }
        epochEnd += epochSecond;
        uint256 tokenRate = getTokenRate();
        if(tokenRate > 100) {
            tokenRate = 100;
        }
        for(uint256 i; i < pools.length; i++) {
            uint256 rewardRate;
            if(i == 0) {
                rewardRate = getRewardRate1(tokenRate)/2;
            }else if(i == 1) {
                rewardRate = getRewardRate30(tokenRate)/2;
            }else if(i == 2) {
                rewardRate = getRewardRate90(tokenRate)/2;
            }else if(i == 3) {
                rewardRate = getRewardRate180(tokenRate)/2;
            }else {
                rewardRate = getRewardRate360(tokenRate)/2;
            }
            IStaking(pools[i]).updateRewardPer(rewardRate);
        }
    }

    function getTokenRate() public view returns (uint256) {
        (,uint256 pairERC20) = getReserves(c_usdt, address(c_erc20));
        uint256 numerator = getLockAmount() + pairERC20 + c_erc20.balanceOf(market) + c_erc20.balanceOf(arbitrage);
        return 100*numerator/c_erc20.totalSupply();
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        (address token0, ) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getLockAmount() public view returns(uint256 la) {
        for(uint256 i = 1; i < pools.length; i++) {
            la += c_erc20.balanceOf(pools[i]);
        }
    }

    function getRewardRate1(uint256 r) public pure returns (uint256) {
        if(r <= 20) {
            return 1000;
        }else if(r <= 60) {
            return 1000 + 50*(r-20);
        }
        return 3000 + 100*(r-60);
    }

    function getRewardRate30(uint256 r) public pure returns (uint256) {
        if(r <= 20) {
            return 2000;
        }else if(r <= 60) {
            return 2000 + 50*(r-20);
        }
        return 4000 + 100*(r-60);
    }

    function getRewardRate90(uint256 r) public pure returns (uint256) {
        if(r <= 20) {
            return 3000;
        }else if(r <= 60) {
            return 3000 + 50*(r-20);
        }
        return 5000 + 100*(r-60);
    }

    function getRewardRate180(uint256 r) public pure returns (uint256) {
        if(r <= 20) {
            return 4000;
        }else if(r <= 60) {
            return 4000 + 50*(r-20);
        }
        return 6000 + 100*(r-60);
    }

    function getRewardRate360(uint256 r) public pure returns (uint256) {
        if(r <= 20) {
            return 5000;
        }else if(r <= 60) {
            return 5000 + 50*(r-20);
        }
        return 7000 + 100*(r-60);
    }

    function getAllRewardRate() external view returns(uint256 r1, uint256 r30, uint256 r90, uint256 r180, uint256 r360) {
        uint256 tokenRate = getTokenRate();
        r1 = getRewardRate1(tokenRate)/2; 
        r30 = getRewardRate30(tokenRate)/2; 
        r90 = getRewardRate90(tokenRate)/2;
        r180 = getRewardRate180(tokenRate)/2;
        r360 = getRewardRate360(tokenRate)/2;
    }
}
