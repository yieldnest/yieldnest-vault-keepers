// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Ownable} from "lib/yieldnest-vault/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/yieldnest-vault/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {Math} from "src/libraries/Math.sol";

import {console} from "lib/yieldnest-vault/lib/forge-std/src/console.sol";

contract BaseKeeper is Ownable {
    uint256[] private targetRatios;

    // vault[0] is max vault and rest are underlying vaults
    address[] public vaults;
    address public asset;
    IVault public maxVault;

    uint256 public tolerance;

    struct Deposit {
        uint256 to;
        uint256 amount;
    }

    struct Withdraw {
        uint256 from;
        uint256 amount;
    }

    constructor() Ownable(msg.sender) {}

    function setTolerance(uint256 _tolerance) public onlyOwner {
        tolerance = _tolerance;
    }

    function setData(uint256[] memory _targetRatios, address[] memory _vaults) public onlyOwner {
        require(_targetRatios.length > 1, "Array length must be greater than 1");
        require(_targetRatios.length == _vaults.length, "Array lengths must match");

        targetRatios = _targetRatios;
        vaults = _vaults;
        for (uint256 i = 0; i < _vaults.length; i++) {
            require(isVault(_vaults[i]), "Invalid vault");
        }

        maxVault = IVault(payable(_vaults[0]));
        asset = maxVault.asset();

        require(totalInitialRatios() == totalTargetRatios(), "Initial and target ratios must match");
    }

    function totalInitialRatios() public view returns (uint256) {
        uint256 totalAssets = maxVault.totalAssets();
        uint256 total = 0;
        for (uint256 i = 0; i < targetRatios.length; i++) {
            total += calculateCurrentRatio(vaults[i], totalAssets);
        }
        require(total == 1e18, "Initial ratios must add up to 100 %");
        return total;
    }

    function totalTargetRatios() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < targetRatios.length; i++) {
            total += targetRatios[i];
        }
        require(total == 1e18, "Target ratios must add up to 100 %");
        return total;
    }

    function calculateCurrentRatio(address vault, uint256 totalAssets) public view returns (uint256) {
        uint256 balance;
        if (vault == address(maxVault)) {
            balance = IERC20(asset).balanceOf(address(maxVault));
        } else {
            balance = IVault(vault).totalAssets();
        }

        uint256 rate = IProvider(maxVault.provider()).getRate(asset);

        // get current percentage in wad: ((wad*X) / Y) / WAD = percentZ (1e18 = 100%)
        uint256 adjustedBalance = Math.wmul(balance, rate);
        uint256 currentRatio = Math.wdiv(adjustedBalance, totalAssets);
        return currentRatio;
    }

    function isVault(address target) public view returns (bool) {
        try Vault(payable(target)).VAULT_VERSION() returns (string memory version) {
            return bytes(version).length > 0;
        } catch {
            return false;
        }
    }

    function shouldRebalance() public view returns (bool) {
        uint256 totalAssets = maxVault.totalAssets();

        // Check each underlying asset's ratio.
        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 actualRatio = calculateCurrentRatio(vaults[i], totalAssets); // Calculate current ratio

            // Check if the actual ratio deviates from the target ratio
            if (!isWithinTolerance(actualRatio, targetRatios[i])) {
                return true; // Rebalancing is required
            }
        }
        // All vaults are within target ratios
        return false;
    }

    function isWithinTolerance(uint256 actualWAD, uint256 targetWAD) public view returns (bool) {
        if (actualWAD >= targetWAD) {
            // todo: make tolerance a percentage
            return (actualWAD - targetWAD) <= tolerance; // Upper bound
        } else {
            return (targetWAD - actualWAD) <= tolerance; // Lower bound
        }
    }

    function currentRatios() public view returns (uint256[] memory ratios) {
        uint256 length = vaults.length;
        uint256 totalAssets = maxVault.totalAssets();
        ratios = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            ratios[i] = calculateCurrentRatio(vaults[i], totalAssets);
        }
    }

    function finalRatios() public view returns (uint256[] memory ratios) {
        return targetRatios;
    }

    function calculateDiffs() public view returns (int256[] memory diffs) {
        uint256 length = vaults.length;

        uint256 totalAssets = maxVault.totalAssets();
        uint256[] memory initialRatios = new uint256[](length);

        uint256 totalInitial = 0;
        uint256 totalFinal = totalTargetRatios();

        for (uint256 i = 0; i < vaults.length; i++) {
            initialRatios[i] = calculateCurrentRatio(vaults[i], totalAssets);
            totalInitial += initialRatios[i];
        }

        require(totalInitial == totalFinal, "Ratios must add up");

        uint256[] memory initialAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            initialAmounts[i] = initialRatios[i] * totalAssets / totalInitial;
        }

        uint256[] memory finalAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            finalAmounts[i] = targetRatios[i] * totalAssets / totalFinal;
        }

        diffs = new int256[](length);

        // Calculate differences
        for (uint256 i = 0; i < length; i++) {
            diffs[i] = int256(initialAmounts[i]) - int256(finalAmounts[i]);
        }
    }

    function calculateTransfers() public view returns (Withdraw[] memory, Deposit[] memory) {
        uint256 length = vaults.length;

        int256[] memory diffs = calculateDiffs();

        Withdraw[] memory withdraws = new Withdraw[](length);
        Deposit[] memory deposits = new Deposit[](length);
        uint256 withdrawIndex = 0;
        uint256 depositIndex = 0;

        for (uint256 i = 0; i < length; i++) {
            if (diffs[i] > 0) {
                for (uint256 j = 0; j < length; j++) {
                    if (diffs[j] < 0) {
                        uint256 transferAmount = uint256(diffs[i] > -diffs[j] ? -diffs[j] : diffs[i]);

                        if (j == 0) {
                            withdraws[withdrawIndex++] = Withdraw(i, transferAmount);
                        } else if (i == 0) {
                            deposits[depositIndex++] = Deposit(j, transferAmount);
                        } else {
                            withdraws[withdrawIndex++] = Withdraw(i, transferAmount);
                            deposits[depositIndex++] = Deposit(j, transferAmount);
                        }

                        diffs[i] -= int256(transferAmount);
                        diffs[j] += int256(transferAmount);

                        if (diffs[i] == 0) break;
                    }
                }
            }
        }

        Withdraw[] memory sortedWithdraws = new Withdraw[](length);
        Deposit[] memory sortedDeposits = new Deposit[](length);

        uint256 sortedWithdrawIndex = 0;
        uint256 sortedDepositIndex = 0;

        for (uint256 j = 0; j < length; j++) {
            uint256 withdrawAmount = 0;
            uint256 depositAmount = 0;
            for (uint256 i = 0; i < withdrawIndex; i++) {
                if (withdraws[i].from == j) {
                    withdrawAmount += withdraws[i].amount;
                }
            }
            for (uint256 i = 0; i < depositIndex; i++) {
                if (deposits[i].to == j) {
                    depositAmount += deposits[i].amount;
                }
            }
            if (withdrawAmount > 0) {
                sortedWithdraws[sortedWithdrawIndex++] = Withdraw(j, withdrawAmount);
            }
            if (depositAmount > 0) {
                sortedDeposits[sortedDepositIndex++] = Deposit(j, depositAmount);
            }
        }

        Withdraw[] memory finalWithdraws = new Withdraw[](sortedWithdrawIndex);
        Deposit[] memory finalDeposits = new Deposit[](sortedDepositIndex);

        for (uint256 i = 0; i < sortedWithdrawIndex; i++) {
            finalWithdraws[i] = sortedWithdraws[i];
        }
        for (uint256 i = 0; i < sortedDepositIndex; i++) {
            finalDeposits[i] = sortedDeposits[i];
        }

        return (finalWithdraws, finalDeposits);
    }

    function rebalance() public {}
}
