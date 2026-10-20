// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNRegistry — The Herald's Covenant
 * On-chain referral registry for the SZN Sovereign ecosystem.
 * Deployed on Cronos (chainId: 25).
 *
 * Clause I  — onlyAmbassador(): minimum 1,000 SZN to generate referral link.
 * Clause II — Fee split: 0.5% of volume routed to referrer (called by SZNRouter).
 * Clause III — Immutable bond: mapping(address => address) referrers is write-once per user.
 *
 * Deploy sequence:
 *   1. Deploy SZNToken (or use existing address)
 *   2. Deploy SZNRegistry(sznTokenAddress)
 *   3. Deploy SZNRouter(sznRegistryAddress, ...)
 *   4. Call registry.authorizeRouter(routerAddress)
 */

interface ISZN {
    function balanceOf(address account) external view returns (uint256);
}

contract SZNRegistry {

    // ── Immutable config ───────────────────────────────────────────────────────
    ISZN   public immutable sznToken;
    uint256 public constant MIN_AMBASSADOR = 1_000 * 1e18;  // 1,000 SZN (18 decimals)
    uint256 public constant REFERRER_BPS   = 50;            // 0.5% in basis points
    uint256 public constant BPS_DENOM      = 10_000;

    // ── State ─────────────────────────────────────────────────────────────────
    address public owner;
    address public authorizedRouter;

    // Clause III: Immutable bond — write-once per user
    mapping(address => address)  public referrers;       // new user => referrer
    mapping(address => uint256)  public referralCount;   // referrer => # invites
    mapping(address => uint256)  public totalEarned;     // referrer => total CRO earned (wei)
    mapping(address => address[]) private _referees;     // referrer => list of referees

    // ── Events ────────────────────────────────────────────────────────────────
    event Registered(address indexed newUser, address indexed referrer, uint256 timestamp);
    event ReferralRewarded(address indexed referrer, address indexed trader, uint256 amount);
    event RouterAuthorized(address indexed router);

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "SZNRegistry: not owner");
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == authorizedRouter, "SZNRegistry: caller is not router");
        _;
    }

    // Clause I: Proof of Stake — must hold >= 1,000 SZN to be an Ambassador
    modifier onlyAmbassador(address account) {
        require(
            sznToken.balanceOf(account) >= MIN_AMBASSADOR,
            "SZNRegistry: insufficient SZN - 1,000 SZN required"
        );
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(address _sznToken) {
        require(_sznToken != address(0), "SZNRegistry: zero token address");
        sznToken = ISZN(_sznToken);
        owner    = msg.sender;
    }

    // ── Registration ──────────────────────────────────────────────────────────

    /**
     * Register a new user under a referrer.
     * Called when a new wallet connects via a referral link.
     * The referrer must hold >= 1,000 SZN (Clause I).
     * Bond is permanent once set (Clause III).
     */
    function register(address referrer)
        external
        onlyAmbassador(referrer)
    {
        require(referrers[msg.sender] == address(0), "SZNRegistry: already bonded");
        require(referrer != msg.sender,              "SZNRegistry: self-referral denied");
        require(referrer != address(0),              "SZNRegistry: zero referrer");

        // Clause III: Write-once — permanent on-chain bond
        referrers[msg.sender] = referrer;
        referralCount[referrer]++;
        _referees[referrer].push(msg.sender);

        emit Registered(msg.sender, referrer, block.timestamp);
    }

    // ── Reward distribution (called by SZNRouter) ─────────────────────────────

    /**
     * Route the referral tithe to the referrer.
     * Called by SZNRouter on every qualifying swap.
     * Clause II: 0.5% of volume, paid in CRO from the swap fee pool.
     */
    function distributeReferralReward(address trader)
        external
        payable
        onlyRouter
    {
        address referrer = referrers[trader];
        if (referrer == address(0)) return; // no referrer — skip silently

        uint256 reward = msg.value; // router sends exact 0.5% of fee
        if (reward == 0) return;

        totalEarned[referrer] += reward;

        (bool sent, ) = payable(referrer).call{value: reward}("");
        require(sent, "SZNRegistry: reward transfer failed");

        emit ReferralRewarded(referrer, trader, reward);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    function getReferrer(address user) external view returns (address) {
        return referrers[user];
    }

    function getReferees(address referrer) external view returns (address[] memory) {
        return _referees[referrer];
    }

    function isAmbassador(address account) external view returns (bool) {
        return sznToken.balanceOf(account) >= MIN_AMBASSADOR;
    }

    function ambassadorStats(address referrer)
        external
        view
        returns (uint256 count, uint256 earned, bool active)
    {
        count  = referralCount[referrer];
        earned = totalEarned[referrer];
        active = sznToken.balanceOf(referrer) >= MIN_AMBASSADOR;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function authorizeRouter(address router) external onlyOwner {
        require(router != address(0), "SZNRegistry: zero router address");
        authorizedRouter = router;
        emit RouterAuthorized(router);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SZNRegistry: zero address");
        owner = newOwner;
    }

    // Reject direct ETH sends (rewards come through distributeReferralReward only)
    receive() external payable { revert("SZNRegistry: use distributeReferralReward"); }
}
