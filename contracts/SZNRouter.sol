// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNRouter — Sovereign Swap Router
 * Cronos chain (chainId: 25) | Paired with SZNRegistry for referral fee splitting.
 *
 * Fee Architecture (per swap):
 *   → Referrer receives: 0.5% (50 bps)  — direct ERC-20 transfer to referrer
 *   → LP pool receives:  0.3% (30 bps)  — handled internally by SZNPool on amountForPool
 *
 * Swap flow:
 *   User calls swap() →
 *     1. Transfer input token from user
 *     2. Calculate fee split
 *     3. Route referral tithe to SZNRegistry
 *     4. Route LP share to pool
 *     5. Transfer output token to user
 *
 * Supported pairs:
 *   SZNX / USDT  — primary sovereign pair (SZNPool)
 *   SZNX / USDC  — secondary pair (same pool, USDC treated as USDT-equivalent)
 *
 * USDT on Cronos (Crypto.com bridge): 0x66e428c3f67a68878562e79A0234c1F83c208770
 * USDC on Cronos (Multichain bridge):  0xc21223249CA28397B4B6541dfFaEcC539BfF0c59
 */

interface IERC20 {
    function totalSupply()                                          external view returns (uint256);
    function balanceOf(address account)                            external view returns (uint256);
    function transfer(address to, uint256 amount)                  external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount)              external returns (bool);
    function allowance(address owner, address spender)             external view returns (uint256);
}

interface ISZNRegistry {
    function getReferrer(address user)                       external view returns (address);
    function distributeReferralReward(address trader)        external payable;
    function REFERRER_BPS()                                  external view returns (uint256);
}

interface ILiquidityPool {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external returns (uint256 amountOut);
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        external view returns (uint256 amountOut);
}

contract SZNRouter {

    // ── Constants ─────────────────────────────────────────────────────────────
    // Referral fee (0.5%) is the only router-level deduction.
    // LP fees (0.3%) are handled internally by SZNPool on every swap.
    uint256 public constant REFERRAL_FEE_BPS = 50;   // 0.5% to referrer
    uint256 public constant BPS_DENOM        = 10_000;

    // ── Addresses ─────────────────────────────────────────────────────────────
    address public immutable sznToken;    // SZNX (18 decimals)
    address public immutable usdcToken;   // USDC on Cronos — secondary stable
    address public immutable usdtToken;   // USDT on Cronos — primary stable (SZNPool pair)
    ISZNRegistry public immutable registry;
    ILiquidityPool public pool;           // SZNPool (SZNX/USDT)
    address public owner;

    // Stable tokens accepted as input — routed through USDT pool
    mapping(address => bool) public isAcceptedStable;

    // ── Events ────────────────────────────────────────────────────────────────
    event Swapped(
        address indexed trader,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 lpFee,
        uint256 referralFee,
        address referrer
    );
    event PoolUpdated(address indexed newPool);

    // ── Modifiers ─────────────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "SZNRouter: not owner");
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(
        address _sznToken,
        address _usdcToken,
        address _usdtToken,
        address _registry,
        address _pool
    ) {
        require(_sznToken  != address(0), "SZNRouter: zero SZNX");
        require(_usdcToken != address(0), "SZNRouter: zero USDC");
        require(_usdtToken != address(0), "SZNRouter: zero USDT");
        require(_registry  != address(0), "SZNRouter: zero registry");

        sznToken  = _sznToken;
        usdcToken = _usdcToken;
        usdtToken = _usdtToken;
        registry  = ISZNRegistry(_registry);
        pool      = ILiquidityPool(_pool);
        owner     = msg.sender;

        // Both stablecoins accepted as input; pool always pairs SZNX/USDT
        isAcceptedStable[_usdtToken] = true;
        isAcceptedStable[_usdcToken] = true;
    }

    // ── Core Swap ─────────────────────────────────────────────────────────────

    /**
     * Execute a swap with optional referral fee splitting.
     * @param tokenIn    Address of input token (SZNX or USDT only — USDC not yet active)
     * @param tokenOut   Address of output token (SZNX or USDT only)
     * @param amountIn   Gross input amount (before fees)
     * @param minOut     Minimum acceptable output (slippage guard)
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut
    ) external returns (uint256 amountOut) {
        require(amountIn > 0, "SZNRouter: zero amount");

        // USDC routing requires a stable bridge — not yet active
        require(tokenIn != usdcToken && tokenOut != usdcToken, "SZNRouter: USDC routing not yet active");

        bool validPair = (tokenIn == sznToken  && tokenOut == usdtToken) ||
                         (tokenIn == usdtToken && tokenOut == sznToken);
        require(validPair, "SZNRouter: unsupported pair");

        // Pull input from trader
        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "SZNRouter: transferFrom failed"
        );

        // ── Referral fee (0.5%) — Clause II ───────────────────────────────
        address referrer    = registry.getReferrer(msg.sender);
        uint256 referralFee = 0;
        if (referrer != address(0)) {
            referralFee = (amountIn * REFERRAL_FEE_BPS) / BPS_DENOM;
            require(
                IERC20(tokenIn).transfer(referrer, referralFee),
                "SZNRouter: referral transfer failed"
            );
        }

        // ── Execute swap — pool handles 0.3% LP fee internally ────────────
        uint256 amountForPool = amountIn - referralFee;
        require(
            IERC20(tokenIn).approve(address(pool), amountForPool),
            "SZNRouter: approve failed"
        );
        amountOut = pool.swap(tokenIn, tokenOut, amountForPool, minOut, msg.sender);

        // belt-and-suspenders: pool.swap already enforces minOut internally
        require(amountOut >= minOut, "SZNRouter: slippage exceeded");

        emit Swapped(
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            0,                                              // LP fee is internal to pool
            referrer != address(0) ? referralFee : 0,
            referrer != address(0) ? referrer    : address(0)
        );
    }

    // ── Quote (view) ──────────────────────────────────────────────────────────

    /**
     * Get estimated output for a given input, after all fees.
     * referralFee is 0.5% of amountIn (only deducted when caller has a referrer).
     * lpFee (0.3% of netInput) is deducted inside the pool and reflected in amountOut.
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (
        uint256 amountOut,
        uint256 lpFee,
        uint256 referralFee,
        uint256 netInput
    ) {
        referralFee = (amountIn * REFERRAL_FEE_BPS) / BPS_DENOM;
        netInput    = amountIn - referralFee;
        amountOut   = pool.getAmountOut(tokenIn, tokenOut, netInput);
        // LP fee is embedded in amountOut reduction by pool; surface it for callers
        lpFee       = (netInput * 30) / BPS_DENOM; // pool SWAP_FEE_BPS = 30
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function setPool(address newPool) external onlyOwner {
        require(newPool != address(0), "SZNRouter: zero pool");
        pool = ILiquidityPool(newPool);
        emit PoolUpdated(newPool);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SZNRouter: zero address");
        owner = newOwner;
    }

    // Rescue accidentally sent tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
}
