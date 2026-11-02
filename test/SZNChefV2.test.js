import hre from "hardhat";
import { expect } from "chai";
const { ethers } = hre;
const DAY = 86400;
const bump = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("hardhat_mine", ["0x1"]); };

describe("SZNChefV2", () => {
  let owner, a, b, sznx, lp, chef;
  beforeEach(async () => {
    [owner, a, b] = await ethers.getSigners();
    const M = await ethers.getContractFactory("MockERC20");
    sznx = await M.deploy(); lp = await M.deploy();
    const C = await ethers.getContractFactory("SZNChefV2");
    chef = await C.deploy(await sznx.getAddress(), await lp.getAddress(), 10n ** 18n, DAY);
    await sznx.mint(owner.address, 10n ** 24n);
    await sznx.approve(await chef.getAddress(), 10n ** 24n);
    await chef.fundReactor(10n ** 24n);
    for (const u of [a, b]) { await lp.mint(u.address, 1000n); await lp.connect(u).approve(await chef.getAddress(), 1000n); }
  });

  it("pays rewards, then locks the next claim for the interval, with rewards still accruing", async () => {
    await chef.connect(a).deposit(1000n);
    await bump(60);
    await chef.connect(a).harvest();
    const first = await sznx.balanceOf(a.address);
    expect(first).to.be.gt(0n);
    await expect(chef.connect(a).harvest()).to.be.revertedWith("SZNChefV2: harvest locked");
    expect(await chef.pendingReward(a.address)).to.be.gt(0n);       // still accruing
    await bump(DAY);
    await chef.connect(a).harvest();
    expect(await sznx.balanceOf(a.address)).to.be.gt(first);
  });

  it("deposit inside the lockup does not pay or lose pending rewards", async () => {
    await chef.connect(a).deposit(500n);
    await bump(60);
    await chef.connect(a).harvest();
    await bump(100);
    const before = await chef.pendingReward(a.address);
    await chef.connect(a).deposit(500n);
    expect(await chef.pendingReward(a.address)).to.be.gte(before);
  });

  it("withdraw while locked with rewards pending is refused, emergencyWithdraw returns the stake", async () => {
    await chef.connect(a).deposit(1000n);
    await bump(60);
    await chef.connect(a).harvest();
    await bump(60);
    await expect(chef.connect(a).withdraw(1000n)).to.be.revertedWith("SZNChefV2: harvest locked, wait or use emergencyWithdraw");
    await chef.connect(a).emergencyWithdraw();
    expect(await lp.balanceOf(a.address)).to.equal(1000n);
  });

  it("withdraw after the lockup pays and returns the stake", async () => {
    await chef.connect(a).deposit(1000n);
    await bump(DAY + 10);
    await chef.connect(a).withdraw(1000n);
    expect(await lp.balanceOf(a.address)).to.equal(1000n);
    expect(await sznx.balanceOf(a.address)).to.be.gt(0n);
  });

  it("owner changes need the timelock; cannot execute early; cancel works; non-owner refused", async () => {
    await expect(chef.connect(a).queueChange(1, 5n, DAY)).to.be.revertedWith("SZNChefV2: not owner");
    await expect(chef.queueChange(1, 5n, 3600)).to.be.revertedWith("SZNChefV2: delay out of range");
    const tx = await chef.queueChange(1, 5n, DAY);
    const id = (await tx.wait()).logs.find((l) => l.fragment?.name === "ChangeQueued").args[0];
    await expect(chef.executeChange(id)).to.be.revertedWith("SZNChefV2: timelock active");
    await bump(DAY + 1);
    await chef.executeChange(id);
    expect(await chef.sznxPerBlock()).to.equal(5n);
    const t2 = await chef.queueChange(1, 7n, DAY);
    const id2 = (await t2.wait()).logs.find((l) => l.fragment?.name === "ChangeQueued").args[0];
    await chef.cancelChange(id2);
    await bump(DAY + 1);
    await expect(chef.executeChange(id2)).to.be.revertedWith("SZNChefV2: not queued");
  });

  it("a queued change expires after the grace window", async () => {
    const tx = await chef.queueChange(3, 3600n, DAY);
    const id = (await tx.wait()).logs.find((l) => l.fragment?.name === "ChangeQueued").args[0];
    await bump(DAY + 8 * DAY);
    await expect(chef.executeChange(id)).to.be.revertedWith("SZNChefV2: expired");
  });

  it("there is no way for the owner to take staked LP", async () => {
    await chef.connect(a).deposit(1000n);
    const names = chef.interface.fragments.filter((f) => f.type === "function").map((f) => f.name);
    for (const bad of ["migrate", "setMigrator", "sweep", "rescue", "withdrawAll", "recoverToken"]) expect(names).to.not.include(bad);
    expect(await lp.balanceOf(await chef.getAddress())).to.equal(1000n);
  });
});
