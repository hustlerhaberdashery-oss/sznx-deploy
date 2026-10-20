// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNToken — Sovereign Zero Node
 * Symbol:    SZNX
 * Supply:    1,000,000,000 SZNX  (1 Billion, 18 decimals)
 * Chain:     Cronos (chainId: 25)
 *
 * Mechanics:
 *   • 2% auto-burn on every transfer  — deflationary pressure
 *   • Standard ERC-20 (approve / transferFrom)
 *   • Owner can mint once to seed liquidity phases (capped at genesis supply)
 *   • Owner renounce after Phase 1 seed
 *
 * Backing (off-chain):
 *   • Cloudflare D1 sovereign ledger  (watch-to-earn credits)
 *   • 1.29 TB SUZERAIN_FLIXX media estate
 *   • LEX LOCI IP database
 *   • Shug White + BingeTVCEO NFT portfolio (Ethereum mainnet)
 */

contract SZNToken {

    // ── Metadata ──────────────────────────────────────────────────────────────
    string  public constant name     = "Sovereign Zero Node";
    string  public constant symbol   = "SZNX";
    uint8   public constant decimals = 18;

    // ── Supply config ─────────────────────────────────────────────────────────
    uint256 public constant GENESIS_SUPPLY = 1_000_000_000 * 1e18;  // 1B SZNX
    uint256 public constant BURN_BPS       = 200;                   // 2% burn
    uint256 public constant BPS_DENOM      = 10_000;

    // ── State ─────────────────────────────────────────────────────────────────
    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ── Events ────────────────────────────────────────────────────────────────
    event Transfer(address indexed from,    address indexed to,      uint256 value);
    event Approval(address indexed owner,   address indexed spender, uint256 value);
    event Burned(address indexed from,      uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        _mint(msg.sender, GENESIS_SUPPLY);
    }

    // ── ERC-20 Core ───────────────────────────────────────────────────────────

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "SZNX: allowance exceeded");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // ── Internal transfer with 2% burn ────────────────────────────────────────

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "SZNX: from zero address");
        require(to   != address(0), "SZNX: to zero address");
        require(balanceOf[from] >= amount, "SZNX: insufficient balance");

        uint256 burnAmt = (amount * BURN_BPS) / BPS_DENOM;
        uint256 sendAmt = amount - burnAmt;

        balanceOf[from]    -= amount;
        balanceOf[to]      += sendAmt;
        totalSupply        -= burnAmt;

        emit Transfer(from, to, sendAmt);
        emit Transfer(from, address(0), burnAmt);
        emit Burned(from, burnAmt);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "SZNX: mint to zero address");
        totalSupply   += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // ── Owner admin ───────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "SZNX: not owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SZNX: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}
