require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    const owner = deployer.address;
    const opsWallet = process.env.OPS_WALLET;
    const engineWallet = process.env.ENGINE_WALLET;

    if (!opsWallet) throw new Error("OPS_WALLET not set");
    if (opsWallet.toLowerCase() === owner.toLowerCase()) throw new Error("OPS_WALLET must differ from deployer");
    if (!engineWallet) throw new Error("ENGINE_WALLET not set");

    const balance = await ethers.provider.getBalance(deployer.address);

    console.log("Deploying with:", deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "tBNB");
    console.log("Owner:", owner);
    console.log("Ops wallet:", opsWallet);
    console.log("Engine wallet:", engineWallet);

    // --- 1. Deploy BUBBATEST v2 ---
    const Token = await ethers.getContractFactory("BubbasTokenTest");
    const token = await Token.deploy(owner, opsWallet);
    await token.waitForDeployment();
    const tokenAddr = await token.getAddress();
    console.log("BUBBATEST v2 deployed:", tokenAddr);

    // --- 2. Deploy GameRouter ---
    const Router = await ethers.getContractFactory("GameRouter");
    const router = await Router.deploy(owner, engineWallet);
    await router.waitForDeployment();
    const routerAddr = await router.getAddress();
    console.log("GameRouter deployed:", routerAddr);

    // --- 3. Deploy PayoutManager ---
    const PayoutManager = await ethers.getContractFactory("PayoutManager");
    const payout = await PayoutManager.deploy(owner, engineWallet, tokenAddr);
    await payout.waitForDeployment();
    const payoutAddr = await payout.getAddress();
    console.log("PayoutManager deployed:", payoutAddr);

    console.log("\n--- Testnet Deployment Summary ---");
    console.log("Owner:          ", owner);
    console.log("OPS wallet:     ", opsWallet);
    console.log("Engine:         ", engineWallet);
    console.log("BUBBATEST v2:   ", tokenAddr);
    console.log("GameRouter:     ", routerAddr);
    console.log("PayoutManager:  ", payoutAddr);

    console.log("\n--- Verify Commands ---");
    console.log(`npx hardhat verify --network bscTestnet ${tokenAddr} ${owner} ${opsWallet}`);
    console.log(`npx hardhat verify --network bscTestnet ${routerAddr} ${owner} ${engineWallet}`);
    console.log(`npx hardhat verify --network bscTestnet ${payoutAddr} ${owner} ${engineWallet} ${tokenAddr}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
