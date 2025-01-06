// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";

import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {SetupVault, Vault, WETH9} from "lib/yieldnest-vault/test/unit/helpers/SetupVault.sol";
import {BaseKeeper} from "src/BaseKeeper.sol";

contract BaseKeeperTest is Test, MainnetActors {
    BaseKeeper public baseKeeper;
    Vault public maxVault;
    Vault public underlyingVault1;
    Vault public underlyingVault2;

    WETH9 public weth;

    uint256 public constant INITIAL_BALANCE = 10 ether;

    address public alice = address(0xa11ce);

    function setUp() public {
        baseKeeper = new BaseKeeper();

        SetupVault setupVault = new SetupVault();
        (maxVault, weth) = setupVault.setup();
        (underlyingVault1,) = setupVault.setup();
        (underlyingVault2,) = setupVault.setup();

        vm.startPrank(ASSET_MANAGER);
        maxVault.addAsset(address(underlyingVault1), false);
        maxVault.addAsset(address(underlyingVault2), false);
        vm.stopPrank();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        weth.deposit{value: INITIAL_BALANCE}();

        // deposit assets
        weth.approve(address(maxVault), type(uint256).max);
        maxVault.depositAsset(address(weth), INITIAL_BALANCE, alice);
        vm.stopPrank();

        vm.label(address(weth), "WETH");
        vm.label(address(maxVault), "Max Vault");
        vm.label(address(underlyingVault1), "Underlying Vault 1");
        vm.label(address(underlyingVault2), "Underlying Vault 2");
        vm.label(address(baseKeeper), "BaseKeeper");
    }

    function test_ViewFunctions() public view {
        assertEq(maxVault.totalAssets(), INITIAL_BALANCE);
        assertEq(underlyingVault1.totalAssets(), 0);
        assertEq(underlyingVault2.totalAssets(), 0);
        assertEq(weth.balanceOf(address(maxVault)), INITIAL_BALANCE);
    }

    function test_SetData() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        finalRatios[0] = 40 * 1e16;
        finalRatios[1] = 40 * 1e16;
        finalRatios[2] = 20 * 1e16;

        assertEq(finalRatios[0] + finalRatios[1] + finalRatios[2], 1e18);

        vaults[0] = address(maxVault);
        vaults[1] = address(underlyingVault1);
        vaults[2] = address(underlyingVault2);

        baseKeeper.setData(finalRatios, vaults);

        assertEq(baseKeeper.initialRatios(0), 1e18);
        assertEq(baseKeeper.targetRatios(1), 40 * 1e16);
        assertEq(baseKeeper.vaults(2), address(underlyingVault2));
    }

    function test_Rebalance_ExampleOne() public {
        setData(0.5e18, 0.25e18, 0.25e18);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2, "Expected 2 steps");

        // Validate first step
        assertEq(steps[0].from, 0, "Expected from for step 0");
        assertEq(steps[0].to, 1, "Expected to for step 0");
        assertEq(steps[0].amount, INITIAL_BALANCE / 4, "Expected amount for step 0");

        // Validate second step
        assertEq(steps[1].from, 0, "Expected from for step 1");
        assertEq(steps[1].to, 2, "Expected to for step 1");
        assertEq(steps[1].amount, INITIAL_BALANCE / 4, "Expected amount for step 1");
    }

    function test_Rebalance_ExampleTwo() public {
        setData(0.5e18, 0.4e18, 0.1e18);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2);

        // Validate first step
        assertEq(steps[0].from, 0, "Expected from for step 0");
        assertEq(steps[0].to, 1, "Expected to for step 0");
        assertEq(steps[0].amount, 4 * INITIAL_BALANCE / 10, "Expected amount for step 0");

        // Validate second step
        assertEq(steps[1].from, 0, "Expected from for step 1");
        assertEq(steps[1].to, 2, "Expected to for step 1");
        assertEq(steps[1].amount, 1 * INITIAL_BALANCE / 10, "Expected amount for step 1");
    }

    function test_Rebalance_ExampleThree() public {
        setData(0.5e18, 0.2e18, 0.3e18);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2, "Expected 2 steps");

        // Validate first step
        assertEq(steps[0].from, 0, "Expected from for step 0");
        assertEq(steps[0].to, 1, "Expected to for step 0");
        assertEq(steps[0].amount, 2 * INITIAL_BALANCE / 10, "Expected amount for step 0");

        // Validate second step
        assertEq(steps[1].from, 0, "Expected from for step 1");
        assertEq(steps[1].to, 2, "Expected to for step 1");
        assertEq(steps[1].amount, 3 * INITIAL_BALANCE / 10, "Expected amount for step 1");
    }

    function test_SetDataFailsForMismatchedArrayLengths() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](2);

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(maxVault);
        vaults[1] = address(2);

        vm.expectRevert("Array lengths must match");
        baseKeeper.setData(finalRatios, vaults);
    }

    function test_SetDataFailsForInvalidRatios() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);
        uint256 ratio1 = 0.5e17;
        uint256 ratio2 = 0.25e17;
        uint256 ratio3 = 0.25e17;

        vaults[0] = address(maxVault);
        vaults[1] = address(underlyingVault1);
        vaults[2] = address(underlyingVault2);

        finalRatios[0] = ratio1;
        finalRatios[1] = ratio2;
        finalRatios[2] = ratio3;

        vm.expectRevert("Initial and target ratios must match");
        baseKeeper.setData(finalRatios, vaults);
    }

    function test_CalculateCurrentRatio() public {
        setData(0.5e18, 0.25e18, 0.25e18);

        uint256 currentRatio = baseKeeper.calculateCurrentRatio(address(maxVault), maxVault.totalAssets());
        assertEq(currentRatio, 1e18);
    }

    function test_ShouldRebalance() public {
        setData(0.5e18, 0.25e18, 0.25e18);
        bool shouldRebalance = baseKeeper.shouldRebalance();
        assertEq(shouldRebalance, true);

        setData(1e18, 0, 0);
        shouldRebalance = baseKeeper.shouldRebalance();
        assertEq(shouldRebalance, false);
    }

    function setData(uint256 ratio1, uint256 ratio2, uint256 ratio3) public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        vaults[0] = address(maxVault);
        vaults[1] = address(underlyingVault1);
        vaults[2] = address(underlyingVault2);

        finalRatios[0] = ratio1;
        finalRatios[1] = ratio2;
        finalRatios[2] = ratio3;

        baseKeeper.setData(finalRatios, vaults);

        assertEq(baseKeeper.targetRatios(0), ratio1, "Target ratio 0 incorrect");
        assertEq(baseKeeper.targetRatios(1), ratio2, "Target ratio 1 incorrect");
        assertEq(baseKeeper.targetRatios(2), ratio3, "Target ratio 2 incorrect");
    }
}
