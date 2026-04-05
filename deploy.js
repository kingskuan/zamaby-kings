const { ethers } = require("hardhat");

async function main() {
  const [deployer, auditor, regulator] = await ethers.getSigners();

  console.log("═══════════════════════════════════════════════");
  console.log("  PrivateFund — FHE Private Payroll Protocol");
  console.log("═══════════════════════════════════════════════");
  console.log("\nDeploying contracts with account:", deployer.address);
  console.log("Auditor address:", auditor.address);
  console.log("Regulator address:", regulator.address);
  console.log(
    "Account balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH\n"
  );

  // Deploy PrivateFund
  const PrivateFund = await ethers.getContractFactory("PrivateFund");
  const privateFund = await PrivateFund.deploy(
    auditor.address,
    regulator.address,
    { value: ethers.parseEther("0.1") } // Seed ETH for withdrawals
  );

  await privateFund.waitForDeployment();
  const address = await privateFund.getAddress();

  console.log("✅ PrivateFund deployed to:", address);
  console.log("   CFO:", deployer.address);
  console.log("   Auditor:", auditor.address);
  console.log("   Regulator:", regulator.address);

  // Verify on etherscan (if not local)
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 31337n) {
    console.log("\nWaiting 30s before Etherscan verification...");
    await new Promise((r) => setTimeout(r, 30000));

    try {
      await hre.run("verify:verify", {
        address: address,
        constructorArguments: [auditor.address, regulator.address],
      });
      console.log("✅ Contract verified on Etherscan");
    } catch (e) {
      console.log("⚠️  Verification failed:", e.message);
    }
  }

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId.toString(),
    contractAddress: address,
    cfo: deployer.address,
    auditor: auditor.address,
    regulator: regulator.address,
    deployedAt: new Date().toISOString(),
    blockNumber: await ethers.provider.getBlockNumber(),
  };

  const fs = require("fs");
  fs.writeFileSync(
    "deployment.json",
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log("\n📄 Deployment info saved to deployment.json");

  return deploymentInfo;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
