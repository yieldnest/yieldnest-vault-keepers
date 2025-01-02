// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

// import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

contract BaseKeeper {
    uint256[] public initialRatios;
    uint256[] public finalRatios;

    // vault[0] is max vault and rest are underlying vaults
    address[] public vaults;

    struct Transfer {
        uint256 from;
        uint256 to;
        uint256 amount;
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

    function caculateSteps() public view returns (Transfer[] memory) {
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
        uint256 totalSteps = 0;

        // Calculate differences
        for (uint256 i = 0; i < length; i++) {
            diffs[i] = int256(initialAmounts[i]) - int256(finalAmounts[i]);
        }

        // Count total surplus and deficit
        for (uint256 i = 0; i < length; i++) {
            if (diffs[i] > 0) totalSteps += uint256(diffs[i]);
        }

        Transfer[] memory steps = new Transfer[](totalSteps);
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

        return steps;
    }
}
