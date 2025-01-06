// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/yieldnest-vault/lib/forge-std/src/Test.sol";

import {MainnetContracts} from "lib/yieldnest-vault/script/Contracts.sol";
import {SetupVault, Vault, WETH9} from "lib/yieldnest-vault/test/unit/helpers/SetupVault.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {BaseKeeper} from "src/BaseKeeper.sol";

contract BaseKeeperTest is Test {
    BaseKeeper public baseKeeper;
    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    uint256 public INITIAL_BALANCE = 10 ether;

    address public alice = address(0xa11ce);

    function setUp() public {
        baseKeeper = new BaseKeeper();
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();
        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MainnetContracts.STETH));

        deal(address(steth), alice, INITIAL_BALANCE);
        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);

        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        vm.startPrank(alice);

        steth.approve(address(vault), INITIAL_BALANCE);
        weth.approve(address(vault), type(uint256).max);

        vault.depositAsset(address(steth), INITIAL_BALANCE, alice);
        vault.depositAsset(address(weth), INITIAL_BALANCE, alice);
        vm.stopPrank();

        baseKeeper.setAsset(address(weth), 6e17, true, 0);
        baseKeeper.setAsset(address(steth), 5e17, true, 0);
        baseKeeper.setMaxVault(address(vault));

        vm.label(address(weth), "WETH");
        vm.label(address(steth), "STETH");
        vm.label(address(vault), "Vault");
        vm.label(address(baseKeeper), "BaseKeeper");
    }

    function test_SetData() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 30;
        initialRatios[2] = 20;

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        assertEq(baseKeeper.initialRatios(0), 50);
        assertEq(baseKeeper.finalRatios(1), 40);
        assertEq(baseKeeper.vaults(2), address(3));
    }

    function test_TotalInitialRatios() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 30;
        initialRatios[2] = 20;

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        assertEq(baseKeeper.totalInitialRatios(), 100);
    }

    function test_TotalFinalRatios() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 30;
        initialRatios[2] = 20;

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        assertEq(baseKeeper.totalFinalRatios(), 100);
    }

    function test_Rebalance_ExampleOne() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 30;
        initialRatios[2] = 20;

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 1);

        // Validate first step
        assertEq(steps[0].from, 0);
        assertEq(steps[0].to, 1);
        assertEq(steps[0].amount, 10);
    }

    function test_Rebalance_ExampleTwo() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 30;
        initialRatios[2] = 20;

        finalRatios[0] = 20;
        finalRatios[1] = 40;
        finalRatios[2] = 40;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2);

        // Validate first step
        assertEq(steps[0].from, 0);
        assertEq(steps[0].to, 1);
        assertEq(steps[0].amount, 10);

        // Validate second step
        assertEq(steps[1].from, 0);
        assertEq(steps[1].to, 2);
        assertEq(steps[1].amount, 20);
    }

    function test_Rebalance_ExampleThree() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 50;
        initialRatios[2] = 0;

        finalRatios[0] = 33;
        finalRatios[1] = 33;
        finalRatios[2] = 34;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2);

        // Validate first step
        assertEq(steps[0].from, 0);
        assertEq(steps[0].to, 2);
        assertEq(steps[0].amount, 17);

        // Validate second step
        assertEq(steps[1].from, 1);
        assertEq(steps[1].to, 2);
        assertEq(steps[1].amount, 17);
    }

    function test_SetDataFailsForMismatchedArrayLengths() public {
        uint256[] memory initialRatios = new uint256[](2);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 50;

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        vm.expectRevert("Array lengths must match");
        baseKeeper.setData(initialRatios, finalRatios, vaults);
    }

    function test_RebalanceFailsForUnmatchedRatios() public {
        uint256[] memory initialRatios = new uint256[](3);
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        initialRatios[0] = 50;
        initialRatios[1] = 30;
        initialRatios[2] = 20;

        finalRatios[0] = 50;
        finalRatios[1] = 30;
        finalRatios[2] = 10;

        vaults[0] = address(1);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(initialRatios, finalRatios, vaults);

        vm.expectRevert("Ratios must add up");
        baseKeeper.rebalance();
    }

    function test_SetAsset() public {
        baseKeeper.setAsset(address(weth), 8e17, false, 1000);
        (uint256 targetRatio, uint256 tolerance, bool isManaged) = baseKeeper.assetData(address(weth));
        assertEq(targetRatio, 8e17);
        assertEq(isManaged, false);
        assertEq(tolerance, 1000);
    }

    function test_SetMaxVault() public {
        baseKeeper.setMaxVault(address(1));
        assertEq(address(baseKeeper.maxVault()), address(1));
    }

    function test_CalculateCurrentRatio() public {
        uint256 currentRatio = baseKeeper.calculateCurrentRatio(address(weth), vault.totalAssets());
        assertEq(currentRatio, 5e17);
    }

    function test_ShouldRebalance() public {
        bool shouldRebalance = baseKeeper.shouldRebalance();
        assertEq(shouldRebalance, true);
    }
}
