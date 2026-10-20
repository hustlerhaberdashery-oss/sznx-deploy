// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNEternityLock — The Immutable Seal
 * Locks SZNX + WCRO as permanent liquidity in SZNPool for 100 years.
 *
 * Once sealed:
 *   • The contract adds liquidity to SZNPool and OWNS those LP shares
 *   • No withdrawal is possible before lockExpiry (100 years)
 *   • After lockExpiry, only the designated heir can withdraw
 *   • The pool cannot be rugged — this liquidity is infrastructure
 *
 * This transforms liquidity from Capital into Estate.
 */

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ISZNPool {
    function addLiquidity(
        uint256 amountSZNX,
        uint256 amountUSDT,
        uint256 minSZNX,
        uint256 minUSDT,
        bool lockPhase4
    ) external returns (uint256 sharesMinted);
    function removeLiquidity(uint256 sharesToBurn, uint256 minSZNX, uint256 minUSDT)
        external returns (uint256 sznxOut, uint256 usdtOut);
    function shares(address account) external view returns (uint256);
}

contract SZNEternityLock {

    // ── Immutable config ───────────────────────────────────────────────────────
    IERC20    public immutable sznxToken;
    IERC20    public immutable wcroToken;
    ISZNPool  public immutable pool;
    address   public immutable heir;           // beneficiary after lock expires
    uint256   public immutable lockExpiry;     // unix timestamp — 100 years from seal
    uint256   public immutable sealedAt;       // block.timestamp when sealed

    bool      public isSealed;                 // one-way door

    // ── Events ────────────────────────────────────────────────────────────────
    event Sealed(uint256 sznxLocked, uint256 wcroLocked, uint256 sharesMinted, uint256 lockExpiry);
    event HeirWithdrew(uint256 sznxOut, uint256 wcroOut);

    constructor(
        address _sznx,
        address _wcro,
        address _pool,
        address _heir
    ) {
        sznxToken  = IERC20(_sznx);
        wcroToken  = IERC20(_wcro);
        pool       = ISZNPool(_pool);
        heir       = _heir;
        lockExpiry = block.timestamp + (100 * 365 days);
        sealedAt   = block.timestamp;
    }

    /**
     * Seal the estate. One-way, irreversible.
     * Caller deposits SZNX + WCRO → contract adds them as liquidity → LP shares locked.
     */
    function seal(uint256 amountSZNX, uint256 amountWCRO) external {
        require(!isSealed, "EternityLock: already sealed");
        require(amountSZNX > 0 && amountWCRO > 0, "EternityLock: zero amount");

        sznxToken.transferFrom(msg.sender, address(this), amountSZNX);
        wcroToken.transferFrom(msg.sender, address(this), amountWCRO);

        sznxToken.approve(address(pool), amountSZNX);
        wcroToken.approve(address(pool), amountWCRO);

        uint256 sharesMinted = pool.addLiquidity(amountSZNX, amountWCRO, 0, 0, false);

        isSealed = true;

        emit Sealed(amountSZNX, amountWCRO, sharesMinted, lockExpiry);
    }

    /**
     * After 100 years — heir may withdraw.
     */
    function heirWithdraw(uint256 minSZNX, uint256 minWCRO) external {
        require(msg.sender == heir,            "EternityLock: not heir");
        require(block.timestamp >= lockExpiry, "EternityLock: estate still sealed");

        uint256 myShares = pool.shares(address(this));
        require(myShares > 0, "EternityLock: no shares");

        (uint256 sznxOut, uint256 wcroOut) = pool.removeLiquidity(myShares, minSZNX, minWCRO);

        sznxToken.transfer(heir, sznxOut);
        wcroToken.transfer(heir, wcroOut);

        emit HeirWithdrew(sznxOut, wcroOut);
    }

    // ── View ──────────────────────────────────────────────────────────────────
    function lockedShares() external view returns (uint256) {
        return pool.shares(address(this));
    }

    function yearsRemaining() external view returns (uint256) {
        if (block.timestamp >= lockExpiry) return 0;
        return (lockExpiry - block.timestamp) / 365 days;
    }
}
