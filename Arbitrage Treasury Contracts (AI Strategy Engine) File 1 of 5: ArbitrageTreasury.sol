// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPancake.sol";
import "./AccessControl.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";

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

interface IPancakeV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint32 feeProtocol,
            bool unlocked
        );
}

contract ArbitrageTreasury is TraderAccessControl {
    address private constant bnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address private constant usdt = 0x55d398326f99059fF775485246999027B3197955;
    address private constant erc20 = 0xe1ED729eAD2f59DBf643e011b606335F03Fc5606;
    address private constant doge = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43;

    address private constant btc = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    address private constant eth = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address private constant xrp = 0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE;
    address private constant sol = 0x570A5D26f7765Ecb712C0924E4De545B89fD43dF;
    
    IPancakeRouter02 private constant uniswapV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address private constant factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    ISwapRouter private constant swapRouter = ISwapRouter(0x1b81D678ffb9C0263b24A97847620C99d213eB14);

    uint256 private constant Q96 = 0x1000000000000000000000000;
    uint256 private constant DECIMALS_18 = 10**18;

    constructor() {
        IERC20(usdt).approve(address(uniswapV2Router), type(uint256).max);
        IERC20(erc20).approve(address(uniswapV2Router), type(uint256).max);
        IERC20(doge).approve(address(uniswapV2Router), type(uint256).max);
        IERC20(eth).approve(address(uniswapV2Router), type(uint256).max);
        IERC20(xrp).approve(address(uniswapV2Router), type(uint256).max);

        IERC20(usdt).approve(address(swapRouter), type(uint256).max);
        IERC20(btc).approve(address(swapRouter), type(uint256).max);
        IERC20(eth).approve(address(swapRouter), type(uint256).max);
        IERC20(xrp).approve(address(swapRouter), type(uint256).max);
        IERC20(sol).approve(address(swapRouter), type(uint256).max);
    }

    receive() external payable {}

    function approveRouter(uint256 tokenType, uint256 routerType, uint256 amount) external onlyTrader {
        address token = getAddressByTokenType(tokenType);
        address r = address(uniswapV2Router);
        if(routerType == 3) {
            r = address(swapRouter);
        }
        IERC20(token).approve(r, amount);
    }

    // btc eth xrp sol usdt
    function swapBNBForTokenV3(uint256 tokenType, uint256 bnbAmount, uint256 minTokenAmount, uint256 deadline) external onlyTrader {
        require(tokenType == 1 || tokenType == 2 || tokenType == 4 || tokenType == 5 || tokenType == 7, 't');
        address tokenOut = getAddressByTokenType(tokenType);
        ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: bnb,
                tokenOut: tokenOut,
                fee: getFeeByTokenType(tokenType),
                recipient: address(this),
                deadline: deadline,
                amountIn: bnbAmount,
                amountOutMinimum: minTokenAmount,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle{value: bnbAmount}(params);
    }

    // btc eth xrp sol usdt
    function swapTokenForBNBV3(uint256 tokenType, uint256 tokenAmount, uint256 minBNBAmount, uint256 deadline) external onlyTrader {
        require(tokenType == 1 || tokenType == 2 || tokenType == 4 || tokenType == 5 || tokenType == 7, 't');
        address tokenIn = getAddressByTokenType(tokenType);
        ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: bnb,
                fee: getFeeByTokenType(tokenType),
                recipient: address(this),
                deadline: deadline,
                amountIn: tokenAmount,
                amountOutMinimum: minBNBAmount,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle(params);
        IERC20(bnb).withdraw( IERC20(bnb).balanceOf(address(this)) );
    }

    // eth doge xrp usdt   bnb
    function swapBNBForTokenV2(uint256 tokenType, uint256 bnbAmount, uint256 minTokenAmount, uint256 deadline) external onlyTrader {
        require(tokenType == 2 || tokenType == 4 || tokenType == 6 || tokenType == 7, 't');
        address[] memory path = new address[](2);
        path[0] = bnb;
        path[1] = getAddressByTokenType(tokenType);
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: bnbAmount}(minTokenAmount, path, address(this), deadline);
    }

    // eth doge xrp usdt   bnb
    function swapTokenForBNBV2(uint256 tokenType, uint256 tokenAmount, uint256 minBNBAmount, uint256 deadline) external onlyTrader {
        require(tokenType == 2 || tokenType == 4 || tokenType == 6 || tokenType == 7, 't');
        address[] memory path = new address[](2);
        path[0] = getAddressByTokenType(tokenType);
        path[1] = bnb;
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, minBNBAmount, path, address(this), deadline);
    }

    // usdt-erc20
    function swapUSDTForToken(uint256 usdtAmount, uint256 minTokenAmount, uint256 deadline) external onlyTrader {
        address[] memory path = new address[](2);
        path[0] = usdt;
        path[1] = erc20;
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(usdtAmount, minTokenAmount, path, address(this), deadline);
    }

    // usdt-erc20
    function swapTokenForUSDT(uint256 tokenAmount, uint256 minUSDTAmount, uint256 deadline) external onlyTrader {
        address[] memory path = new address[](2);
        path[0] = erc20;
        path[1] = usdt;
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(tokenAmount, minUSDTAmount, path, address(this), deadline);
    }

    function burn(uint256 amount) external onlyTrader {
        IERC20(erc20).burn(amount);
    }

    function getAddressByTokenType(uint256 tokenType) public pure returns(address) {
        if(tokenType == 0) {
            return erc20;
        }else if(tokenType == 1) {
            return btc;
        }else if(tokenType == 2) {
            return eth;
        }else if(tokenType == 3) {
            return bnb;
        }else if(tokenType == 4) {
            return xrp;
        }else if(tokenType == 5) {
            return sol;
        }else if(tokenType == 6){
            return doge;
        }else {
            return usdt;
        }
    }

    function getFeeByTokenType(uint256 tokenType) public pure returns(uint24) {
        if(tokenType == 4) {
            return 2500;
        }else if(tokenType == 7) {
            return 100;
        }
        return 500;
    }

    // btc eth xrp sol doge   bnb usdt
    function getValue() external view returns(uint256 v) {
        // bnb   btc eth xrp sol   doge
        uint256 bnbAmount = address(this).balance + getBNBValueV3(1) + getBNBValueV3(2) + getBNBValueV3(4) + getBNBValueV3(5) + getBNBValueV2(6);
        v = IERC20(usdt).balanceOf(address(this)) + bnbAmount*DECIMALS_18/getV3PriceByTokenType(7);
    }

    function getBNBValueV3(uint256 tokenType) public view returns(uint256) {
        address tokenAddress = getAddressByTokenType(tokenType);
        uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
        if(tokenBalance > 0) {
            uint256 tokenPrice = getV3PriceByTokenType(tokenType);
            return tokenBalance*tokenPrice/DECIMALS_18;
        }
        return 0;
    }

    function getBNBValueV2(uint256 tokenType) public view returns(uint256) {
        address tokenAddress = getAddressByTokenType(tokenType);
        uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
        if(tokenBalance > 0) {
            (uint256 r0Token, uint256 r1BNB) = getReserves(tokenAddress, bnb);
            return tokenBalance*r1BNB/r0Token;
        }
        return 0;
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        address pair = address(uint160(uint(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            hex'00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5'
        )))));

        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getTokenBalance() external view returns(uint256 u, uint256 er, uint256 bt, uint256 et, uint256 bn, uint256 x, uint256 so, uint256 d) {
        u = IERC20(usdt).balanceOf(address(this));
        er = IERC20(erc20).balanceOf(address(this));
        bt = IERC20(btc).balanceOf(address(this));
        et = IERC20(eth).balanceOf(address(this));
        bn = address(this).balance;
        x = IERC20(xrp).balanceOf(address(this));
        so = IERC20(sol).balanceOf(address(this));
        d = IERC20(doge).balanceOf(address(this));
    }

    // eth doge xrp usdt   bnb
    function getAmountOutV2(uint256 tradeSide, uint256 tokenType, uint256 amount) external view returns(uint256) {
        address[] memory path = new address[](2);
        if(tradeSide == 0) {
            if(tokenType == 0) {
                path[0] = usdt;
                path[1] = erc20;
            }else {
                path[0] = bnb;
                path[1] = getAddressByTokenType(tokenType);
            }
        }else {
            if(tokenType == 0) {
                path[0] = erc20;
                path[1] = usdt;
            }else {
                path[0] = getAddressByTokenType(tokenType);
                path[1] = bnb;
            }
        }
        uint[] memory amounts = new uint[](2);
        amounts = uniswapV2Router.getAmountsOut(amount, path);
        return amounts[1];
    }

    // btc eth xrp sol usdt   bnb
    function getPoolByTokenType(uint256 tokenType) public pure returns(address) {
        if(tokenType == 1) {
            return 0x6bbc40579ad1BBD243895cA0ACB086BB6300d636;
        }else if(tokenType == 2) {
            return 0xD0e226f674bBf064f54aB47F42473fF80DB98CBA;
        }else if(tokenType == 4) {
            return 0xd15B00E81F98A7DB25f1dC1BA6E983a4316c4CaC;
        }else if(tokenType == 5) {
            return 0xbFFEc96e8f3b5058B1817c14E4380758Fada01EF;
        }else {
            return 0x172fcD41E0913e95784454622d1c3724f546f849;
        }
    }

    function getV3PriceByTokenType(uint256 tokenType) public view returns (uint256 price) {
        address pool = getPoolByTokenType(tokenType);
        (uint160 sqrtPriceX96,,,,,,) =  IPancakeV3Pool(pool).slot0();
        return sqrtPriceX96ToHumanPrice(sqrtPriceX96);
    }

    function sqrtPriceX96ToHumanPrice(uint160 sqrtPriceX96) public pure returns (uint256 price) {
        uint256 numerator = uint256(sqrtPriceX96) * DECIMALS_18;
        uint256 priceX96Decimals = numerator / Q96;
        price = (priceX96Decimals * uint256(sqrtPriceX96)) / Q96;
    }
}
