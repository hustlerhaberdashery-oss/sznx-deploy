// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * SZNChef — Sovereign Yield Reactor
 * MasterChef-style farm. Accepts VVS LP tokens, distributes SZNX rewards per block.
 *
 * Rate: sznxPerBlock — set at deployment, adjustable by owner.
 * APY is determined by: (sznxPerBlock * blocks_per_year * price) / (totalStaked * price)
 * At low TVL + high rate = degenerate APY. This is by design.
 */

interface IERC20 {
    function transfer(address to, uint256 amount)                      external returns (bool);
    function transferFrom(address from, address to, uint256 amount)    external returns (bool);
    function balanceOf(address account)                                external view returns (uint256);
}

contract SZNChef {

    // ── Config ────────────────────────────────────────────────────────────────
    IERC20  public immutable sznx;
    uint256 public sznxPerBlock;
    address public owner;

    // ── Pool ──────────────────────────────────────────────────────────────────
    IERC20  public lpToken;           // VVS SZNX-WCRO LP
    uint256 public totalStaked;
    uint256 public accSznxPerShare;   // accumulated rewards per share (scaled 1e12)
    uint256 public lastRewardBlock;

    // ── User ──────────────────────────────────────────────────────────────────
    struct UserInfo {
        uint256 amount;       // LP staked
        uint256 rewardDebt;   // accounting offset
    }
    mapping(address => UserInfo) public userInfo;

    // ── Events ────────────────────────────────────────────────────────────────
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 reward);
    event RateSet(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "SZNChef: not owner");
        _;
    }

    constructor(address _sznx, address _lpToken, uint256 _sznxPerBlock) {
        sznx         = IERC20(_sznx);
        lpToken      = IERC20(_lpToken);
        sznxPerBlock = _sznxPerBlock;
        lastRewardBlock = block.number;
        owner = msg.sender;
    }

    // ── Reward accounting ─────────────────────────────────────────────────────

    function _update() internal {
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * sznxPerBlock;
        accSznxPerShare += (reward * 1e12) / totalStaked;
        lastRewardBlock = block.number;
    }

    function pendingReward(address user) external view returns (uint256) {
        UserInfo storage u = userInfo[user];
        uint256 acc = accSznxPerShare;
        if (block.number > lastRewardBlock && totalStaked > 0) {
            uint256 blocks = block.number - lastRewardBlock;
            acc += (blocks * sznxPerBlock * 1e12) / totalStaked;
        }
        return (u.amount * acc / 1e12) - u.rewardDebt;
    }

    // ── Stake / Unstake ───────────────────────────────────────────────────────

    function deposit(uint256 amount) external {
        _update();
        UserInfo storage u = userInfo[msg.sender];

        if (u.amount > 0) {
            uint256 pending = (u.amount * accSznxPerShare / 1e12) - u.rewardDebt;
            if (pending > 0) {
                sznx.transfer(msg.sender, pending);
                emit Harvest(msg.sender, pending);
            }
        }

        if (amount > 0) {
            lpToken.transferFrom(msg.sender, address(this), amount);
            u.amount += amount;
            totalStaked += amount;
        }

        u.rewardDebt = u.amount * accSznxPerShare / 1e12;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        _update();
        UserInfo storage u = userInfo[msg.sender];
        require(u.amount >= amount, "SZNChef: insufficient stake");

        uint256 pending = (u.amount * accSznxPerShare / 1e12) - u.rewardDebt;
        if (pending > 0) {
            sznx.transfer(msg.sender, pending);
            emit Harvest(msg.sender, pending);
        }

        if (amount > 0) {
            u.amount -= amount;
            totalStaked -= amount;
            lpToken.transfer(msg.sender, amount);
        }

        u.rewardDebt = u.amount * accSznxPerShare / 1e12;
        emit Withdraw(msg.sender, amount);
    }

    function harvest() external {
        _update();
        UserInfo storage u = userInfo[msg.sender];
        uint256 pending = (u.amount * accSznxPerShare / 1e12) - u.rewardDebt;
        if (pending > 0) {
            sznx.transfer(msg.sender, pending);
            emit Harvest(msg.sender, pending);
        }
        u.rewardDebt = u.amount * accSznxPerShare / 1e12;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function setRate(uint256 newRate) external onlyOwner {
        _update();
        sznxPerBlock = newRate;
        emit RateSet(newRate);
    }

    function setLpToken(address _lp) external onlyOwner {
        require(totalStaked == 0, "SZNChef: pool not empty");
        lpToken = IERC20(_lp);
    }

    function fundReactor(uint256 amount) external {
        sznx.transferFrom(msg.sender, address(this), amount);
    }

    function reactorBalance() external view returns (uint256) {
        return sznx.balanceOf(address(this));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
