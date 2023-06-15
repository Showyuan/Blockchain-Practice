// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// comptroller
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { ComptrollerG7 } from "compound-protocol/contracts/ComptrollerG7.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";
// InterestRateModel
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import { InterestRateModel } from "compound-protocol/contracts/InterestRateModel.sol";
// priceOracle
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
// cToken
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
// token
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { TestERC20 } from "../contracts/TestERC20.sol";
import { EIP20Interface } from "compound-protocol/contracts/EIP20Interface.sol";
// test
import "forge-std/Test.sol";
import "forge-std/console.sol";
// aave
import {
  IFlashLoanSimpleReceiver,
  IPoolAddressesProvider,
  IPool
} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
// uniswap
import { ISwapRouter } from "v3-periphery/interfaces/ISwapRouter.sol";

contract CompoundHomework is Test, IFlashLoanSimpleReceiver {

    // users
    address public admin = makeAddr("Admin");
    address public user1 = makeAddr("User1");
    address public user2 = makeAddr("User2");
    // constants
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    // comptroller
    Unitroller unitroller;
    ComptrollerG7 comptrollerG7;
    ComptrollerG7 unitrollerProxy;
    // cToken
    TestERC20 tokenA;
    TestERC20 tokenB;
    CErc20Delegate cTokenADelegate;
    CErc20Delegate cTokenBDelegate;
    CErc20Delegator cTokenA;
    CErc20Delegator cTokenB;
    // usdc
    EIP20Interface IUSDC;
    CErc20Delegate cUsdcDelegate;
    CErc20Delegator cUsdc;
    // uni
    EIP20Interface IUNI;
    CErc20Delegate cUniDelegate;
    CErc20Delegator cUni;
    // priceOracle
    SimplePriceOracle priceOracle;
    WhitePaperInterestRateModel whitePaper;
    // var
    uint256 initialAmount = 150 * 10 ** 18;

    function setUp() public {

        vm.startPrank(admin);

        // SimplePriceOracle
        priceOracle = new SimplePriceOracle();
        // WhitePaperInterestRateModel : 0%
        whitePaper = new WhitePaperInterestRateModel(0, 0);

        // Comptoller proxy settings
        unitroller = new Unitroller();
        comptrollerG7 = new ComptrollerG7();
        unitrollerProxy = ComptrollerG7(address(unitroller));
        unitroller._setPendingImplementation(address(comptrollerG7));
        comptrollerG7._become(unitroller);
        unitrollerProxy._setPriceOracle(priceOracle);

        // deploy TokenA
        deployTokenA();
        // deploy USDC
        deployUsdc();
        // deploy UNI
        deployUni();

        // Close factor: 50%
        unitrollerProxy._setCloseFactor(0.5e18);
        // Liquidation incentive : 8%
        unitrollerProxy._setLiquidationIncentive(1.08 * 1e18);
        
        deal(UNI, user1, 1000 * 10 ** 18); // for user1 borrow
        deal(USDC, admin, 2500 * 10 ** 6); // for user1 borrow
        deal(USDC, address(this), 6.25 * 10 * 6); // premium
        IUSDC.approve(address(cUsdc), 2500 * 10 ** 6);
        cUsdc.mint(2500 * 10 ** 6);

        vm.stopPrank();
    }

    function test_mint_and_redeem() public {
        vm.startPrank(user1);

        uint256 amount = 100 * 10 ** 18;

        // cTokenA mint 100
        tokenA.approve(address(cTokenA), amount);
        cTokenA.mint(amount);
        // check balance
        assertEq(cTokenA.balanceOf(user1), amount);

        // cTokenA redeem 100
        cTokenA.redeem(amount);
        // check balance
        assertEq(cTokenA.balanceOf(user1), 0);
        
        vm.stopPrank();
    }

    function test_borrow_and_repay() public {
        
        vm.startPrank(admin);
        deployTokenB();
        vm.stopPrank();

        uint256 borrowAmount = 50e18;
        uint256 mintAmount = 1e18;

        // user2 mint tokenA
        vm.startPrank(user2);

        tokenA.approve(address(cTokenA), borrowAmount);
        cTokenA.mint(borrowAmount);
        
        vm.stopPrank();

        // user1 borrow tokenA
        vm.startPrank(user1);

        // let tokenB enter markets
        address[] memory addr = new address[](1);
        addr[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(addr);

        // mint 1 tokenB
        tokenB.approve(address(cTokenB), mintAmount);
        cTokenB.mint(mintAmount);

        // borrow 50 tokenA
        cTokenA.borrow(borrowAmount);

        vm.stopPrank();
    }

    function test_liquidation_collateralFactor() public {

        test_borrow_and_repay();

        // 50(tokenA) * 50%
        uint256 repayAmount = 25e18; 

        vm.prank(admin);
        // 0.5 -> 0.4
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 0.4e18);

        vm.startPrank(user2);

        tokenA.approve(address(cTokenA), repayAmount);
        cTokenA.liquidateBorrow(user1, repayAmount, cTokenB);

        vm.stopPrank();

    }

    function test_liquidation_oracle() public {

        test_borrow_and_repay();

        // 50(tokenA) * 50%
        uint256 repayAmount = 25e18; 

        vm.prank(admin);
        // $100 -> $70
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 70e18);

        vm.startPrank(user2);

        tokenA.approve(address(cTokenA), repayAmount);
        cTokenA.liquidateBorrow(user1, repayAmount, cTokenB);

        vm.stopPrank();
    }

    // forge test --fork-url https://eth-mainnet.g.alchemy.com/v2/jLiLx82EZbK1WsZ94UWWeNt27AwcGBiN --fork-block-number 17465000
    function test_aave_flash_loan() public {

        // user1 borrow tokenA
        vm.startPrank(user1);

        // let tokenB enter markets
        address[] memory addr = new address[](1);
        addr[0] = address(cUni);
        unitrollerProxy.enterMarkets(addr);

        // mint 1000 UNI
        IUNI.approve(address(cUni), 1000 * 10 ** 18);
        cUni.mint(1000 * 10 ** 18);

        // borrow 2500 USDC
        cUsdc.borrow(2500 * 10 ** 6);

        vm.stopPrank();

        // let User1 Shortfall
        vm.prank(admin);
        // $5 -> $4
        priceOracle.setUnderlyingPrice(CToken(address(cUni)), 4e18);

        // User2 user flash loan to liquidate User1
        vm.startPrank(user2);

        // AAVE: flashLoanSimple
        // 2500 * 50% = 1250 usdc
        POOL().flashLoanSimple(address(this), USDC, 1250 * 10 ** 6, abi.encode(0x00), 0);

        // earn 63 USDC
        console.log("Final USDC Balance: %s", EIP20Interface(USDC).balanceOf(address(this)));
    }

    function deployTokenA() public {

        // tokenA
        tokenA = new TestERC20("TokenA","TokenA");
        tokenA.mint(address(user1), initialAmount);
        tokenA.mint(address(user2), initialAmount);

        cTokenADelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);

        // decimals : 18
        cTokenA = new CErc20Delegator(
            address(tokenA),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e18,
            "Compound TokenA",
            "cTokenA",
            18,
            payable(address(uint160(admin))),
            address(cTokenADelegate),
            data );
        cTokenA._setImplementation(address(cTokenADelegate), false, data);

        // Underlying Price : $1
        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e18);
        // Reserve Factor : 0%
        cTokenA._setReserveFactor(0);
        // support tokenA into Market
        unitrollerProxy._supportMarket(CToken(address(cTokenA)));
        // Close Factor : 50%
        unitrollerProxy._setCloseFactor(0.5e18);
    }

    function deployTokenB() public {
        
        // tokenB
        tokenB = new TestERC20("TokenB","TokenB");
        tokenB.mint(address(user1), initialAmount);
        tokenB.mint(address(user2), initialAmount);

        cTokenBDelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);

        // decimals : 18
        cTokenB = new CErc20Delegator(
            address(tokenB),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e18,
            "Compound TokenB",
            "cTokenB",
            18,
            payable(address(uint160(admin))),
            address(cTokenBDelegate),
            data );
        cTokenB._setImplementation(address(cTokenBDelegate), false, data);
        
        // token B Underlying Price : $100
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 100e18);
        // Reserve Factor : 0%
        cTokenB._setReserveFactor(0);
        // support tokenB into Market
        unitrollerProxy._supportMarket(CToken(address(cTokenB)));
        // Close Factor : 50%
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 0.5e18);
    }

    function deployUsdc() public {
        IUSDC = EIP20Interface(USDC);
        
        cUsdcDelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);
                
        // cUsdc
        // Exchange rate : 10 ^ (18 - cToken decimals + underlying token decimals)
        cUsdc = new CErc20Delegator(
            USDC,
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e6,
            "Compound USDC",
            "cUSDC",
            18,
            payable(address(uint160(admin))),
            address(cUsdcDelegate),
            data );
        cUsdc._setImplementation(address(cUsdcDelegate), false, data);

        // Underlying Price : $1
        // 10 ^ (36 - underlying asset decimals)
        priceOracle.setUnderlyingPrice(CToken(address(cUsdc)), 1e30);
        // Reserve Factor : 0%
        cUsdc._setReserveFactor(0);
        // support cUsdc into Market
        unitrollerProxy._supportMarket(CToken(address(cUsdc)));
    }

    function deployUni() public {

        IUNI = EIP20Interface(UNI);
        
        cUniDelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);

        // cUni
        // Exchange rate : 10 ^ (18 - cToken decimals + underlying token decimals)
        cUni = new CErc20Delegator(
            UNI,
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e18,
            "Compound UNI",
            "cUNI",
            18,
            payable(address(uint160(admin))),
            address(cUniDelegate),
            data );
        cUni._setImplementation(address(cUniDelegate), false, data);

        // Underlying Price : $5
        // 10 ^ (36 - underlying asset decimals)
        priceOracle.setUnderlyingPrice(CToken(address(cUni)), 5e18);
        // Reserve Factor : 0%
        cUni._setReserveFactor(0);
        // support cUni into Market
        unitrollerProxy._supportMarket(CToken(address(cUni)));
        // 設定 UNI 的 collateral factor 為 50%
        unitrollerProxy._setCollateralFactor(CToken(address(cUni)), 0.5e18);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        // 1250 USDC
        console.log("liquidate amount: %s", amount);
        IUSDC.approve(address(cUsdc), amount);
        // liquidate user1's USDC get cUni
        cUsdc.liquidateBorrow(user1, amount, cUni);
        console.log("cUni balance: %s", cUni.balanceOf(address(this)));
        // redeem cUni get Uni
        cUni.redeem(cUni.balanceOf(address(this)));
        console.log("Uni balance: %s", IUNI.balanceOf(address(this)));
        // swap UNI for USDC
        uint256 amtIn = IUNI.balanceOf(address(this));

        IUNI.approve(address(SWAP_ROUTER), amtIn);

        ISwapRouter.ExactInputSingleParams memory swapParams =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: UNI,
            tokenOut: USDC,
            fee: 3000, // 0.3%
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amtIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        uint256 amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(swapParams);

        // approve AAVE transfer amount + premium 0.05% USDC
        EIP20Interface(asset).approve(address(POOL()), amount + premium);
        return true;
    }
    
    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}