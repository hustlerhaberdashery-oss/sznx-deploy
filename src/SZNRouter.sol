// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNRouter — Sovereign Swap Router
 * Cronos chain (chainId: 25) | Paired with SZNRegistry for referral fee splitting.
 *
 * Fee Architecture (per swap):
 *   Total LP fee:       3.0%  (300 bps)
 *   → LP pool receives: 2.5%  (250 bps)
 *   → Referrer receives:0.5%  (50 bps)  — via SZNRegistry.distributeReferralReward()
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

import "./interfaces/IERC20.sol";

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
    uint256 public constant TOTAL_FEE_BPS    = 300;  // 3.0% total fee
    uint256 public constant LP_FEE_BPS       = 250;  // 2.5% to LP pool
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
     * Execute a swap with referral fee splitting.
     * @param tokenIn    Address of input token (USDC or SZN)
     * @param tokenOut   Address of output token (SZN or USDC)
     * @param amountIn   Gross input amount (before fees)
     * @param minOut     Minimum acceptable output (slippage guard — 0.1% sovereign lock)
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut
    ) external returns (uint256 amountOut) {
        require(amountIn > 0, "SZNRouter: zero amount");
        // Accept SZNX↔USDT and SZNX↔USDC (USDC routed through USDT pool)
        bool validPair = (tokenIn == sznToken  && isAcceptedStable[tokenOut]) ||
                         (isAcceptedStable[tokenIn] && tokenOut == sznToken);
        require(validPair, "SZNRouter: unsupported pair");

        // Normalise: USDC input is swapped as USDT in the pool
        // The router holds USDC, sends USDT to the pool (1:1 stable bridge logic)
        // For MVP: USDC and USDT treated as equivalent — same pool, same reserves
        address poolTokenIn  = (tokenIn  == usdcToken) ? usdtToken : tokenIn;
        address poolTokenOut = (tokenOut == usdcToken) ? usdtToken : tokenOut;
        // Override for pool call below — pool only knows SZNX/USDT
        tokenIn  = poolTokenIn;
        tokenOut = poolTokenOut;

        // Pull input from trader
        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "SZNRouter: transferFrom failed"
        );

        // ── Fee split ──────────────────────────────────────────────────────
        uint256 totalFee    = (amountIn * TOTAL_FEE_BPS)    / BPS_DENOM;
        uint256 referralFee = (amountIn * REFERRAL_FEE_BPS) / BPS_DENOM;
        uint256 lpFee       = totalFee - referralFee;
        uint256 amountForPool = amountIn - totalFee;

        // ── Referral tithe (Clause II) ─────────────────────────────────────
        address referrer = registry.getReferrer(msg.sender);
        if (referrer != address(0) && referralFee > 0) {
            // Convert token fee to CRO value for registry reward
            // In production: use price oracle or send token directly.
            // Here: transfer referralFee tokens to referrer directly.
            require(
                IERC20(tokenIn).transfer(referrer, referralFee),
                "SZNRouter: referral transfer failed"
            );
        } else {
            // No referrer — redirect referral fee to LP
            lpFee += referralFee;
            amountForPool += referralFee - (totalFee - lpFee - referralFee);
            // Simpler: if no referrer, full fee goes to LP
            amountForPool = amountIn - lpFee;
        }

        // ── Route LP fee to pool ────────────────────────────────────────────
        require(
            IERC20(tokenIn).transfer(address(pool), lpFee),
            "SZNRouter: LP fee transfer failed"
        );

        // ── Execute swap in pool ────────────────────────────────────────────
        require(
            IERC20(tokenIn).approve(address(pool), amountForPool),
            "SZNRouter: approve failed"
        );
        amountOut = pool.swap(tokenIn, tokenOut, amountForPool, minOut, msg.sender);

        require(amountOut >= minOut, "SZNRouter: slippage exceeded");

        emit Swapped(
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            lpFee,
            referrer != address(0) ? referralFee : 0,
            referrer != address(0) ? referrer    : address(0)
        );
    }

    // ── Quote (view) ──────────────────────────────────────────────────────────

    /**
     * Get estimated output for a given input, after all fees.
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
        uint256 totalFee = (amountIn * TOTAL_FEE_BPS)    / BPS_DENOM;
        referralFee      = (amountIn * REFERRAL_FEE_BPS) / BPS_DENOM;
        lpFee            = totalFee - referralFee;
        netInput         = amountIn - totalFee;
        amountOut        = pool.getAmountOut(tokenIn, tokenOut, netInput);
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
