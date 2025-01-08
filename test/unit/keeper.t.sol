// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";

import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";

import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";
import {IVault, SetupVault, Vault, WETH9} from "lib/yieldnest-vault/test/unit/helpers/SetupVault.sol";
import {BaseKeeper} from "src/BaseKeeper.sol";

contract BaseKeeperTest is Test, MainnetActors, VaultUtils {
    BaseKeeper public keeper;
    Vault public maxVault;
    Vault[] public underlyingVaults;
    WETH9 public weth;
    uint256 public length;

    uint256 public constant INITIAL_BALANCE = 10 ether;

    address public alice = address(0xa11ce);

    function _vaults() internal view returns (address[] memory vaults) {
        vaults = new address[](underlyingVaults.length + 1);
        vaults[0] = address(maxVault);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            vaults[i + 1] = address(underlyingVaults[i]);
        }
    }

    function _underlyingVaults() internal view returns (address[] memory vaults) {
        vaults = new address[](underlyingVaults.length);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            vaults[i] = address(underlyingVaults[i]);
        }
    }

    function setUp() public {
        keeper = new BaseKeeper();

        SetupVault setupVault = new SetupVault();
        (maxVault, weth) = setupVault.setup();
        (Vault underlyingVault1,) = setupVault.setup();
        (Vault underlyingVault2,) = setupVault.setup();
        (Vault underlyingVault3,) = setupVault.setup();

        underlyingVaults.push(underlyingVault1);
        underlyingVaults.push(underlyingVault2);
        underlyingVaults.push(underlyingVault3);

        length = underlyingVaults.length + 1;

        vm.startPrank(ADMIN);
        maxVault.grantRole(maxVault.PROCESSOR_ROLE(), address(keeper));
        vm.stopPrank();

        vm.startPrank(ASSET_MANAGER);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            maxVault.addAsset(address(underlyingVaults[i]), false);
        }
        vm.stopPrank();

        // set rules for maxVault
        vm.startPrank(PROCESSOR_MANAGER);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            setDepositRule(maxVault, address(underlyingVaults[i]));
        }

        setApprovalRule(maxVault, address(weth), _underlyingVaults());

        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            setWithdrawRule(maxVault, address(underlyingVaults[i]));
        }

        // set rules for underlyingVaults
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            setDepositRule(underlyingVaults[i], MC.BUFFER);
            setApprovalRule(underlyingVaults[i], address(weth), MC.BUFFER);
        }

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
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            vm.label(address(underlyingVaults[i]), string.concat("Underlying Vault ", vm.toString(i)));
        }
        vm.label(address(keeper), "BaseKeeper");
    }

    function test_ViewFunctions() public view {
        assertEq(maxVault.totalAssets(), INITIAL_BALANCE);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            assertEq(underlyingVaults[i].totalAssets(), 0);
        }
        assertEq(weth.balanceOf(address(maxVault)), INITIAL_BALANCE);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            assertEq(weth.balanceOf(address(underlyingVaults[i])), 0);
        }
    }

    function test_SetData() public {
        uint256[] memory finalRatios = new uint256[](length);
        finalRatios[0] = 40 * 1e16;
        finalRatios[1] = 40 * 1e16;
        finalRatios[2] = 10 * 1e16;
        finalRatios[3] = 10 * 1e16;
        assertEq(finalRatios[0] + finalRatios[1] + finalRatios[2] + finalRatios[3], 1e18);

        keeper.setData(finalRatios, _vaults());

        uint256[] memory initialRatios = keeper.currentRatios();
        uint256[] memory targetRatios = keeper.finalRatios();

        assertEq(initialRatios.length, length);
        assertEq(targetRatios.length, length);

        assertEq(initialRatios[0], 1e18);
        for (uint256 i = 0; i < length; i++) {
            assertEq(targetRatios[i], finalRatios[i]);
            assertEq(keeper.vaults(i), _vaults()[i]);
        }
    }

    function test_CalculateTransfers_ExampleOne() public {
        _setData(0.5e18, 0.25e18, 0.25e18);

        (BaseKeeper.Withdraw[] memory withdraws, BaseKeeper.Deposit[] memory deposits) = keeper.calculateTransfers();

        assertEq(withdraws.length, 0, "Expected 0 withdraws");
        assertEq(deposits.length, 2, "Expected 2 deposits");

        // Validate first deposit
        assertEq(deposits[0].to, 1, "Expected to for deposit 0");
        assertEq(deposits[0].amount, INITIAL_BALANCE / 4, "Expected amount for deposit 0");

        // Validate second deposit
        assertEq(deposits[1].to, 2, "Expected to for deposit 1");
        assertEq(deposits[1].amount, INITIAL_BALANCE / 4, "Expected amount for deposit 1");
    }

    function test_Rebalance_ExampleOne() public {
        _testRebalance(0.5e18, 0.25e18, 0.25e18);
    }

    function test_CalculateTransfers_ExampleTwo() public {
        _setData(0.5e18, 0.4e18, 0.1e18);

        (BaseKeeper.Withdraw[] memory withdraws, BaseKeeper.Deposit[] memory deposits) = keeper.calculateTransfers();

        assertEq(withdraws.length, 0, "Expected 0 withdraws");
        assertEq(deposits.length, 2, "Expected 2 deposits");

        // Validate first deposit
        assertEq(deposits[0].to, 1, "Expected to for deposit 0");
        assertEq(deposits[0].amount, 4 * INITIAL_BALANCE / 10, "Expected amount for deposit 0");

        // Validate second deposit
        assertEq(deposits[1].to, 2, "Expected to for deposit 1");
        assertEq(deposits[1].amount, 1 * INITIAL_BALANCE / 10, "Expected amount for deposit 1");
    }

    function test_Rebalance_ExampleTwo() public {
        _testRebalance(0.5e18, 0.4e18, 0.1e18);
    }

    function test_CalculateTransfers_ExampleThree() public {
        _setData(0.5e18, 0.2e18, 0.3e18);

        (BaseKeeper.Withdraw[] memory withdraws, BaseKeeper.Deposit[] memory deposits) = keeper.calculateTransfers();

        assertEq(withdraws.length, 0, "Expected 0 withdraws");
        assertEq(deposits.length, 2, "Expected 2 deposits");

        // Validate first deposit
        assertEq(deposits[0].to, 1, "Expected to for deposit 0");
        assertEq(deposits[0].amount, 2 * INITIAL_BALANCE / 10, "Expected amount for deposit 0");

        // Validate second deposit
        assertEq(deposits[1].to, 2, "Expected to for deposit 1");
        assertEq(deposits[1].amount, 3 * INITIAL_BALANCE / 10, "Expected amount for deposit 1");
    }

    function test_Rebalance_ExampleThree() public {
        _testRebalance(0.5e18, 0.2e18, 0.3e18);
    }

    function test_Rebalance_TwoTimes() public {
        _testRebalance(0.5e18, 0.2e18, 0.3e18);

        _setData(0.5e18, 0.4e18, 0.1e18);

        uint256[] memory currentRatios = keeper.currentRatios();
        uint256[] memory finalRatios = keeper.finalRatios();

        assertEq(currentRatios[0], 0.5e18);
        assertEq(currentRatios[1], 0.2e18);
        assertEq(currentRatios[2], 0.3e18);

        assertEq(finalRatios[0], 0.5e18);
        assertEq(finalRatios[1], 0.4e18);
        assertEq(finalRatios[2], 0.1e18);

        (BaseKeeper.Withdraw[] memory withdraws, BaseKeeper.Deposit[] memory deposits) = keeper.calculateTransfers();

        assertEq(withdraws.length, 1, "Expected 1 withdraws");
        assertEq(deposits.length, 1, "Expected 1 deposits");

        // Validate first deposit
        assertEq(deposits[0].to, 1, "Expected to for deposit 0");
        assertEq(deposits[0].amount, 2 * INITIAL_BALANCE / 10, "Expected amount for deposit 0");

        assertEq(withdraws[0].from, 2, "Expected from for withdraw 0");
        assertEq(withdraws[0].amount, 2 * INITIAL_BALANCE / 10, "Expected amount for withdraw 0");

        _allocateBalanceToBuffer(underlyingVaults[0]);
        _allocateBalanceToBuffer(underlyingVaults[1]);

        _rebalanceAndValidate();
    }

    function test_Rebalance_MultipleTimes() public {
        _testRebalance(0.5e18, 0.2e18, 0.3e18);

        _testRebalance(0.5e18, 0.4e18, 0.1e18);

        _testRebalance(0.5e18, 0.2e18, 0.3e18);

        _testRebalance(0, 1e18, 0);

        _testRebalance(0, 0, 1e18);

        _testRebalance(1e18, 0, 0);
    }

    function test_Rebalance_WithThreeUnderlyingVaults() public {
        _testRebalance(0.5e18, 0.25e18, 0.1e18, 0.15e18);

        _testRebalance(0.5e18, 0.25e18, 0, 0.25e18);

        _testRebalance(0, 0.9e18, 0.1e18, 0);

        _testRebalance(0.35e18, 0.4e18, 0.25e18, 0);

        _testRebalance(0, 0.25e18, 0.25e18, 0.5e18);
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
        keeper.setData(finalRatios, vaults);
    }

    function test_SetDataFailsForInvalidRatios() public {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);
        uint256 ratio1 = 0.5e17;
        uint256 ratio2 = 0.25e17;
        uint256 ratio3 = 0.25e17;

        vaults[0] = address(maxVault);
        vaults[1] = address(underlyingVaults[0]);
        vaults[2] = address(underlyingVaults[1]);

        finalRatios[0] = ratio1;
        finalRatios[1] = ratio2;
        finalRatios[2] = ratio3;

        vm.expectRevert("Target ratios must add up to 100 %");
        keeper.setData(finalRatios, vaults);
    }

    function test_CalculateCurrentRatio() public {
        _setData(0.5e18, 0.25e18, 0.25e18);

        uint256 currentRatio = keeper.calculateCurrentRatio(address(maxVault), maxVault.totalAssets());
        assertEq(currentRatio, 1e18);
    }

    function test_ShouldRebalance() public {
        _setData(0.5e18, 0.25e18, 0.25e18);
        bool shouldRebalance = keeper.shouldRebalance();
        assertEq(shouldRebalance, true);

        _setData(1e18, 0, 0);
        shouldRebalance = keeper.shouldRebalance();
        assertEq(shouldRebalance, false);
    }

    function _testRebalance(uint256 ratio1, uint256 ratio2, uint256 ratio3) public {
        _setData(ratio1, ratio2, ratio3);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            _allocateBalanceToBuffer(underlyingVaults[i]);
        }
        _rebalanceAndValidate(3);
    }

    function _testRebalance(uint256 ratio1, uint256 ratio2, uint256 ratio3, uint256 ratio4) public {
        _setData(ratio1, ratio2, ratio3, ratio4);
        for (uint256 i = 0; i < underlyingVaults.length; i++) {
            _allocateBalanceToBuffer(underlyingVaults[i]);
        }
        _rebalanceAndValidate(4);
    }

    function _setData(uint256 ratio1, uint256 ratio2, uint256 ratio3) internal {
        uint256[] memory finalRatios = new uint256[](3);
        address[] memory vaults = new address[](3);

        vaults[0] = address(maxVault);
        vaults[1] = address(underlyingVaults[0]);
        vaults[2] = address(underlyingVaults[1]);

        finalRatios[0] = ratio1;
        finalRatios[1] = ratio2;
        finalRatios[2] = ratio3;

        keeper.setData(finalRatios, vaults);

        uint256[] memory targetRatios = keeper.finalRatios();

        assertEq(targetRatios[0], ratio1, "Target ratio 0 incorrect");
        assertEq(targetRatios[1], ratio2, "Target ratio 1 incorrect");
        assertEq(targetRatios[2], ratio3, "Target ratio 2 incorrect");
    }

    function _setData(uint256 ratio1, uint256 ratio2, uint256 ratio3, uint256 ratio4) internal {
        uint256[] memory finalRatios = new uint256[](4);
        finalRatios[0] = ratio1;
        finalRatios[1] = ratio2;
        finalRatios[2] = ratio3;
        finalRatios[3] = ratio4;
        assertEq(finalRatios[0] + finalRatios[1] + finalRatios[2] + finalRatios[3], 1e18);

        keeper.setData(finalRatios, _vaults());

        uint256[] memory targetRatios = keeper.finalRatios();

        assertEq(targetRatios[0], ratio1, "Target ratio 0 incorrect");
        assertEq(targetRatios[1], ratio2, "Target ratio 1 incorrect");
        assertEq(targetRatios[2], ratio3, "Target ratio 2 incorrect");
        assertEq(targetRatios[3], ratio4, "Target ratio 3 incorrect");
    }

    function _rebalanceAndValidate() internal {
        _rebalanceAndValidate(3);
    }

    function _rebalanceAndValidate(uint256 _length) internal {
        keeper.rebalance();

        uint256[] memory initialRatios = keeper.currentRatios();
        uint256[] memory targetRatios = keeper.finalRatios();

        assertEq(initialRatios.length, _length);
        assertEq(targetRatios.length, _length);

        for (uint256 i = 0; i < _length; i++) {
            assertEq(initialRatios[i], targetRatios[i], "Expected initial ratios to match target ratios");
        }
    }

    function _allocateBalanceToBuffer(IVault vault) internal {
        uint256 balance = weth.balanceOf(address(vault));
        _allocateToBuffer(vault, balance);
    }

    function _allocateToBuffer(IVault vault, uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }
}
