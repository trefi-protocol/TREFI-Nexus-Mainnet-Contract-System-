// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20StandardToken.sol";
import "./AccessControl.sol";

contract TFIAccessControl is AccessControl {
    bytes32 public constant MINT = keccak256("MINT");
    bytes32 public constant PAIR_FEE = keccak256("PAIR_FEE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINT, msg.sender);
        _grantRole(PAIR_FEE, msg.sender);
    }

    modifier onlyMint() {
        require(hasRole(MINT, msg.sender), "mint");
        _;
    }

    modifier onlyPairFee() {
        require(hasRole(PAIR_FEE, msg.sender), "PairFee");
        _;
    }
}

contract TFI is ERC20StandardToken, TFIAccessControl {

    mapping (address => bool) public pairs;
    mapping (address => bool) public isExcludedFromFees;
    address public constant feeAddress1 = 0x2C931e1a38174054B26410dd8De3eF8bc72c8Cec;
    address public constant feeAddress2 = 0x9C021cAcB0fc89A02E13508d2dB4470a17a04e70;
    uint256 public buyFee = 99;

    constructor(string memory symbol_, string memory name_, uint8 decimals_, uint256 totalSupply_) ERC20StandardToken(symbol_, name_, decimals_, totalSupply_) {
        address factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
        address usdt = 0x55d398326f99059fF775485246999027B3197955;
        address usdtPair = pairFor(factory, usdt, address(this));
        pairs[usdtPair] = true;
        isExcludedFromFees[0x9a7DCD3dA1965E322368BA01f46e1F6F53f0A416] = true;
    }

    function pairFor(address factory, address tokenA, address tokenB) public pure returns (address pair_) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair_ = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5'
        )))));
    }

    function setPair(address _pair, bool b) external onlyPairFee {
        pairs[_pair] = b;
    }

    function setFee(uint256 b) external onlyPairFee {
        require(b <= 100, 'b');
        buyFee = b;
    }

    function setExcludeFee(address a, bool b) external onlyPairFee {
        isExcludedFromFees[a] = b;
    }

    function mint(address account, uint256 amount) external onlyMint {
        _mint(account, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if(!pairs[from] && !pairs[to]) {
            super._transfer(from, to, amount);
            return;
        }
        if(isExcludedFromFees[from] || isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
            return;
        }
        _subSenderBalance(from, amount);
        unchecked{
            if(pairs[from]) {
                uint256 feeAmount;
                uint256 b = buyFee;
                if(b > 0) {
                    feeAmount = amount*b/100;
                    _addReceiverBalance(from, feeAddress2, feeAmount);
                }
                _addReceiverBalance(from, to, amount - feeAmount);
            }else {
                uint256 f1 = amount*9/1000;
                _addReceiverBalance(from, feeAddress1, f1);
                
                uint256 f2 = amount*21/1000;
                _addReceiverBalance(from, feeAddress2, f2);
                
                _addReceiverBalance(from, to, amount - f1 - f2);
            }
        }
    }
}
