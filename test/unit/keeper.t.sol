// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/yieldnest-vault/lib/forge-std/src/Test.sol";

import {ERC20} from "lib/yieldnest-vault/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MainnetContracts} from "lib/yieldnest-vault/script/Contracts.sol";
import {SetupVault, Vault, WETH9} from "lib/yieldnest-vault/test/unit/helpers/SetupVault.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {BaseKeeper} from "src/BaseKeeper.sol";

contract BaseKeeperTest is Test {
    BaseKeeper public baseKeeper;
    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;
    ERC20 public meth;

    uint256 public INITIAL_BALANCE = 10 ether;

    address public alice = address(0xa11ce);

    function setUp() public {
        baseKeeper = new BaseKeeper();
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();
        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MainnetContracts.STETH));
        meth = ERC20(payable(MainnetContracts.METH));

        // Give Alice some tokens
        deal(address(steth), alice, INITIAL_BALANCE);
        deal(address(meth), alice, INITIAL_BALANCE);
        deal(alice, INITIAL_BALANCE);

        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        vm.startPrank(alice);

        steth.approve(address(vault), INITIAL_BALANCE);
        weth.approve(address(vault), type(uint256).max);
        meth.approve(address(vault), type(uint256).max);
        vault.depositAsset(address(steth), INITIAL_BALANCE, alice);
        vault.depositAsset(address(weth), INITIAL_BALANCE, alice);
        vault.depositAsset(address(meth), INITIAL_BALANCE, alice);
        vm.stopPrank();

        vm.label(address(weth), "WETH");
        vm.label(address(steth), "STETH");
        vm.label(address(meth), "METH");
        vm.label(address(vault), "Vault");
        vm.label(address(baseKeeper), "BaseKeeper");
    }

    function test_SetData() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(vault);
        vaults[1] = address(2);
        vaults[2] = address(3);

        baseKeeper.setData(finalRatios, vaults);

        assertEq(baseKeeper.targetRatios(1), 40);
        assertEq(baseKeeper.vaults(2), address(3));
    }

    function test_TotalFinalRatios() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        finalRatios[0] = 50;
        finalRatios[1] = 25;
        finalRatios[2] = 25;

        vaults[0] = address(vault);
        vaults[1] = address(weth);
        vaults[2] = address(steth);

        baseKeeper.setData(finalRatios, vaults);

        assertEq(baseKeeper.totalTargetRatios(), 100);
    }

    function test_Rebalance_ExampleOne() public {
        setData(0.5e18, 0.25e18, 0.25e18);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2, "Expected 2 steps");

        // Validate first step
        assertEq(steps[0].from, 1, "Expected from 1");
        assertEq(steps[0].to, 0, "Expected to 0");
        assertEq(steps[0].amount, 4e18, "Expected amount 4e18");
    }

    function test_Rebalance_ExampleTwo() public {
        setData(0.5e18, 0.4e18, 0.1e18);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2);

        // Validate first step
        assertEq(steps[0].from, 2, "Step 0: Expected from 2");
        assertEq(steps[0].to, 0, "Step 0: Expected to 0");
        assertEq(steps[0].amount, 6000000000000000000, "Step 0: Expected amount 6000000000000000000");

        // Validate second step
        assertEq(steps[1].from, 2, "Step 1: Expected from 0");
        assertEq(steps[1].to, 1, "Step 1: Expected to 1");
        assertEq(steps[1].amount, 800000000000000000, "Step 1: Expected amount 800000000000000000");
    }

    function test_Rebalance_ExampleThree() public {
        setData(0.5e18, 0.2e18, 0.3e18);

        BaseKeeper.Transfer[] memory steps = baseKeeper.rebalance();

        assertEq(steps.length, 2, "Expected 2 steps");

        // Validate first step
        assertEq(steps[0].from, 1, "Step 0: Expected from 1");
        assertEq(steps[0].to, 0, "Step 0: Expected to 2");
        assertEq(steps[0].amount, 5600000000000000000, "Step 0: Expected amount 5600000000000000000");

        // Validate second step
        assertEq(steps[1].from, 2, "Step 2: Expected from 1");
        assertEq(steps[1].to, 0, "Step 1: Expected to 2");
        assertEq(steps[1].amount, 400000000000000000, "Step 1: Expected amount 400000000000000000");
    }

    function test_SetDataFailsForMismatchedArrayLengths() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](2);

        finalRatios[0] = 40;
        finalRatios[1] = 40;
        finalRatios[2] = 20;

        vaults[0] = address(vault);
        vaults[1] = address(2);

        vm.expectRevert("Array lengths must match");
        baseKeeper.setData(finalRatios, vaults);
    }

    function test_RebalanceFailsForUnmatchedRatios() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        finalRatios[0] = 50;
        finalRatios[1] = 30;
        finalRatios[2] = 10;

        vaults[0] = address(vault);
        vaults[1] = address(weth);
        vaults[2] = address(steth);

        baseKeeper.setData(finalRatios, vaults);

        vm.expectRevert("Ratios must add up");
        baseKeeper.rebalance();
    }

    function test_SetMaxVault_Revert_notAVault() public {
        setData(50, 25, 25);
        vm.expectRevert();
        baseKeeper.setMaxVault(address(1));
    }

    function test_CalculateCurrentRatio() public {
        setData(50, 25, 25);
        uint256 currentRatio = baseKeeper.calculateCurrentRatio(address(weth), vault.totalAssets());
        assertEq(currentRatio, 312500000000000000);
    }

    function test_ShouldRebalance() public {
        setData(50, 25, 25);
        bool shouldRebalance = baseKeeper.shouldRebalance();
        assertEq(shouldRebalance, true);

        setData(0.3125e18, 0.375e18, 0.3125e18);
        shouldRebalance = baseKeeper.shouldRebalance();
        assertEq(shouldRebalance, false);
    }

    function setData(uint256 ratio1, uint256 ratio2, uint256 ratio3) public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        vaults[0] = address(vault);
        vaults[1] = address(meth);
        vaults[2] = address(steth);

        finalRatios[0] = ratio1;
        finalRatios[1] = ratio2;
        finalRatios[2] = ratio3;

        baseKeeper.setData(finalRatios, vaults);

        assertEq(baseKeeper.targetRatios(0), ratio1, "Target ratio 0 incorrect");
        assertEq(baseKeeper.targetRatios(1), ratio2, "Target ratio 1 incorrect");
        assertEq(baseKeeper.targetRatios(2), ratio3, "Target ratio 2 incorrect");
    }
}
