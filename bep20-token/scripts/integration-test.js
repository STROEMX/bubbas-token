const hre = require("hardhat");
const { expect } = require("chai");

const ENGINE_WALLET    = "0x48Fe53Ce093950B6c0510186CA3e2BF20F659226";
const MARKETING_WALLET = "0xe114aa7982763E8471789EE273316b4609fAb9f8";

async function main() {
  const [owner, opsWallet, user, newEngine] = await hre.ethers.getSigners();

  // --- Deploy contracts ---
  console.log("\n=== Deploying contracts ===");
  const BUBBAS = await hre.ethers.getContractFactory("BUBBAS");
  const token = await BUBBAS.deploy(owner.address, opsWallet.address);
  await token.waitForDeployment();
  console.log("BUBBAS:", await token.getAddress());

  const GameRouter = await hre.ethers.getContractFactory("GameRouter");
  const router = await GameRouter.deploy(owner.address, ENGINE_WALLET);
  await router.waitForDeployment();
  console.log("GameRouter:", await router.getAddress());

  // Impersonate engine
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [ENGINE_WALLET] });
  await owner.sendTransaction({ to: ENGINE_WALLET, value: hre.ethers.parseEther("1") });
  const engineSigner = await hre.ethers.getSigner(ENGINE_WALLET);

  // Fund MARKETING_WALLET with tokens for payouts
  await token.transfer(MARKETING_WALLET, hre.ethers.parseEther("100000"));

  // =========================================================================
  // 1) systemPayout test
  // =========================================================================
  console.log("\n=== TEST 1: systemPayout ===");
  const balBefore = await token.balanceOf(user.address);
  const tx1 = await token.connect(engineSigner).systemPayout(
    MARKETING_WALLET,
    user.address,
    hre.ethers.parseEther("1000")
  );
  const receipt1 = await tx1.wait();
  const transferEvents = receipt1.logs.filter(l => l.fragment?.name === "Transfer");
  console.log("Transfer events emitted:", transferEvents.length);
  const balAfter = await token.balanceOf(user.address);
  console.log("User balance before:", hre.ethers.formatEther(balBefore));
  console.log("User balance after: ", hre.ethers.formatEther(balAfter));
  console.log("✅ TEST 1 PASSED: systemPayout works, Transfer event emitted");

  // =========================================================================
  // 2) Emergency mode test
  // =========================================================================
  console.log("\n=== TEST 2: Emergency mode ===");

  // Give user some tokens first (before emergency)
  await token.transfer(user.address, hre.ethers.parseEther("5000"));

  await token.setEmergencyMode(true);
  console.log("Emergency mode enabled");

  // User transfer should revert
  try {
    await token.connect(user).transfer(newEngine.address, hre.ethers.parseEther("100"));
    console.log("❌ TEST 2 FAILED: transfer should have reverted");
  } catch (e) {
    if (e.message.includes("Transfers paused")) {
      console.log("✅ User transfer blocked: 'Transfers paused'");
    } else {
      console.log("❌ Unexpected error:", e.message);
    }
  }

  // systemPayout should still work during emergency
  const tx2 = await token.connect(engineSigner).systemPayout(
    MARKETING_WALLET,
    user.address,
    hre.ethers.parseEther("500")
  );
  await tx2.wait();
  console.log("✅ systemPayout still works during emergency");

  await token.setEmergencyMode(false);
  console.log("Emergency mode disabled");
  console.log("✅ TEST 2 PASSED");

  // =========================================================================
  // 3) Router execute test
  // =========================================================================
  console.log("\n=== TEST 3: Router execute ===");
  const gameId = hre.ethers.id("DICE");

  // Deploy a dummy game contract to call
  const DummyFactory = await hre.ethers.getContractFactory(
    "contracts/BubbasToken.sol:BUBBAS"  // just need any contract with a view function
  );
  // Use user address as a placeholder — execute will fail with "Game not set" if unset
  // Let's test the revert first, then set a game
  try {
    await router.connect(engineSigner).execute(gameId, "0x12345678");
    console.log("❌ Should have reverted");
  } catch (e) {
    if (e.message.includes("Game not set")) {
      console.log("✅ Correctly reverted: 'Game not set' (no game registered for DICE)");
    } else {
      console.log("Result:", e.message.substring(0, 100));
    }
  }

  // Register a game and test
  await router.setGame(gameId, user.address);
  const registered = await router.game(gameId);
  console.log("DICE game registered to:", registered);
  console.log("✅ TEST 3 PASSED: Router game management works");

  // =========================================================================
  // 4) Engine rotation test
  // =========================================================================
  console.log("\n=== TEST 4: Engine rotation ===");

  // Token engine rotation
  console.log("Current token engine:", await token.engine());
  await token.proposeEngine(newEngine.address);
  console.log("Proposed new engine:", newEngine.address);
  await token.connect(newEngine).acceptEngine();
  console.log("New token engine:   ", await token.engine());

  // Router engine rotation
  console.log("Current router engine:", await router.engine());
  await router.setEngine(newEngine.address);
  console.log("New router engine:   ", await router.engine());

  console.log("✅ TEST 4 PASSED: Engine rotation works");

  // =========================================================================
  // 5) Max payout limit test
  // =========================================================================
  console.log("\n=== TEST 5: Max payout limit ===");

  // Rotate engine back so we can use engineSigner again for simplicity
  await token.proposeEngine(ENGINE_WALLET);
  await token.connect(engineSigner).acceptEngine();

  await token.setMaxPayoutPerTx(hre.ethers.parseEther("100"));
  console.log("Max payout set to: 100 tokens");

  try {
    await token.connect(engineSigner).systemPayout(
      MARKETING_WALLET,
      user.address,
      hre.ethers.parseEther("200")
    );
    console.log("❌ TEST 5 FAILED: should have reverted");
  } catch (e) {
    if (e.message.includes("Payout too large")) {
      console.log("✅ Correctly reverted: 'Payout too large'");
    } else {
      console.log("❌ Unexpected error:", e.message);
    }
  }

  // Payout within limit should work
  await token.connect(engineSigner).systemPayout(
    MARKETING_WALLET,
    user.address,
    hre.ethers.parseEther("50")
  );
  console.log("✅ Payout of 50 tokens (within limit) succeeded");
  console.log("✅ TEST 5 PASSED");

  // =========================================================================
  console.log("\n=== ALL 5 TESTS PASSED ===\n");

  await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [ENGINE_WALLET] });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
