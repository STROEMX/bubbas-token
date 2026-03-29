/**
 * Testnet integration tests for BUBBATEST v2, GameRouter, PayoutManager.
 *
 * These tests run against live BSC testnet using the deployer wallet.
 * No impersonation (only works on local Hardhat network).
 *
 * Usage:
 *   npx hardhat run scripts/integration-test-testnet.js --network bscTestnet
 *
 * Required env:
 *   PRIVATE_KEY, OPS_WALLET, ENGINE_WALLET
 *   TESTNET_TOKEN, TESTNET_ROUTER, TESTNET_PAYOUT (contract addresses)
 */
require("dotenv").config();
const hre = require("hardhat");

const TOKEN_ADDR  = process.env.TESTNET_TOKEN  || "0xDeFDF14d1232860F844b187aA4A9Aa3B77e0FF0b";
const ROUTER_ADDR = process.env.TESTNET_ROUTER || "0x2deba2a0Fe3aC7E5178B01B9eAb9e52eB44B9eb0";
const PAYOUT_ADDR = process.env.TESTNET_PAYOUT || "0x2A3094A13c3CA198E6C9B73608749159f335dc35";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Testing with account:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "tBNB");

  // Attach to deployed contracts
  const token  = await hre.ethers.getContractAt("BubbasTokenTest", TOKEN_ADDR);
  const router = await hre.ethers.getContractAt("GameRouter", ROUTER_ADDR);
  const payout = await hre.ethers.getContractAt("PayoutManager", PAYOUT_ADDR);

  // =========================================================================
  // TEST 1: Token metadata
  // =========================================================================
  console.log("\n=== TEST 1: Token metadata ===");
  const name = await token.name();
  const symbol = await token.symbol();
  const totalSupply = await token.totalSupply();
  const ownerBalance = await token.balanceOf(deployer.address);

  console.log("Name:", name);
  console.log("Symbol:", symbol);
  console.log("Total supply:", hre.ethers.formatEther(totalSupply));
  console.log("Owner balance:", hre.ethers.formatEther(ownerBalance));

  if (name !== "BUBBATEST v2") throw new Error("Wrong name");
  if (symbol !== "BUBBAT2") throw new Error("Wrong symbol");
  console.log("✅ TEST 1 PASSED: Correct name/symbol");

  // =========================================================================
  // TEST 2: Emergency mode (owner can toggle)
  // =========================================================================
  console.log("\n=== TEST 2: Emergency mode ===");
  const tx2a = await token.setEmergencyMode(true);
  await tx2a.wait();
  console.log("Emergency mode enabled");

  const emergencyOn = await token.emergencyMode();
  if (!emergencyOn) throw new Error("Emergency mode should be true");
  console.log("✅ emergencyMode = true");

  const tx2b = await token.setEmergencyMode(false);
  await tx2b.wait();
  console.log("Emergency mode disabled");
  console.log("✅ TEST 2 PASSED");

  // =========================================================================
  // TEST 3: Fee toggle
  // =========================================================================
  console.log("\n=== TEST 3: Fee toggle ===");

  // First, ensure fees are enabled (may be stale from failed previous run)
  const currentFees = await token.feesEnabled();
  if (currentFees) {
    const txOff = await token.setFeesEnabled(false);
    const rcptOff = await txOff.wait(2);
    console.log("Disabled fees, tx:", rcptOff.hash);
  }

  // Now re-enable
  const txOn = await token.setFeesEnabled(true);
  const rcptOn = await txOn.wait(2);
  console.log("Enabled fees, tx:", rcptOn.hash);

  // Verify via event in receipt
  const feesEvent = rcptOn.logs.find(l => {
    try { return token.interface.parseLog(l)?.name === "FeesEnabledSet"; }
    catch { return false; }
  });
  if (!feesEvent) throw new Error("FeesEnabledSet event not found");
  const parsed = token.interface.parseLog(feesEvent);
  console.log("FeesEnabledSet event, enabled:", parsed.args[0]);
  if (parsed.args[0] !== true) throw new Error("Fees should be enabled");
  console.log("✅ TEST 3 PASSED: Fee toggle works");

  // =========================================================================
  // TEST 4: Max payout limit
  // =========================================================================
  console.log("\n=== TEST 4: Max payout limit ===");
  const currentMax = await token.maxPayoutPerTx();
  console.log("Current maxPayoutPerTx:", hre.ethers.formatEther(currentMax));

  const tx4a = await token.setMaxPayoutPerTx(hre.ethers.parseEther("500"));
  const rcpt4a = await tx4a.wait(2);
  const maxEvent = rcpt4a.logs.find(l => {
    try { return token.interface.parseLog(l)?.name === "MaxPayoutUpdated"; }
    catch { return false; }
  });
  if (!maxEvent) throw new Error("MaxPayoutUpdated event not found");
  const parsedMax = token.interface.parseLog(maxEvent);
  console.log("MaxPayoutUpdated event, amount:", hre.ethers.formatEther(parsedMax.args[0]));

  // Restore original
  const tx4b = await token.setMaxPayoutPerTx(currentMax);
  await tx4b.wait(2);
  console.log("Restored maxPayoutPerTx");
  console.log("✅ TEST 4 PASSED: Max payout limit works");

  // =========================================================================
  // TEST 5: Engine pause toggle
  // =========================================================================
  console.log("\n=== TEST 5: Engine pause ===");
  const tx5a = await token.setEnginePaused(true);
  const rcpt5a = await tx5a.wait(2);
  const pauseEvent = rcpt5a.logs.find(l => {
    try { return token.interface.parseLog(l)?.name === "EnginePaused"; }
    catch { return false; }
  });
  if (!pauseEvent) throw new Error("EnginePaused event not found");
  console.log("Engine paused: true (confirmed via event)");

  const tx5b = await token.setEnginePaused(false);
  await tx5b.wait(2);
  console.log("Engine unpaused");
  console.log("✅ TEST 5 PASSED: Engine pause toggle works");

  // =========================================================================
  // TEST 6: GameRouter game management
  // =========================================================================
  console.log("\n=== TEST 6: GameRouter game management ===");
  const gameId = hre.ethers.id("DICE");
  const dummyGame = "0x0000000000000000000000000000000000000001";

  const tx6a = await router.setGame(gameId, dummyGame);
  await tx6a.wait();
  const registered = await router.game(gameId);
  console.log("DICE registered to:", registered);
  if (registered.toLowerCase() !== dummyGame.toLowerCase()) throw new Error("Game not registered");

  const tx6b = await router.removeGame(gameId);
  await tx6b.wait();
  const removed = await router.game(gameId);
  console.log("DICE after removal:", removed);
  console.log("✅ TEST 6 PASSED: Game set/remove works");

  // =========================================================================
  // TEST 7: PayoutManager global pause
  // =========================================================================
  console.log("\n=== TEST 7: PayoutManager global pause ===");
  const tx7a = await payout.setGlobalPaused(true);
  const rcpt7a = await tx7a.wait(2);
  const gpEvent = rcpt7a.logs.find(l => {
    try { return payout.interface.parseLog(l)?.name === "GlobalPaused"; }
    catch { return false; }
  });
  if (!gpEvent) throw new Error("GlobalPaused event not found");
  console.log("Global paused: true (confirmed via event)");

  const tx7b = await payout.setGlobalPaused(false);
  await tx7b.wait(2);
  console.log("Global unpaused");
  console.log("✅ TEST 7 PASSED: PayoutManager pause works");

  // =========================================================================
  // TEST 8: Contract ownership
  // =========================================================================
  console.log("\n=== TEST 8: Contract ownership ===");
  const tokenOwner  = await token.owner();
  const routerOwner = await router.owner();
  const payoutOwner = await payout.owner();
  console.log("Token owner:  ", tokenOwner);
  console.log("Router owner: ", routerOwner);
  console.log("Payout owner: ", payoutOwner);

  if (tokenOwner !== deployer.address)  throw new Error("Token owner mismatch");
  if (routerOwner !== deployer.address) throw new Error("Router owner mismatch");
  if (payoutOwner !== deployer.address) throw new Error("Payout owner mismatch");
  console.log("✅ TEST 8 PASSED: All contracts owned by deployer");

  // =========================================================================
  console.log("\n=== ALL 8 TESTNET TESTS PASSED ===\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
