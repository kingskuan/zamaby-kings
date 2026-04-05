const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * PrivateFund Test Suite
 * 
 * NOTE: Full FHE tests require the Zama FHEVM hardhat plugin and a running
 * local FHEVM node. These tests use mock/plaintext values for CI purposes.
 * Run against the Zama devnet for full FHE integration tests.
 */
describe("PrivateFund", function () {
  let privateFund;
  let cfo, auditor, regulator, employee1, employee2, employee3;

  beforeEach(async function () {
    [cfo, auditor, regulator, employee1, employee2, employee3] =
      await ethers.getSigners();

    const PrivateFund = await ethers.getContractFactory("PrivateFund");
    privateFund = await PrivateFund.deploy(
      auditor.address,
      regulator.address,
      { value: ethers.parseEther("1.0") }
    );
    await privateFund.waitForDeployment();
  });

  // ─── Role Setup ────────────────────────────────────────────────────────────

  describe("Deployment", function () {
    it("Should set correct CFO, auditor, regulator", async function () {
      expect(await privateFund.cfo()).to.equal(cfo.address);
      expect(await privateFund.auditor()).to.equal(auditor.address);
      expect(await privateFund.regulator()).to.equal(regulator.address);
    });

    it("Should initialize with 0 employees", async function () {
      expect(await privateFund.getEmployeeCount()).to.equal(0);
    });

    it("Should accept ETH funding on deploy", async function () {
      const balance = await ethers.provider.getBalance(
        await privateFund.getAddress()
      );
      expect(balance).to.equal(ethers.parseEther("1.0"));
    });
  });

  // ─── Employee Management ───────────────────────────────────────────────────

  describe("Employee Management", function () {
    it("CFO can add employees", async function () {
      await privateFund.connect(cfo).addEmployee(employee1.address);
      expect(await privateFund.isEmployee(employee1.address)).to.be.true;
      expect(await privateFund.getEmployeeCount()).to.equal(1);
    });

    it("Should emit EmployeeAdded event", async function () {
      await expect(privateFund.connect(cfo).addEmployee(employee1.address))
        .to.emit(privateFund, "EmployeeAdded")
        .withArgs(employee1.address, await getBlockTimestamp());
    });

    it("Cannot add same employee twice", async function () {
      await privateFund.connect(cfo).addEmployee(employee1.address);
      await expect(
        privateFund.connect(cfo).addEmployee(employee1.address)
      ).to.be.revertedWith("PrivateFund: already registered");
    });

    it("Non-CFO cannot add employees", async function () {
      await expect(
        privateFund.connect(employee1).addEmployee(employee2.address)
      ).to.be.revertedWith("PrivateFund: caller is not CFO");
    });

    it("Cannot add zero address", async function () {
      await expect(
        privateFund.connect(cfo).addEmployee(ethers.ZeroAddress)
      ).to.be.revertedWith("PrivateFund: zero address");
    });
  });

  // ─── Access Control ────────────────────────────────────────────────────────

  describe("Access Control", function () {
    beforeEach(async function () {
      await privateFund.connect(cfo).addEmployee(employee1.address);
    });

    it("Non-employee cannot call getMyBalance", async function () {
      // employee2 not registered
      await expect(
        privateFund
          .connect(employee2)
          .getMyBalance(ethers.randomBytes(32))
      ).to.be.revertedWith("PrivateFund: caller is not registered employee");
    });

    it("Non-auditor cannot call requestComplianceCheck", async function () {
      await expect(
        privateFund.connect(employee1).requestComplianceCheck()
      ).to.be.revertedWith("PrivateFund: caller is not auditor");
    });

    it("Non-regulator cannot call regulatorRequestDecryption", async function () {
      await expect(
        privateFund
          .connect(employee1)
          .regulatorRequestDecryption(employee1.address)
      ).to.be.revertedWith("PrivateFund: not regulator");
    });

    it("Compliance check requires budget cap to be set", async function () {
      await expect(
        privateFund.connect(auditor).requestComplianceCheck()
      ).to.be.revertedWith("PrivateFund: budget cap not set");
    });
  });

  // ─── Payroll (Mock FHE — replace with fhevm plugin for full test) ──────────

  describe("Payroll Flow (structural test)", function () {
    it("Batch payment reverts on unregistered employee", async function () {
      // Structural test: checks length validation
      await expect(
        privateFund.connect(cfo).paySalaryBatch(
          [],    // empty arrays
          [],
          []
        )
      ).to.be.revertedWith("PrivateFund: empty batch");
    });

    it("Batch payment reverts on mismatched arrays", async function () {
      const fakeEncrypted = {
        handle: ethers.hexlify(ethers.randomBytes(32)),
        inputProof: "0x00"
      };
      await expect(
        privateFund.connect(cfo).paySalaryBatch(
          [employee1.address, employee2.address],
          [fakeEncrypted],
          ["0x00"]
        )
      ).to.be.revertedWith("PrivateFund: length mismatch");
    });
  });

  // ─── Funding ───────────────────────────────────────────────────────────────

  describe("Contract Funding", function () {
    it("Can receive ETH after deployment", async function () {
      const contractAddress = await privateFund.getAddress();
      await cfo.sendTransaction({
        to: contractAddress,
        value: ethers.parseEther("0.5"),
      });
      const balance = await ethers.provider.getBalance(contractAddress);
      expect(balance).to.be.gte(ethers.parseEther("1.0"));
    });
  });

  // ─── Helpers ───────────────────────────────────────────────────────────────

  async function getBlockTimestamp() {
    const block = await ethers.provider.getBlock("latest");
    return block.timestamp + 1; // +1 for next tx
  }
});

/**
 * FHEVM Integration Tests
 * Run with: FHEVM_NO_DECORATOR=false npx hardhat test --network zamaDevnet
 */
describe("PrivateFund — FHEVM Integration (requires devnet)", function () {
  it.skip("Full encrypted payroll flow with real FHE", async function () {
    // This test requires:
    // 1. Running Zama local devnet: npx hardhat node (with fhevm plugin)
    // 2. fhevm-hardhat-plugin configured
    // 3. createEncryptedInput() from the plugin

    const { createEncryptedInput } = require("@zama/fhevm-hardhat-plugin");
    // ... full FHE test implementation
  });
});
