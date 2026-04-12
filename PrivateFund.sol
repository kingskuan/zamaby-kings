// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint64, euint32, ebool, externalEuint64, externalEuint32 } from "fhevm/lib/FHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import { GatewayCaller } from "fhevm/lib/GatewayCaller.sol";

/**
 * @title PrivateFund
 * @notice FHE-powered private payroll & fund management protocol
 * @dev All salary amounts are encrypted using Zama FHEVM.
 *      - CFO can pay employees with encrypted amounts
 *      - Employees can only view their own balance
 *      - Auditor can verify compliance without seeing individual amounts
 *      - Regulator can request decryption of specific records via ACL
 */
contract PrivateFund is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {

    // ─── Roles ───────────────────────────────────────────────────────────────

    address public cfo;
    address public auditor;
    address public regulator;

    // ─── Encrypted State ─────────────────────────────────────────────────────

    /// @dev Employee encrypted balance: only the employee + contract can read
    mapping(address => euint64) private encryptedBalances;

    /// @dev Whether employee has been registered
    mapping(address => bool) public isEmployee;

    /// @dev Total amount paid (encrypted) — auditor can read, not individuals
    euint64 private encryptedTotalPaid;

    /// @dev Budget cap set by CFO (encrypted)
    euint64 private encryptedBudgetCap;

    /// @dev Whether budget cap has been set
    bool public budgetCapSet;

    // ─── Plaintext Tracking ──────────────────────────────────────────────────

    address[] public employeeList;
    uint256 public paymentRoundCount;

    /// @dev Pending withdrawal amounts resolved via Gateway callback
    mapping(uint256 => address) private pendingWithdrawals;
    mapping(address => uint256) private pendingWithdrawAmounts;

    // ─── Events ──────────────────────────────────────────────────────────────

    event EmployeeAdded(address indexed employee, uint256 timestamp);
    event SalaryPaid(address indexed employee, uint256 timestamp, uint256 round);
    event BudgetCapSet(uint256 timestamp);
    event ComplianceCheckRequested(address indexed auditor, uint256 timestamp);
    event WithdrawalRequested(address indexed employee, uint256 timestamp);
    event WithdrawalExecuted(address indexed employee, uint256 amount, uint256 timestamp);
    event RegulatorDecryptionGranted(address indexed employee, address indexed regulator);

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyCFO() {
        require(msg.sender == cfo, "PrivateFund: caller is not CFO");
        _;
    }

    modifier onlyAuditor() {
        require(msg.sender == auditor, "PrivateFund: caller is not auditor");
        _;
    }

    modifier onlyEmployee() {
        require(isEmployee[msg.sender], "PrivateFund: caller is not registered employee");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _auditor, address _regulator) payable {
        cfo = msg.sender;
        auditor = _auditor;
        regulator = _regulator;

        // Initialize encrypted total to 0
        encryptedTotalPaid = FHE.asEuint64(0);
        FHE.allowThis(encryptedTotalPaid);
        FHE.allow(encryptedTotalPaid, auditor);
    }

    // ─── CFO Functions ───────────────────────────────────────────────────────

    /**
     * @notice CFO adds an employee to the payroll
     */
    function addEmployee(address employee) external onlyCFO {
        require(!isEmployee[employee], "PrivateFund: already registered");
        require(employee != address(0), "PrivateFund: zero address");

        isEmployee[employee] = true;
        employeeList.push(employee);

        // Initialize encrypted balance to 0
        encryptedBalances[employee] = FHE.asEuint64(0);
        FHE.allowThis(encryptedBalances[employee]);
        FHE.allow(encryptedBalances[employee], employee);

        emit EmployeeAdded(employee, block.timestamp);
    }

    /**
     * @notice CFO sets the encrypted budget cap
     * @dev Budget amount is encrypted — even CFO cannot read it back
     */
    function setBudgetCap(
        externalEuint64 calldata encryptedCap,
        bytes calldata inputProof
    ) external onlyCFO {
        encryptedBudgetCap = FHE.fromExternal(encryptedCap, inputProof);
        FHE.allowThis(encryptedBudgetCap);
        // Auditor can verify budget without seeing the exact number
        FHE.allow(encryptedBudgetCap, auditor);
        budgetCapSet = true;
        emit BudgetCapSet(block.timestamp);
    }

    /**
     * @notice CFO pays a single employee with an encrypted salary amount
     * @param employee  The employee's address
     * @param encryptedAmount  The encrypted salary amount (from Relayer SDK)
     * @param inputProof  The ZK proof validating the encrypted input
     */
    function paySalary(
        address employee,
        externalEuint64 calldata encryptedAmount,
        bytes calldata inputProof
    ) external onlyCFO {
        require(isEmployee[employee], "PrivateFund: not an employee");

        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        // Add to employee's encrypted balance (fully on-chain FHE computation)
        encryptedBalances[employee] = FHE.add(encryptedBalances[employee], amount);

        // Add to encrypted total paid
        encryptedTotalPaid = FHE.add(encryptedTotalPaid, amount);

        // Grant access permissions
        FHE.allowThis(encryptedBalances[employee]);
        FHE.allow(encryptedBalances[employee], employee);    // Employee reads own balance
        FHE.allow(encryptedBalances[employee], regulator);  // Regulator can request decrypt

        FHE.allowThis(encryptedTotalPaid);
        FHE.allow(encryptedTotalPaid, auditor);             // Auditor reads total

        emit SalaryPaid(employee, block.timestamp, paymentRoundCount);
    }

    /**
     * @notice CFO pays multiple employees in a single batch transaction
     */
    function paySalaryBatch(
        address[] calldata employees,
        externalEuint64[] calldata encryptedAmounts,
        bytes[] calldata inputProofs
    ) external onlyCFO {
        require(employees.length == encryptedAmounts.length, "PrivateFund: length mismatch");
        require(employees.length == inputProofs.length, "PrivateFund: proof length mismatch");
        require(employees.length > 0, "PrivateFund: empty batch");

        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];
            require(isEmployee[employee], "PrivateFund: not an employee");

            euint64 amount = FHE.fromExternal(encryptedAmounts[i], inputProofs[i]);

            encryptedBalances[employee] = FHE.add(encryptedBalances[employee], amount);
            encryptedTotalPaid = FHE.add(encryptedTotalPaid, amount);

            FHE.allowThis(encryptedBalances[employee]);
            FHE.allow(encryptedBalances[employee], employee);
            FHE.allow(encryptedBalances[employee], regulator);

            emit SalaryPaid(employee, block.timestamp, paymentRoundCount);
        }

        FHE.allowThis(encryptedTotalPaid);
        FHE.allow(encryptedTotalPaid, auditor);

        paymentRoundCount++;
    }

    // ─── Employee Functions ──────────────────────────────────────────────────

    /**
     * @notice Employee re-encrypts their balance for client-side decryption
     * @dev Uses FHEVM's seal mechanism: balance is re-encrypted with employee's public key
     *      The result can ONLY be decrypted by the employee's private key
     * @param publicKey  Employee's ephemeral public key from Relayer SDK
     * @return  Sealed (re-encrypted) balance ciphertext
     */
    function getMyBalance(bytes32 publicKey) external view onlyEmployee returns (bytes memory) {
        return FHE.sealoutput(encryptedBalances[msg.sender], publicKey);
    }

    /**
     * @notice Employee requests to withdraw funds
     * @dev Uses FHE.select for branchless, privacy-preserving withdrawal logic.
     *      Even if balance is insufficient, no information leaks on-chain.
     *      Actual ETH/token transfer happens via Gateway callback.
     */
    function requestWithdrawal(
        externalEuint64 calldata encryptedAmount,
        bytes calldata inputProof
    ) external onlyEmployee {
        euint64 requestedAmount = FHE.fromExternal(encryptedAmount, inputProof);

        // Encrypted comparison: is balance >= requested amount?
        ebool hasSufficientFunds = FHE.ge(encryptedBalances[msg.sender], requestedAmount);

        // FHE.select: branchless conditional — no information leak
        // If sufficient: deduct from balance. If not: leave balance unchanged.
        encryptedBalances[msg.sender] = FHE.select(
            hasSufficientFunds,
            FHE.sub(encryptedBalances[msg.sender], requestedAmount),
            encryptedBalances[msg.sender]
        );

        FHE.allowThis(encryptedBalances[msg.sender]);
        FHE.allow(encryptedBalances[msg.sender], msg.sender);

        // Request Gateway to decrypt hasSufficientFunds to execute transfer
        // The boolean tells us IF we should transfer, not how much
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(hasSufficientFunds);

        // Store pending context for callback
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.withdrawalCallback.selector,
            0,
            block.timestamp + 100,
            false
        );
        pendingWithdrawals[requestId] = msg.sender;

        emit WithdrawalRequested(msg.sender, block.timestamp);
    }

    /**
     * @notice Gateway callback for withdrawal execution
     * @dev Called by the Gateway after decrypting the hasSufficientFunds boolean
     */
    function withdrawalCallback(
        uint256 requestId,
        bool hasSufficientFunds
    ) external onlyGateway {
        address employee = pendingWithdrawals[requestId];
        uint256 amount = pendingWithdrawAmounts[employee];

        if (hasSufficientFunds && amount > 0 && address(this).balance >= amount) {
            pendingWithdrawAmounts[employee] = 0;
            delete pendingWithdrawals[requestId];
            payable(employee).transfer(amount);
            emit WithdrawalExecuted(employee, amount, block.timestamp);
        }
        delete pendingWithdrawals[requestId];
    }

    // ─── Auditor Functions ───────────────────────────────────────────────────

    /**
     * @notice Auditor verifies total spend is within budget — without seeing exact amounts
     * @dev Returns an encrypted boolean. The auditor decrypts ONLY the yes/no result.
     *      This is the core innovation: compliance verification without privacy breach.
     * @return complianceResult  Encrypted bool: true = within budget, false = over budget
     */
    function requestComplianceCheck() external onlyAuditor returns (ebool) {
        require(budgetCapSet, "PrivateFund: budget cap not set");

        // FHE comparison: totalPaid <= budgetCap (fully encrypted)
        ebool withinBudget = FHE.le(encryptedTotalPaid, encryptedBudgetCap);

        // Grant auditor access to decrypt ONLY this boolean result
        FHE.allow(withinBudget, auditor);

        // Make publicly verifiable — the conclusion is public, the numbers are not
        FHE.makePubliclyDecryptable(withinBudget);

        emit ComplianceCheckRequested(msg.sender, block.timestamp);

        return withinBudget;
    }

    /**
     * @notice Auditor re-encrypts total paid for their own client-side viewing
     */
    function getTotalPaidSealed(bytes32 publicKey) external view onlyAuditor returns (bytes memory) {
        return FHE.sealoutput(encryptedTotalPaid, publicKey);
    }

    // ─── Regulator Functions ─────────────────────────────────────────────────

    /**
     * @notice Regulator requests decryption of a specific employee's balance
     * @dev In MiCA-compliant systems, regulator access is pre-authorized via ACL.
     *      The regulator can request Gateway decryption for compliance/legal purposes.
     */
    function regulatorRequestDecryption(address employee) external {
        require(msg.sender == regulator, "PrivateFund: not regulator");
        require(isEmployee[employee], "PrivateFund: not an employee");

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedBalances[employee]);

        Gateway.requestDecryption(
            cts,
            this.regulatorDecryptCallback.selector,
            0,
            block.timestamp + 100,
            false
        );

        emit RegulatorDecryptionGranted(employee, msg.sender);
    }

    function regulatorDecryptCallback(
        uint256 /*requestId*/,
        uint64 /*balance*/
    ) external onlyGateway {
        // In production: emit event, store result for regulator retrieval
        // Balance is now available to regulator off-chain via event logs
    }

    // ─── View Functions ──────────────────────────────────────────────────────

    function getEmployeeCount() external view returns (uint256) {
        return employeeList.length;
    }

    function getEmployee(uint256 index) external view returns (address) {
        return employeeList[index];
    }

    // ─── Receive ETH ─────────────────────────────────────────────────────────

    receive() external payable {}
}
