// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNChefV2 — Sovereign Yield Reactor, hardened
 *
 * Same farm as SZNChef (stake LP, earn SZNX per block) plus three protections:
 *
 *  1. Harvest lockup  — a wallet can claim rewards at most once per `harvestInterval`.
 *     Rewards keep accruing in between; nothing is lost, only the claim frequency is limited.
 *  2. Timelock        — every owner change (rate, LP token, interval, ownership) is queued,
 *     is public for at least `MIN_DELAY` (24h), and only then can be executed. A queued
 *     change can be cancelled. Depositors can read the queue and leave before it lands.
 *  3. No migrator     — there is no function that can move staked LP or reward tokens anywhere
 *     except back to the staker. The owner cannot withdraw anyone's stake.
 *
 * Not included on purpose: no transfer fee, no burn, no rebasing. Those belong in the token
 * contract, and the live SZNX tokens cannot be changed after deployment.
 *
 * Not deployed. Deploying and funding is the owner's own signed transaction.
 */

interface IERC20 {
    function transfer(address to, uint256 amount)                      external returns (bool);
    function transferFrom(address from, address to, uint256 amount)    external returns (bool);
    function balanceOf(address account)                                external view returns (uint256);
}

contract SZNChefV2 {

    // ── Config ────────────────────────────────────────────────────────────────
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 30 days;
    uint256 public constant GRACE     = 7 days;      // a queued change expires if not executed in time
    uint256 public constant MAX_HARVEST_INTERVAL = 7 days;

    IERC20  public immutable sznx;
    IERC20  public lpToken;
    uint256 public sznxPerBlock;
    uint256 public harvestInterval;
    address public owner;

    // ── Pool ──────────────────────────────────────────────────────────────────
    uint256 public totalStaked;
    uint256 public accSznxPerShare;   // scaled 1e12
    uint256 public lastRewardBlock;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastHarvest;          // timestamp of the last paid claim
    }
    mapping(address => UserInfo) public userInfo;

    // ── Timelock queue ────────────────────────────────────────────────────────
    // kind: 1 rate, 2 lpToken, 3 harvestInterval, 4 owner
    struct Queued { uint8 kind; uint256 value; uint256 eta; }
    mapping(bytes32 => Queued) public queue;

    // ── Events ────────────────────────────────────────────────────────────────
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 reward);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event ChangeQueued(bytes32 indexed id, uint8 kind, uint256 value, uint256 eta);
    event ChangeExecuted(bytes32 indexed id, uint8 kind, uint256 value);
    event ChangeCancelled(bytes32 indexed id);

    uint256 private _lock = 1;
    modifier nonReentrant() {
        require(_lock == 1, "SZNChefV2: reentrant");
        _lock = 2;
        _;
        _lock = 1;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "SZNChefV2: not owner");
        _;
    }

    constructor(address _sznx, address _lpToken, uint256 _sznxPerBlock, uint256 _harvestInterval) {
        require(_harvestInterval <= MAX_HARVEST_INTERVAL, "SZNChefV2: interval too long");
        sznx            = IERC20(_sznx);
        lpToken         = IERC20(_lpToken);
        sznxPerBlock    = _sznxPerBlock;
        harvestInterval = _harvestInterval;
        lastRewardBlock = block.number;
        owner           = msg.sender;
    }

    // ── Reward accounting ─────────────────────────────────────────────────────

    function _update() internal {
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 blocks = block.number - lastRewardBlock;
        accSznxPerShare += (blocks * sznxPerBlock * 1e12) / totalStaked;
        lastRewardBlock = block.number;
    }

    function pendingReward(address user) public view returns (uint256) {
        UserInfo storage u = userInfo[user];
        uint256 acc = accSznxPerShare;
        if (block.number > lastRewardBlock && totalStaked > 0) {
            acc += ((block.number - lastRewardBlock) * sznxPerBlock * 1e12) / totalStaked;
        }
        return (u.amount * acc / 1e12) - u.rewardDebt;
    }

    /// Seconds until `user` may claim again (0 = now).
    function harvestIn(address user) public view returns (uint256) {
        uint256 next = userInfo[user].lastHarvest + harvestInterval;
        return block.timestamp >= next ? 0 : next - block.timestamp;
    }

    // ── Stake / unstake / claim ───────────────────────────────────────────────
    // While a wallet is inside its lockup window, deposit/withdraw do NOT pay rewards out:
    // they leave them accruing (rewardDebt is only advanced by what was actually paid).

    function _settle(UserInfo storage u) internal {
        uint256 pending = (u.amount * accSznxPerShare / 1e12) - u.rewardDebt;
        if (pending == 0) return;
        if (block.timestamp < u.lastHarvest + harvestInterval) return;   // locked: keep accruing
        u.lastHarvest = block.timestamp;
        u.rewardDebt += pending;
        require(sznx.transfer(msg.sender, pending), "SZNChefV2: reward transfer failed");
        emit Harvest(msg.sender, pending);
    }

    function deposit(uint256 amount) external nonReentrant {
        _update();
        UserInfo storage u = userInfo[msg.sender];
        _settle(u);
        if (amount > 0) {
            // Rewards still waiting inside the lockup stay with the old balance.
            uint256 owed = (u.amount * accSznxPerShare / 1e12) - u.rewardDebt;
            require(lpToken.transferFrom(msg.sender, address(this), amount), "SZNChefV2: LP transfer failed");
            u.amount += amount;
            totalStaked += amount;
            u.rewardDebt = (u.amount * accSznxPerShare / 1e12) - owed;
        }
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _update();
        UserInfo storage u = userInfo[msg.sender];
        require(u.amount >= amount, "SZNChefV2: insufficient stake");
        _settle(u);
        if (amount > 0) {
            // Still locked with rewards waiting? Refuse rather than silently forfeit them.
            require(u.amount * accSznxPerShare / 1e12 == u.rewardDebt, "SZNChefV2: harvest locked, wait or use emergencyWithdraw");
            u.amount -= amount;
            totalStaked -= amount;
            u.rewardDebt = u.amount * accSznxPerShare / 1e12;
            require(lpToken.transfer(msg.sender, amount), "SZNChefV2: LP transfer failed");
        }
        emit Withdraw(msg.sender, amount);
    }

    function harvest() external nonReentrant {
        _update();
        UserInfo storage u = userInfo[msg.sender];
        require(block.timestamp >= u.lastHarvest + harvestInterval, "SZNChefV2: harvest locked");
        uint256 pending = (u.amount * accSznxPerShare / 1e12) - u.rewardDebt;
        require(pending > 0, "SZNChefV2: nothing to harvest");
        u.lastHarvest = block.timestamp;
        u.rewardDebt += pending;
        require(sznx.transfer(msg.sender, pending), "SZNChefV2: reward transfer failed");
        emit Harvest(msg.sender, pending);
    }

    /// Leave with the stake and forfeit unclaimed rewards. Works even if the reactor is empty.
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage u = userInfo[msg.sender];
        uint256 amount = u.amount;
        require(amount > 0, "SZNChefV2: nothing staked");
        u.amount = 0;
        u.rewardDebt = 0;
        totalStaked -= amount;
        require(lpToken.transfer(msg.sender, amount), "SZNChefV2: LP transfer failed");
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // ── Timelocked admin ──────────────────────────────────────────────────────

    function queueChange(uint8 kind, uint256 value, uint256 delay) external onlyOwner returns (bytes32 id) {
        require(kind >= 1 && kind <= 4, "SZNChefV2: bad kind");
        require(delay >= MIN_DELAY && delay <= MAX_DELAY, "SZNChefV2: delay out of range");
        if (kind == 3) require(value <= MAX_HARVEST_INTERVAL, "SZNChefV2: interval too long");
        if (kind == 2 || kind == 4) require(value != 0 && value <= type(uint160).max, "SZNChefV2: bad address");
        id = keccak256(abi.encode(kind, value, block.timestamp));
        require(queue[id].eta == 0, "SZNChefV2: already queued");
        uint256 eta = block.timestamp + delay;
        queue[id] = Queued(kind, value, eta);
        emit ChangeQueued(id, kind, value, eta);
    }

    function cancelChange(bytes32 id) external onlyOwner {
        require(queue[id].eta != 0, "SZNChefV2: not queued");
        delete queue[id];
        emit ChangeCancelled(id);
    }

    function executeChange(bytes32 id) external onlyOwner {
        Queued memory q = queue[id];
        require(q.eta != 0, "SZNChefV2: not queued");
        require(block.timestamp >= q.eta, "SZNChefV2: timelock active");
        require(block.timestamp <= q.eta + GRACE, "SZNChefV2: expired");
        delete queue[id];
        if (q.kind == 1) {
            _update();
            sznxPerBlock = q.value;
        } else if (q.kind == 2) {
            require(totalStaked == 0, "SZNChefV2: pool not empty");
            lpToken = IERC20(address(uint160(q.value)));
        } else if (q.kind == 3) {
            harvestInterval = q.value;
        } else {
            owner = address(uint160(q.value));
        }
        emit ChangeExecuted(id, q.kind, q.value);
    }

    // ── Reactor funding ───────────────────────────────────────────────────────

    function fundReactor(uint256 amount) external {
        require(sznx.transferFrom(msg.sender, address(this), amount), "SZNChefV2: funding failed");
    }

    function reactorBalance() external view returns (uint256) {
        return sznx.balanceOf(address(this));
    }
}
