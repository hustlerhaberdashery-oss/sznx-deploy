// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔═══════════════════════════════════════════════════════╗
 * ║  SZNPool — Sovereign Liquidity Pool                  ║
 * ║  Constant-Product AMM  ·  SZNX / USDT pair           ║
 * ║  Cronos Chain (chainId: 25)                          ║
 * ╚═══════════════════════════════════════════════════════╝
 *
 * Mechanics:
 *   k = reserveSZNX * reserveUSDT  (constant product invariant)
 *
 * Fee Architecture:
 *   Swap fee:    0.3%  (30 bps) — stays in pool, accrues to LPs
 *   Zero protocol fee at genesis — full 0.3% to liquidity providers
 *
 * LP Shares:
 *   First deposit: shares = sqrt(amountSZNX * amountUSDT)
 *   Subsequent:    shares = min(amountSZNX/reserveSZNX, amountUSDT/reserveUSDT) * totalShares
 *
 * Liquidity Seeding Schedule (GENESIS):
 *   Phase 1 — GENESIS SEED:    1,000,000 SZNX  +   100,000 USDT  → price: $0.10/SZNX
 *   Phase 2 — SERIES A DEPTH:  4,000,000 SZNX  +   400,000 USDT  → deepens to $500K TVL
 *   Phase 3 — BOND CORRIDOR:  10,000,000 SZNX  + 1,000,000 USDT  → $1M TVL threshold
 *   Phase 4 — SOVEREIGN LOCK: 50,000,000 SZNX  + 5,000,000 USDT  → $5M TVL / 180-day lockup
 *
 * Deploy sequence:
 *   1. Deploy SZNToken                         → sznxToken address
 *   2. Deploy SZNPool(sznxToken, usdtToken)    → pool address
 *   3. Deploy SZNRouter(sznx, usdt, registry, pool)
 *   4. Call router.authorizePool(pool)
 *   5. Approve pool for both tokens
 *   6. Call pool.addLiquidity(1_000_000e18, 100_000e6, 0, 0, false)  ← GENESIS SEED
 */

interface IERC20 {
    function totalSupply()                                            external view returns (uint256);
    function balanceOf(address account)                              external view returns (uint256);
    function transfer(address to, uint256 amount)                    external returns (bool);
    function transferFrom(address from, address to, uint256 amount)  external returns (bool);
    function approve(address spender, uint256 amount)                external returns (bool);
}

contract SZNPool {

    // ── Tokens ────────────────────────────────────────────────────────────────
    IERC20 public immutable sznxToken;   // SZNX (18 decimals)
    IERC20 public immutable usdtToken;   // USDT (6 decimals on Cronos)

    // ── Reserves ─────────────────────────────────────────────────────────────
    uint256 public reserveSZNX;
    uint256 public reserveUSDT;

    // ── LP Shares (ERC-20 lite — internal ledger, no transfer hooks) ──────────
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    // ── Fee ──────────────────────────────────────────────────────────────────
    uint256 public constant SWAP_FEE_BPS = 30;    // 0.3%
    uint256 public constant BPS_DENOM    = 10_000;

    // ── Lockup schedule ───────────────────────────────────────────────────────
    // Phase 4 LP tokens are locked for 180 days from deposit
    uint256 public constant SOVEREIGN_LOCK_SECS = 180 days;
    mapping(address => uint256) public lockExpiry; // LP => unlock timestamp

    // ── Access ────────────────────────────────────────────────────────────────
    address public owner;
    address public authorizedRouter;

    // ── Reentrancy guard ──────────────────────────────────────────────────────
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;

    // ── Events ────────────────────────────────────────────────────────────────
    event LiquidityAdded(
        address indexed provider,
        uint256 sznxIn,
        uint256 usdtIn,
        uint256 sharesMinted,
        uint256 newReserveSZNX,
        uint256 newReserveUSDT
    );
    event LiquidityRemoved(
        address indexed provider,
        uint256 sznxOut,
        uint256 usdtOut,
        uint256 sharesBurned
    );
    event Swapped(
        address indexed trader,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        uint256 newReserveSZNX,
        uint256 newReserveUSDT
    );
    event RouterAuthorized(address indexed router);

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "SZNPool: not owner");
        _;
    }

    modifier onlyRouter() {
        require(
            msg.sender == authorizedRouter || msg.sender == owner,
            "SZNPool: caller not authorized"
        );
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "SZNPool: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(address _sznxToken, address _usdtToken) {
        require(_sznxToken != address(0), "SZNPool: zero SZNX");
        require(_usdtToken != address(0), "SZNPool: zero USDT");
        sznxToken = IERC20(_sznxToken);
        usdtToken = IERC20(_usdtToken);
        owner     = msg.sender;
        _status   = _NOT_ENTERED;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function authorizeRouter(address router) external onlyOwner {
        require(router != address(0), "SZNPool: zero router");
        authorizedRouter = router;
        emit RouterAuthorized(router);
    }

    // ── Add Liquidity ─────────────────────────────────────────────────────────

    /**
     * @notice Deposit SZNX and USDT to receive LP shares.
     * @param sznxDesired   Amount of SZNX to deposit (18 decimals)
     * @param usdtDesired   Amount of USDT to deposit (6 decimals)
     * @param sznxMin       Minimum SZNX to accept (slippage guard)
     * @param usdtMin       Minimum USDT to accept (slippage guard)
     * @param sovereign     If true, applies 180-day Phase 4 lockup
     * @return sharesMinted LP shares received
     */
    function addLiquidity(
        uint256 sznxDesired,
        uint256 usdtDesired,
        uint256 sznxMin,
        uint256 usdtMin,
        bool    sovereign
    ) external nonReentrant returns (uint256 sharesMinted) {
        require(sznxDesired > 0 && usdtDesired > 0, "SZNPool: zero amounts");

        uint256 sznxIn = sznxDesired;
        uint256 usdtIn = usdtDesired;

        // If pool already has reserves, enforce proportional deposit
        if (reserveSZNX > 0 && reserveUSDT > 0) {
            // Optimal USDT for desired SZNX
            uint256 usdtOptimal = (sznxDesired * reserveUSDT) / reserveSZNX;
            if (usdtOptimal <= usdtDesired) {
                require(usdtOptimal >= usdtMin, "SZNPool: insufficient USDT");
                usdtIn = usdtOptimal;
            } else {
                // Optimal SZNX for desired USDT
                uint256 sznxOptimal = (usdtDesired * reserveSZNX) / reserveUSDT;
                require(sznxOptimal >= sznxMin, "SZNPool: insufficient SZNX");
                sznxIn = sznxOptimal;
            }
        }

        // Transfer tokens in
        require(sznxToken.transferFrom(msg.sender, address(this), sznxIn),  "SZNPool: SZNX transfer failed");
        require(usdtToken.transferFrom(msg.sender, address(this), usdtIn),  "SZNPool: USDT transfer failed");

        // Mint LP shares
        if (totalShares == 0) {
            // Genesis: geometric mean of deposits (Uniswap V2 pattern)
            sharesMinted = _sqrt(sznxIn * (usdtIn * 1e12)); // normalize USDT to 18d before sqrt
        } else {
            uint256 shareBySZNX = (sznxIn * totalShares) / reserveSZNX;
            uint256 shareByUSDT = (usdtIn * totalShares) / reserveUSDT;
            sharesMinted = shareBySZNX < shareByUSDT ? shareBySZNX : shareByUSDT;
        }

        require(sharesMinted > 0, "SZNPool: zero shares minted");

        shares[msg.sender] += sharesMinted;
        totalShares        += sharesMinted;
        reserveSZNX        += sznxIn;
        reserveUSDT        += usdtIn;

        // Phase 4 sovereign lockup
        if (sovereign) {
            lockExpiry[msg.sender] = block.timestamp + SOVEREIGN_LOCK_SECS;
        }

        emit LiquidityAdded(msg.sender, sznxIn, usdtIn, sharesMinted, reserveSZNX, reserveUSDT);
    }

    // ── Remove Liquidity ──────────────────────────────────────────────────────

    /**
     * @notice Burn LP shares to receive proportional SZNX and USDT.
     * @param sharesToBurn  Number of LP shares to redeem
     * @param sznxMin       Minimum SZNX to receive (slippage guard)
     * @param usdtMin       Minimum USDT to receive (slippage guard)
     */
    function removeLiquidity(
        uint256 sharesToBurn,
        uint256 sznxMin,
        uint256 usdtMin
    ) external nonReentrant returns (uint256 sznxOut, uint256 usdtOut) {
        require(sharesToBurn > 0,                        "SZNPool: zero shares");
        require(shares[msg.sender] >= sharesToBurn,      "SZNPool: insufficient shares");
        require(
            lockExpiry[msg.sender] == 0 || block.timestamp >= lockExpiry[msg.sender],
            "SZNPool: sovereign lockup active"
        );

        sznxOut = (sharesToBurn * reserveSZNX) / totalShares;
        usdtOut = (sharesToBurn * reserveUSDT) / totalShares;

        require(sznxOut >= sznxMin, "SZNPool: insufficient SZNX out");
        require(usdtOut >= usdtMin, "SZNPool: insufficient USDT out");

        shares[msg.sender] -= sharesToBurn;
        totalShares        -= sharesToBurn;
        reserveSZNX        -= sznxOut;
        reserveUSDT        -= usdtOut;

        require(sznxToken.transfer(msg.sender, sznxOut), "SZNPool: SZNX out failed");
        require(usdtToken.transfer(msg.sender, usdtOut), "SZNPool: USDT out failed");

        emit LiquidityRemoved(msg.sender, sznxOut, usdtOut, sharesToBurn);
    }

    // ── Swap ──────────────────────────────────────────────────────────────────

    /**
     * @notice Execute a swap. Called by SZNRouter after fee deduction.
     * @param tokenIn       Address of input token (sznxToken or usdtToken)
     * @param tokenOut      Address of output token
     * @param amountIn      Net input amount (after router fee — pool fee taken here)
     * @param minAmountOut  Minimum output (slippage guard)
     * @param recipient     Address to receive output tokens
     * @return amountOut    Actual output amount
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external nonReentrant onlyRouter returns (uint256 amountOut) {
        require(amountIn > 0,    "SZNPool: zero input");
        require(recipient != address(0), "SZNPool: zero recipient");
        _validatePair(tokenIn, tokenOut);

        // Pool fee: 0.3% stays in pool (increases k, accrues to LPs)
        uint256 fee           = (amountIn * SWAP_FEE_BPS) / BPS_DENOM;
        uint256 amountInAfterFee = amountIn - fee;

        bool sznxIn = (tokenIn == address(sznxToken));

        if (sznxIn) {
            // SZNX → USDT
            amountOut = _getAmountOut(amountInAfterFee, reserveSZNX, reserveUSDT);
            require(amountOut >= minAmountOut, "SZNPool: slippage exceeded");

            require(sznxToken.transferFrom(msg.sender, address(this), amountIn), "SZNPool: SZNX in failed");
            require(usdtToken.transfer(recipient, amountOut), "SZNPool: USDT out failed");

            reserveSZNX += amountIn;          // includes fee — grows k
            reserveUSDT -= amountOut;

            emit Swapped(msg.sender, tokenIn, amountIn, amountOut, fee, reserveSZNX, reserveUSDT);
        } else {
            // USDT → SZNX
            amountOut = _getAmountOut(amountInAfterFee, reserveUSDT, reserveSZNX);
            require(amountOut >= minAmountOut, "SZNPool: slippage exceeded");

            require(usdtToken.transferFrom(msg.sender, address(this), amountIn), "SZNPool: USDT in failed");
            require(sznxToken.transfer(recipient, amountOut), "SZNPool: SZNX out failed");

            reserveUSDT += amountIn;
            reserveSZNX -= amountOut;

            emit Swapped(msg.sender, tokenIn, amountIn, amountOut, fee, reserveSZNX, reserveUSDT);
        }
    }

    // ── Price Quotes ──────────────────────────────────────────────────────────

    /**
     * @notice Get estimated output for a given input (includes pool fee).
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        _validatePair(tokenIn, tokenOut);
        uint256 fee           = (amountIn * SWAP_FEE_BPS) / BPS_DENOM;
        uint256 amountInAfterFee = amountIn - fee;

        bool sznxIn = (tokenIn == address(sznxToken));
        if (sznxIn) {
            amountOut = _getAmountOut(amountInAfterFee, reserveSZNX, reserveUSDT);
        } else {
            amountOut = _getAmountOut(amountInAfterFee, reserveUSDT, reserveSZNX);
        }
    }

    /**
     * @notice Current spot price of SZNX in USDT (scaled to 6 decimals).
     * Returns price * 1e6 (e.g., 100000 = $0.10 per SZNX).
     */
    function spotPrice() external view returns (uint256) {
        if (reserveSZNX == 0) return 0;
        // reserveUSDT is 6-decimal, reserveSZNX is 18-decimal
        // price = (reserveUSDT * 1e18) / (reserveSZNX) — returns USDT per SZNX (6 decimals)
        return (reserveUSDT * 1e18) / reserveSZNX;
    }

    /**
     * @notice Total Value Locked in USDT (both sides).
     */
    function tvl() external view returns (uint256) {
        if (reserveSZNX == 0) return reserveUSDT;
        return reserveUSDT * 2;  // by constant-product invariant both sides are equal at genesis price
    }

    // ── Internal Math ─────────────────────────────────────────────────────────

    // Constant product: amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        require(reserveIn > 0 && reserveOut > 0, "SZNPool: empty reserve");
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function _validatePair(address tokenIn, address tokenOut) internal view {
        require(
            (tokenIn == address(sznxToken) && tokenOut == address(usdtToken)) ||
            (tokenIn == address(usdtToken) && tokenOut == address(sznxToken)),
            "SZNPool: invalid pair"
        );
    }

    // Babylonian square root (Uniswap V2 pattern)
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // ── LP Balance Query ──────────────────────────────────────────────────────

    function getLP(address provider) external view returns (
        uint256 lpShares,
        uint256 sznxValue,
        uint256 usdtValue,
        uint256 lockedUntil
    ) {
        lpShares  = shares[provider];
        if (totalShares > 0) {
            sznxValue = (lpShares * reserveSZNX) / totalShares;
            usdtValue = (lpShares * reserveUSDT) / totalShares;
        }
        lockedUntil = lockExpiry[provider];
    }
}
