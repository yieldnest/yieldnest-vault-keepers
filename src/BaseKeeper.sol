// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

import {Math, RAD, RAY, WAD} from "src/libraries/Math.sol";

contract BaseKeeper {
    uint256[] public initialRatios;
    uint256[] public finalRatios;

    // vault[0] is max vault and rest are underlying vaults
    address[] public vaults;
    IVault public maxVault;

    mapping(address => AssetData) public assetData;

    struct AssetData {
        uint256 targetRatio;
        uint256 tolerance;
        bool isManaged;
    }

    struct Transfer {
        uint256 from;
        uint256 to;
        uint256 amount;
    }

    function setMaxVault(address _maxVault) public {
        maxVault = IVault(_maxVault);
    }

    function setAsset(address asset, uint256 targetRatio, bool isManaged, uint256 tolerance) public {
        assetData[asset] = AssetData(targetRatio, tolerance, isManaged);
    }

    function setData(uint256[] memory _initialRatios, uint256[] memory _finalRatios, address[] memory _vaults) public {
        require(_initialRatios.length > 1, "Array length must be greater than 1");
        require(_initialRatios.length == _finalRatios.length, "Array lengths must match");
        require(_initialRatios.length == _vaults.length, "Array lengths must match");

        initialRatios = _initialRatios;
        finalRatios = _finalRatios;
        vaults = _vaults;
    }

    function totalInitialRatios() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < initialRatios.length; i++) {
            total += initialRatios[i];
        }
        return total;
    }

    function totalFinalRatios() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < finalRatios.length; i++) {
            total += finalRatios[i];
        }
        return total;
    }

    function calculateCurrentRatio(address asset) public view returns (uint256) {
        if (!assetData[asset].isManaged) {
            return 0;
        }
        uint256 totalAssets = maxVault.totalAssets();
        uint256 balance;

        if (isVault(asset)) {
            balance = IVault(asset).totalAssets();
        } else {
            balance = IERC20(asset).balanceOf(address(maxVault));
        }
        // get current percentage in wad: ((wad*X) / Y) / WAD = percentZ (1e18 = 100%)
        uint256 currentRatio = Math.wdiv(balance, totalAssets);
        return currentRatio;
    }

    function isVault(address asset) public view returns (bool) {
        try IVault(asset).totalAssets() returns (uint256 totalAssetsWAD) {
            return true;
        } catch {
            return false;
        }
    }

    function shouldRebalance() public view returns (bool) {
        address[] memory underlyingAssets = maxVault.getAssets();
        uint256 totalAssetsWAD = maxVault.totalAssets();

        // Step 2: Check each underlying vault's totalAssets
        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address asset = underlyingAssets[i];
            uint256 targetRatioWAD = assetData[asset].targetRatio; // Target ratio in WAD
            uint256 actualRatioWAD = calculateCurrentRatio(asset); // Calculate current ratio

            // Step 3: Check if the actual ratio deviates from the target ratio
            if (!_isWithinTolerance(asset, actualRatioWAD, targetRatioWAD)) {
                return true; // Rebalancing is required
            }
        }
        // All vaults are within target ratios
        return false;
    }

    function _isWithinTolerance(address asset, uint256 actualWAD, uint256 targetWAD) public view returns (bool) {
        uint256 tolerance = assetData[asset].tolerance;
        if (actualWAD >= targetWAD) {
            return (actualWAD - targetWAD) <= tolerance; // Upper bound
        } else {
            return (targetWAD - actualWAD) <= tolerance; // Lower bound
        }
    }

    function rebalance() public view returns (Transfer[] memory) {
        uint256 length = initialRatios.length;
        require(length > 1, "Array length must be greater than 1");
        require(length == finalRatios.length, "Array lengths must match");
        require(length == vaults.length, "Array lengths must match");

        uint256 totalInitial = totalInitialRatios();
        uint256 totalFinal = totalFinalRatios();
        require(totalInitial == totalFinal, "Ratios must add up");

        // address baseVault = vaults[0];
        // uint256 totalAssets = IVault(baseVault).totalAssets();

        uint256 totalAssets = 100; // for testing set to 100

        uint256[] memory initialAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            initialAmounts[i] = initialRatios[i] * totalAssets / totalInitial;
        }

        uint256[] memory finalAmounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            finalAmounts[i] = finalRatios[i] * totalAssets / totalFinal;
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
