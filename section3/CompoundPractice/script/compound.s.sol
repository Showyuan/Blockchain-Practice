// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
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
// fakeToken
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

contract MyScript is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address myAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // 使用 SimplePriceOracle 作為 Oracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();
        // 使用 WhitePaperInterestRateModel 作為利率模型，利率模型合約中的借貸利率設定為 0%
        WhitePaperInterestRateModel whitePaper = new WhitePaperInterestRateModel(0, 0);

        // Comptoller proxy 設定
        Unitroller unitroller = new Unitroller();
        ComptrollerG7 comptrollerG7 = new ComptrollerG7();
        ComptrollerG7 unitrollerProxy = ComptrollerG7(address(unitroller));
        unitroller._setPendingImplementation(address(comptrollerG7));
        comptrollerG7._become(unitroller);
        unitrollerProxy._setPriceOracle(priceOracle);

        // 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
        ERC20 fakeToken = new ERC20("FakeToken","FakeToken");
        CErc20Delegate cTokenDelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);

        // cERC20 的 decimals 為 18
        CErc20Delegator cToken = new CErc20Delegator(
            address(fakeToken),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e18,
            "Compound FakeToken",
            "cFakeToken",
            18,
            payable(address(uint160(myAddress))),
            address(cTokenDelegate),
            data );
        
        cToken._setImplementation(address(cTokenDelegate), false, data);
        // 初始 exchangeRate 為 1:1，表示合約本身不抽中介費
        cToken._setReserveFactor(0);

        vm.stopBroadcast();
    }
}