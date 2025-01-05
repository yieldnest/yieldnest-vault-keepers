// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import "src/BaseKeeper.sol";

contract BaseKeeperTest is Test {
    BaseKeeper baseKeeper;

    function setUp() public {
        baseKeeper = new BaseKeeper();
    }

    function testSetData() public {
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

    function testTotalInitialRatios() public {
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

    function testTotalFinalRatios() public {
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

    function testCaculateSteps_ExampleOne() public {
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

        BaseKeeper.Transfer[] memory steps = baseKeeper.caculateSteps();

        assertEq(steps.length, 1);

        // Validate first step
        assertEq(steps[0].from, 0);
        assertEq(steps[0].to, 1);
        assertEq(steps[0].amount, 10);
    }

    function testCaculateSteps_ExampleTwo() public {
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

        BaseKeeper.Transfer[] memory steps = baseKeeper.caculateSteps();

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

    function testCaculateSteps_ExampleThree() public {
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

        BaseKeeper.Transfer[] memory steps = baseKeeper.caculateSteps();

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

    function testSetDataFailsForMismatchedArrayLengths() public {
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

    function testCaculateStepsFailsForUnmatchedRatios() public {
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
        baseKeeper.caculateSteps();
    }
}
