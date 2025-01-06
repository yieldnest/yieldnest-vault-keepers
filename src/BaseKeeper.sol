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
    uint256[] public initialRatios;
    uint256[] public targetRatios;

    // vault[0] is max vault and rest are underlying vaults
    address[] public vaults;
    address public asset;
    IVault public maxVault;

    uint256 public tolerance;

    struct Transfer {
        uint256 from;
        uint256 to;
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
        initialRatios = new uint256[](_targetRatios.length);
        vaults = _vaults;
        for (uint256 i = 0; i < _vaults.length; i++) {
            require(isVault(_vaults[i]), "Invalid vault");
        }

        maxVault = IVault(payable(_vaults[0]));
        asset = maxVault.asset();

        require(_totalInitialRatios() == _totalTargetRatios(), "Initial and target ratios must match");
    }

    function _totalInitialRatios() internal returns (uint256) {
        uint256 totalAssets = maxVault.totalAssets();
        uint256 total = 0;
        for (uint256 i = 0; i < targetRatios.length; i++) {
            initialRatios[i] = calculateCurrentRatio(vaults[i], totalAssets);
            total += initialRatios[i];
        }
        require(total == 1e18, "Initial ratios must add up to 100 %");
        return total;
    }

    function _totalTargetRatios() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < targetRatios.length; i++) {
            total += targetRatios[i];
        }
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
        address vault;

        // Check each underlying asset's ratio.
        for (uint256 i = 0; i < vaults.length; i++) {
            vault = vaults[i];
            uint256 actualRatio = calculateCurrentRatio(vault, totalAssets); // Calculate current ratio

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

    function rebalance() public returns (Transfer[] memory) {
        uint256 length = targetRatios.length;
        require(length > 1, "Array length must be greater than 1");
        require(length == targetRatios.length, "Array lengths must match");
        require(length == vaults.length, "Array lengths must match");

        uint256 totalInitial = _totalInitialRatios();
        uint256 totalFinal = _totalTargetRatios();

        require(totalInitial == totalFinal, "Ratios must add up");

        uint256 totalAssets = maxVault.totalAssets();

        uint256[] memory initialAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            initialAmounts[i] = initialRatios[i] * totalAssets / totalInitial;
        }

        uint256[] memory finalAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            finalAmounts[i] = targetRatios[i] * totalAssets / totalFinal;
        }

        int256[] memory diffs = new int256[](length);

        // Calculate differences
        for (uint256 i = 0; i < length; i++) {
            diffs[i] = int256(initialAmounts[i]) - int256(finalAmounts[i]);
        }

        Transfer[] memory steps = new Transfer[](length);
        uint256 stepIndex = 0;

        for (uint256 i = 0; i < length; i++) {
            if (diffs[i] > 0) {
                for (uint256 j = 0; j < length; j++) {
                    if (diffs[j] < 0) {
                        uint256 transferAmount = uint256(diffs[i] > -diffs[j] ? -diffs[j] : diffs[i]);
                        steps[stepIndex++] = Transfer(i, j, transferAmount);

                        diffs[i] -= int256(transferAmount);
                        diffs[j] += int256(transferAmount);

                        if (diffs[i] == 0) break;
                    }
                }
            }
        }

        Transfer[] memory finalSteps = new Transfer[](stepIndex);
        for (uint256 i = 0; i < stepIndex; i++) {
            finalSteps[i] = steps[i];
        }

        return finalSteps;
    }
}
