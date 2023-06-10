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
// test
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract CompoundHomework is Test {

    // users
    address public admin = makeAddr("Admin");
    address public user1 = makeAddr("User1");
    address public user2 = makeAddr("User2");
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
}