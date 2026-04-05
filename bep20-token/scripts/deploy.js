const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "BNB");

  // --- Ops wallet must be a DIFFERENT address from the deployer ---
  const signers = await hre.ethers.getSigners();
  let opsWallet;
  if (process.env.OPS_WALLET) {
    opsWallet = process.env.OPS_WALLET;
  } else if (signers.length > 1) {
    opsWallet = signers[1].address;
  } else {
    throw new Error("OPS_WALLET env var is required (must differ from deployer)");
  }
  console.log("OPS wallet:", opsWallet);

  // --- 1. Deploy BUBBAS Token ---
  const BUBBAS = await hre.ethers.getContractFactory("BUBBAS");
  const token = await BUBBAS.deploy(deployer.address, opsWallet);
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();
  console.log("BUBBAS deployed to:", tokenAddr);

  // --- 2. Deploy GameRouter ---
  const engineWallet = await token.ENGINE_WALLET();
  const GameRouter = await hre.ethers.getContractFactory("GameRouter");
  const router = await GameRouter.deploy(deployer.address, engineWallet);
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log("GameRouter deployed to:", routerAddr);

  // --- 3. Deploy PayoutManager ---
  const PayoutManager = await hre.ethers.getContractFactory("PayoutManager");
  const payout = await PayoutManager.deploy(deployer.address, engineWallet, tokenAddr);
  await payout.waitForDeployment();
  const payoutAddr = await payout.getAddress();
  console.log("PayoutManager deployed to:", payoutAddr);

  console.log("\n--- Deployment Summary ---");
  console.log("Owner:          ", deployer.address);
  console.log("OPS wallet:     ", opsWallet);
  console.log("Engine:         ", engineWallet);
  console.log("BUBBAS Token:   ", tokenAddr);
  console.log("GameRouter:     ", routerAddr);
  console.log("PayoutManager:  ", payoutAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
