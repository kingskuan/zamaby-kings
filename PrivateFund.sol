// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

contract PrivateFund {
    address public cfo;
    address public auditor;

    mapping(address => euint64) private encryptedBalances;
    mapping(address => bool) public isEmployee;
    address[] public employeeList;

    euint64 private totalPaid;
    euint64 private budgetCap;
    bool public budgetCapSet;

    event EmployeeAdded(address indexed employee);
    event SalaryPaid(address indexed employee);

    modifier onlyCFO() {
        require(msg.sender == cfo, "Not CFO");
        _;
    }

    constructor(address _auditor) payable {
        cfo = msg.sender;
        auditor = _auditor;
        totalPaid = TFHE.asEuint64(0);
        TFHE.allowThis(totalPaid);
    }

    function addEmployee(address employee) external onlyCFO {
        require(!isEmployee[employee], "Already registered");
        isEmployee[employee] = true;
        employeeList.push(employee);
        encryptedBalances[employee] = TFHE.asEuint64(0);
        TFHE.allowThis(encryptedBalances[employee]);
        TFHE.allow(encryptedBalances[employee], employee);
        emit EmployeeAdded(employee);
    }

    function setBudgetCap(einput encryptedCap, bytes calldata proof) external onlyCFO {
        budgetCap = TFHE.asEuint64(encryptedCap, proof);
        TFHE.allowThis(budgetCap);
        TFHE.allow(budgetCap, auditor);
        budgetCapSet = true;
    }

    function paySalary(address employee, einput encryptedAmount, bytes calldata proof) external onlyCFO {
        require(isEmployee[employee], "Not employee");
        euint64 amount = TFHE.asEuint64(encryptedAmount, proof);
        encryptedBalances[employee] = TFHE.add(encryptedBalances[employee], amount);
        totalPaid = TFHE.add(totalPaid, amount);
        TFHE.allowThis(encryptedBalances[employee]);
        TFHE.allow(encryptedBalances[employee], employee);
        TFHE.allowThis(totalPaid);
        TFHE.allow(totalPaid, auditor);
        emit SalaryPaid(employee);
    }

    function getMyBalance(bytes32 publicKey) external view returns (bytes memory) {
        require(isEmployee[msg.sender], "Not employee");
        return TFHE.reencrypt(encryptedBalances[msg.sender], publicKey);
    }

    function getEmployeeCount() external view returns (uint256) {
        return employeeList.length;
    }

    receive() external payable {}
}
