const { expect } = require("chai");
const hre = require("hardhat");

describe("BUBBAS Token", function () {
  const TOTAL_SUPPLY = 1_000_000_000n * 10n ** 18n;

  let token;
  let owner, opsWallet, user1, user2, engineSigner;

  // Hardcoded system wallet addresses from the contract
  const ENGINE_WALLET    = "0x48Fe53Ce093950B6c0510186CA3e2BF20F659226";
  const MARKETING_WALLET = "0xe114aa7982763E8471789EE273316b4609fAb9f8";
  const DEV_WALLET       = "0xE4d409A5850A914686240165398E0C051A53347F";
  const LOTTERY_WALLET   = "0x990DC6B4331f1158Acef1408BEe8a521Bde69Cae";
  const JACKPOT_WALLET   = "0x5E621aDBF14dDF216770535aa980d22a202FBcBE";
  const SINK_WALLET      = "0xF5F140fC4B10abe1a58598Ee3544e181107DA638";

  beforeEach(async function () {
    [owner, opsWallet, user1, user2] = await hre.ethers.getSigners();

    const BUBBAS = await hre.ethers.getContractFactory("BUBBAS");
    token = await BUBBAS.deploy(owner.address, opsWallet.address);
    await token.waitForDeployment();

    // Impersonate the engine wallet for engine-only calls
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ENGINE_WALLET],
    });
    // Fund the engine wallet so it can send transactions
    await owner.sendTransaction({
      to: ENGINE_WALLET,
      value: hre.ethers.parseEther("1"),
    });
    engineSigner = await hre.ethers.getSigner(ENGINE_WALLET);
  });

  afterEach(async function () {
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [ENGINE_WALLET],
    });
  });

  // -----------------------------------------------------------------------
  // DEPLOYMENT
  // -----------------------------------------------------------------------
  describe("Deployment", function () {
    it("should set name and symbol to BUBBAS", async function () {
      expect(await token.name()).to.equal("BUBBAS");
      expect(await token.symbol()).to.equal("BUBBAS");
    });

    it("should assign total supply to the deployer", async function () {
      expect(await token.balanceOf(owner.address)).to.equal(TOTAL_SUPPLY);
    });

    it("should report correct totalSupply", async function () {
      expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("should set the engine to ENGINE_WALLET", async function () {
      expect(await token.engine()).to.equal(ENGINE_WALLET);
    });

    it("should set the opsWallet", async function () {
      expect(await token.opsWallet()).to.equal(opsWallet.address);
    });

    it("should mark system wallets correctly", async function () {
      expect(await token.isSystemWallet(ENGINE_WALLET)).to.be.true;
      expect(await token.isSystemWallet(MARKETING_WALLET)).to.be.true;
      expect(await token.isSystemWallet(SINK_WALLET)).to.be.true;
    });

    it("should exclude system wallets from fees", async function () {
      expect(await token.isExcludedFromFee(ENGINE_WALLET)).to.be.true;
      expect(await token.isExcludedFromFee(opsWallet.address)).to.be.true;
    });
  });

  // -----------------------------------------------------------------------
  // TRANSFERS (FEE-FREE: OWNER IS EXCLUDED)
  // -----------------------------------------------------------------------
  describe("Transfers (excluded from fee)", function () {
    it("should transfer full amount between excluded wallets", async function () {
      const amount = hre.ethers.parseEther("1000");
      await token.transfer(opsWallet.address, amount);
      expect(await token.balanceOf(opsWallet.address)).to.equal(amount);
    });
  });

  // -----------------------------------------------------------------------
  // TRANSFERS (WITH TAX)
  // -----------------------------------------------------------------------
  describe("Transfers (with tax)", function () {
    it("should deduct tax on transfer between non-excluded users", async function () {
      const seedAmount = hre.ethers.parseEther("10000");
      // Owner → user1 (fee-free, owner excluded)
      await token.transfer(user1.address, seedAmount);

      const transferAmount = hre.ethers.parseEther("5000");
      // user1 → user2 (both non-excluded → tax applies)
      await token.connect(user1).transfer(user2.address, transferAmount);

      // user2 should receive less than transferAmount due to tax
      const user2Balance = await token.balanceOf(user2.address);
      expect(user2Balance).to.be.lt(transferAmount);
      expect(user2Balance).to.be.gt(0n);
    });

    it("should emit TaxApplied event", async function () {
      const seedAmount = hre.ethers.parseEther("10000");
      await token.transfer(user1.address, seedAmount);

      const transferAmount = hre.ethers.parseEther("5000");
      await expect(
        token.connect(user1).transfer(user2.address, transferAmount)
      ).to.emit(token, "TaxApplied");
    });

    it("should distribute tax to system wallets", async function () {
      const seedAmount = hre.ethers.parseEther("100000");
      await token.transfer(user1.address, seedAmount);

      const sinkBefore = await token.balanceOf(SINK_WALLET);

      const transferAmount = hre.ethers.parseEther("50000");
      await token.connect(user1).transfer(user2.address, transferAmount);

      const sinkAfter = await token.balanceOf(SINK_WALLET);
      expect(sinkAfter).to.be.gt(sinkBefore);
    });
  });

  // -----------------------------------------------------------------------
  // BURN DISABLED
  // -----------------------------------------------------------------------
  describe("Burns", function () {
    it("should revert transfers to address(0)", async function () {
      const amount = hre.ethers.parseEther("100");
      await expect(
        token.transfer(hre.ethers.ZeroAddress, amount)
      ).to.be.reverted;
    });
  });

  // -----------------------------------------------------------------------
  // SINK LOCK
  // -----------------------------------------------------------------------
  describe("Sink lock", function () {
    it("should block transfers from the sink wallet", async function () {
      // Fund the sink first
      await token.transfer(SINK_WALLET, hre.ethers.parseEther("1000"));

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [SINK_WALLET],
      });
      await owner.sendTransaction({ to: SINK_WALLET, value: hre.ethers.parseEther("1") });
      const sinkSigner = await hre.ethers.getSigner(SINK_WALLET);

      await expect(
        token.connect(sinkSigner).transfer(user1.address, hre.ethers.parseEther("1"))
      ).to.be.revertedWith("Sink locked");

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [SINK_WALLET],
      });
    });
  });

  // -----------------------------------------------------------------------
  // ENGINE PAYOUT
  // -----------------------------------------------------------------------
  describe("Engine systemPayout", function () {
    beforeEach(async function () {
      // Fund the ENGINE_WALLET with tokens so it can pay out
      await token.transfer(ENGINE_WALLET, hre.ethers.parseEther("100000"));
    });

    it("should transfer tokens from system wallet to user", async function () {
      const amount = hre.ethers.parseEther("500");
      const balBefore = await token.balanceOf(user1.address);

      await token.connect(engineSigner).systemPayout(ENGINE_WALLET, user1.address, amount);

      const balAfter = await token.balanceOf(user1.address);
      expect(balAfter - balBefore).to.equal(amount);
    });

    it("should revert when called by non-engine", async function () {
      await expect(
        token.connect(user1).systemPayout(ENGINE_WALLET, user2.address, hre.ethers.parseEther("1"))
      ).to.be.revertedWith("Not engine");
    });

    it("should revert if payout exceeds maxPayoutPerTx", async function () {
      const tooMuch = hre.ethers.parseEther("1000001");
      await expect(
        token.connect(engineSigner).systemPayout(ENGINE_WALLET, user1.address, tooMuch)
      ).to.be.revertedWith("Payout too large");
    });

    it("should revert system-to-system payout", async function () {
      await expect(
        token.connect(engineSigner).systemPayout(ENGINE_WALLET, MARKETING_WALLET, hre.ethers.parseEther("1"))
      ).to.be.revertedWith("No system-to-system");
    });
  });

  // -----------------------------------------------------------------------
  // ENGINE PAUSE
  // -----------------------------------------------------------------------
  describe("Engine pause", function () {
    beforeEach(async function () {
      await token.transfer(ENGINE_WALLET, hre.ethers.parseEther("10000"));
    });

    it("should block systemPayout when engine is paused", async function () {
      await token.setEnginePaused(true);
      await expect(
        token.connect(engineSigner).systemPayout(ENGINE_WALLET, user1.address, hre.ethers.parseEther("1"))
      ).to.be.revertedWith("Engine paused");
    });

    it("should resume after unpausing", async function () {
      await token.setEnginePaused(true);
      await token.setEnginePaused(false);
      await expect(
        token.connect(engineSigner).systemPayout(ENGINE_WALLET, user1.address, hre.ethers.parseEther("1"))
      ).to.not.be.reverted;
    });
  });

  // -----------------------------------------------------------------------
  // ENGINE ROTATION (2-STEP)
  // -----------------------------------------------------------------------
  describe("Engine rotation", function () {
    it("should rotate engine via propose → accept", async function () {
      await token.proposeEngine(user1.address);
      expect(await token.pendingEngine()).to.equal(user1.address);

      await token.connect(user1).acceptEngine();
      expect(await token.engine()).to.equal(user1.address);
      expect(await token.pendingEngine()).to.equal(hre.ethers.ZeroAddress);
    });

    it("should revert acceptEngine from non-pending address", async function () {
      await token.proposeEngine(user1.address);
      await expect(
        token.connect(user2).acceptEngine()
      ).to.be.revertedWith("Not pending engine");
    });
  });

  // -----------------------------------------------------------------------
  // EMERGENCY MODE
  // -----------------------------------------------------------------------
  describe("Emergency mode", function () {
    it("should block non-system transfers when enabled", async function () {
      await token.transfer(user1.address, hre.ethers.parseEther("1000"));
      await token.setEmergencyMode(true);

      await expect(
        token.connect(user1).transfer(user2.address, hre.ethers.parseEther("1"))
      ).to.be.revertedWith("Transfers paused");
    });
  });

  // -----------------------------------------------------------------------
  // FEES TOGGLE
  // -----------------------------------------------------------------------
  describe("Fee toggle", function () {
    it("should skip tax when fees are disabled", async function () {
      await token.setFeesEnabled(false);

      await token.transfer(user1.address, hre.ethers.parseEther("10000"));
      const transferAmount = hre.ethers.parseEther("5000");

      await token.connect(user1).transfer(user2.address, transferAmount);
      // Without fees, user2 gets the full amount
      expect(await token.balanceOf(user2.address)).to.equal(transferAmount);
    });
  });

  // -----------------------------------------------------------------------
  // LP MANAGEMENT
  // -----------------------------------------------------------------------
  describe("LP management", function () {
    it("should set and unset LP addresses", async function () {
      await token.setLP(user1.address);
      expect(await token.isLP(user1.address)).to.be.true;
      expect(await token.isExcludedFromFee(user1.address)).to.be.true;

      await token.unsetLP(user1.address);
      expect(await token.isLP(user1.address)).to.be.false;
    });
  });

  // -----------------------------------------------------------------------
  // OWNER-ONLY ACCESS CONTROL
  // -----------------------------------------------------------------------
  describe("Access control", function () {
    it("should revert non-owner calls to admin functions", async function () {
      await expect(
        token.connect(user1).setEnginePaused(true)
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");

      await expect(
        token.connect(user1).setFeesEnabled(false)
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");

      await expect(
        token.connect(user1).proposeEngine(user2.address)
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");
    });
  });
});

// =========================================================================
// GAME ROUTER
// =========================================================================
describe("GameRouter", function () {
  let router;
  let owner, user1, engineSigner;
  const ENGINE_WALLET = "0x48Fe53Ce093950B6c0510186CA3e2BF20F659226";

  beforeEach(async function () {
    [owner, user1] = await hre.ethers.getSigners();

    const GameRouter = await hre.ethers.getContractFactory("GameRouter");
    router = await GameRouter.deploy(owner.address, ENGINE_WALLET);
    await router.waitForDeployment();

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ENGINE_WALLET],
    });
    await owner.sendTransaction({ to: ENGINE_WALLET, value: hre.ethers.parseEther("1") });
    engineSigner = await hre.ethers.getSigner(ENGINE_WALLET);
  });

  afterEach(async function () {
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [ENGINE_WALLET],
    });
  });

  describe("Game management", function () {
    it("should set and remove a game", async function () {
      const gameId = hre.ethers.id("COINFLIP");
      await router.setGame(gameId, user1.address);
      expect(await router.game(gameId)).to.equal(user1.address);

      await router.removeGame(gameId);
      expect(await router.game(gameId)).to.equal(hre.ethers.ZeroAddress);
    });

    it("should revert setGame from non-owner", async function () {
      const gameId = hre.ethers.id("COINFLIP");
      await expect(
        router.connect(user1).setGame(gameId, user1.address)
      ).to.be.revertedWithCustomError(router, "OwnableUnauthorizedAccount");
    });
  });

  describe("Engine management", function () {
    it("should update engine directly", async function () {
      await router.setEngine(user1.address);
      expect(await router.engine()).to.equal(user1.address);
    });

    it("should rotate engine via propose → accept", async function () {
      await router.proposeEngine(user1.address);
      await router.connect(user1).acceptEngine();
      expect(await router.engine()).to.equal(user1.address);
    });
  });

  describe("Execute", function () {
    it("should revert execute from non-engine", async function () {
      const gameId = hre.ethers.id("COINFLIP");
      await expect(
        router.connect(user1).execute(gameId, "0x")
      ).to.be.revertedWith("Not engine");
    });

    it("should revert execute for unset game", async function () {
      const gameId = hre.ethers.id("COINFLIP");
      await expect(
        router.connect(engineSigner).execute(gameId, "0x1234")
      ).to.be.revertedWith("Game not set");
    });
  });
});

// =========================================================================
// PAYOUT MANAGER
// =========================================================================
describe("PayoutManager", function () {
  let token, payoutManager;
  let owner, opsWallet, user1, engineSigner;
  const ENGINE_WALLET    = "0x48Fe53Ce093950B6c0510186CA3e2BF20F659226";
  const LOTTERY_WALLET   = "0x990DC6B4331f1158Acef1408BEe8a521Bde69Cae";

  beforeEach(async function () {
    [owner, opsWallet, user1] = await hre.ethers.getSigners();

    // Deploy token
    const BUBBAS = await hre.ethers.getContractFactory("BUBBAS");
    token = await BUBBAS.deploy(owner.address, opsWallet.address);
    await token.waitForDeployment();
    const tokenAddr = await token.getAddress();

    // Deploy PayoutManager
    const PayoutManager = await hre.ethers.getContractFactory("PayoutManager");
    payoutManager = await PayoutManager.deploy(owner.address, ENGINE_WALLET, tokenAddr);
    await payoutManager.waitForDeployment();

    // Impersonate engine
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ENGINE_WALLET],
    });
    await owner.sendTransaction({ to: ENGINE_WALLET, value: hre.ethers.parseEther("1") });
    engineSigner = await hre.ethers.getSigner(ENGINE_WALLET);

    // Fund the lottery wallet with tokens
    await token.transfer(LOTTERY_WALLET, hre.ethers.parseEther("100000"));
  });

  afterEach(async function () {
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [ENGINE_WALLET],
    });
  });

  describe("Deployment", function () {
    it("should set correct engine and token", async function () {
      expect(await payoutManager.engine()).to.equal(ENGINE_WALLET);
      expect(await payoutManager.token()).to.equal(await token.getAddress());
    });
  });

  describe("Pool configuration", function () {
    it("should allow engine to configure a pool", async function () {
      // Set pool wallet
      await payoutManager.connect(engineSigner).setPoolWallet(0, LOTTERY_WALLET); // 0 = LOTTERY

      // Configure pool
      await payoutManager.connect(engineSigner).setPoolConfig(
        0,                              // PoolType.LOTTERY
        hre.ethers.parseEther("10000"), // payoutLimitPerBlock
        hre.ethers.parseEther("50000"), // payoutLimitPerMinute
        0,                              // cooldownSeconds
        5000,                           // maxValuePerMinuteBps (50%)
        1000,                           // maxSinglePayoutBps (10%)
        100,                            // minReserveBps (1%)
        false                           // drainsOnPayout
      );

      const cfg = await payoutManager.poolConfig(0);
      expect(cfg.initialized).to.be.true;
      expect(cfg.wallet).to.equal(LOTTERY_WALLET);
    });

    it("should revert pool config from non-engine", async function () {
      await expect(
        payoutManager.connect(user1).setPoolWallet(0, LOTTERY_WALLET)
      ).to.be.revertedWith("Not engine");
    });
  });

  describe("Global pause", function () {
    it("should allow owner to pause globally", async function () {
      await payoutManager.setGlobalPaused(true);
      expect(await payoutManager.globalPaused()).to.be.true;
    });
  });

  describe("Engine rotation", function () {
    it("should rotate engine via propose → accept", async function () {
      await payoutManager.proposeEngine(user1.address);
      await payoutManager.connect(user1).acceptEngine();
      expect(await payoutManager.engine()).to.equal(user1.address);
    });
  });
});
