// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {IEVault, IERC4626, IERC20} from "lib/euler-vault-kit/src/EVault/IEVault.sol";

import {ISwapper} from "../../src/Swaps/ISwapper.sol";
import {Swapper} from "../../src/Swaps/Swapper.sol";
import {SwapVerifier} from "../../src/Swaps/SwapVerifier.sol";

import {CowSettlement, GPv2Trade} from "../../src/CoW/vendor/CowSettlement.sol";

import {console} from "forge-std/Test.sol";

/// @notice A minimal storage contract anyone can modify
contract MutableStorage {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

contract EvcWrapper {
    IEVC public evc;
    uint256 public value;

    constructor(address _evc) {
        evc = IEVC(_evc);
    }

    function batch(IEVC.BatchItem[] calldata items) public payable {
        evc.batch(items);
    }

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

/// @notice The tests operate on a fork. Create a .env file with FORK_RPC_URL as per fondry docs
contract CowEvcExperimentsTest is EVaultTestBase {
    struct SettlementData {
        address[] tokens;
        uint256[] clearingPrices;
        GPv2Trade.Data[] trades;
        CowSettlement.InteractionData[][3] interactions;
    }

    uint256 mainnetFork;

    uint256 BLOCK_NUMBER = 22546006;

    address constant GRT = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address constant solver = 0x7E2eF26AdccB02e57258784957922AEEFEe807e5; // quasilabs
    CowSettlement constant cowSettlement = CowSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
    EvcWrapper evcWrapper;

    string FORK_RPC_URL = vm.envOr("FORK_RPC_URL", string(""));

    address user;
    address user2;

    IEVault eGRT;
    IEVault eUSDC;
    IEVault eSTETH;
    IEVault eUSDT;

    // SettlementData emptySettlement;

    // Reference to our mutable storage contract
    MutableStorage public mutableStorage;

    function setUp() public virtual override {
        super.setUp();

        user = makeAddr("user");
        user2 = makeAddr("user2");

        // Deploy the MutableStorage contract
        mutableStorage = new MutableStorage();

        evcWrapper = new EvcWrapper(address(evc));

        if (bytes(FORK_RPC_URL).length != 0) {
            mainnetFork = vm.createSelectFork(FORK_RPC_URL);
        }
    }

    function getEmptySettlement() public pure returns (SettlementData memory) {
        return SettlementData({
            tokens: new address[](0),
            clearingPrices: new uint256[](0),
            trades: new GPv2Trade.Data[](0),
            interactions: [
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0)
            ]
        });
    }

    function setupFork(uint256 blockNumber, bool forBorrow) internal {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        vm.rollFork(blockNumber);

        eGRT = IEVault(factory.createProxy(address(0), true, abi.encodePacked(GRT, address(oracle), unitOfAccount)));
        eUSDC = IEVault(factory.createProxy(address(0), true, abi.encodePacked(USDC, address(oracle), unitOfAccount)));
        eSTETH = IEVault(factory.createProxy(address(0), true, abi.encodePacked(STETH, address(oracle), unitOfAccount)));
        eUSDT = IEVault(factory.createProxy(address(0), true, abi.encodePacked(USDT, address(oracle), unitOfAccount)));

        eGRT.setHookConfig(address(0), 0);
        eUSDC.setHookConfig(address(0), 0);
        eSTETH.setHookConfig(address(0), 0);
        eUSDT.setHookConfig(address(0), 0);

        if (forBorrow) {
            eUSDC.setLTV(address(eGRT), 0.97e4, 0.97e4, 0);
            eSTETH.setLTV(address(eUSDT), 0.97e4, 0.97e4, 0);

            oracle.setPrice(address(USDC), unitOfAccount, 1e18);
            oracle.setPrice(address(GRT), unitOfAccount, 1e18);
            oracle.setPrice(address(STETH), unitOfAccount, 1e18);
            oracle.setPrice(address(USDT), unitOfAccount, 1e30);

            startHoax(user2);

            deal(USDC, user2, 100_000e6);
            IERC20(USDC).approve(address(eUSDC), type(uint256).max);
            eUSDC.deposit(type(uint256).max, user2);

            bytes32 slot = keccak256(abi.encode(user2, 0)); // stEth balances are at slot 0
            vm.store(STETH, slot, bytes32(uint256(100_000e18)));
            IERC20(STETH).approve(address(eSTETH), type(uint256).max);
            eSTETH.deposit(type(uint256).max, user2);

            startHoax(user);

            evc.enableCollateral(user, address(eGRT));
            evc.enableCollateral(user, address(eUSDT));
        }

        startHoax(user);

        deal(GRT, user, 100_000e18);
        IERC20(GRT).approve(address(eGRT), type(uint256).max);
        eGRT.deposit(type(uint256).max, user);

        deal(USDT, user, 100_000e6);
        // USDT returns void
        (bool success,) = USDT.call(abi.encodeCall(IERC20.approve, (address(eUSDT), type(uint256).max)));
        if (!success) revert("USDT approval");
        eUSDT.deposit(type(uint256).max, user);
    }

    function test_solverCanSettleOutsideEVC() external {
        setupFork(BLOCK_NUMBER, false);
        vm.startPrank(solver);

        console.log("solver", msg.sender);

        SettlementData memory emptySettlement = getEmptySettlement();
        cowSettlement.settle(
            emptySettlement.tokens, emptySettlement.clearingPrices, emptySettlement.trades, emptySettlement.interactions
        );
    }

    function test_solverCanExecuteEmptyEvcBatch() external {
        setupFork(BLOCK_NUMBER, false);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](0);
        evc.batch(items);
    }

    function test_solverCantWriteToStorageInsideEVC() external {
        setupFork(BLOCK_NUMBER, false);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: solver,
            targetContract: address(mutableStorage),
            value: 0,
            data: abi.encodeCall(MutableStorage.setValue, (123))
        });

        vm.expectRevert(abi.encodeWithSignature("EVC_NotAuthorized()"));
        evc.batch(items);
    }

    function test_solverCanWriteUsingEvcWrapper() external {
        setupFork(BLOCK_NUMBER, false);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: solver,
            targetContract: address(evcWrapper),
            value: 0,
            data: abi.encodeCall(EvcWrapper.setValue, (123))
        });

        evcWrapper.batch(items);

        assertEq(evcWrapper.value(), 123);
    }

    function test_solverCantSettleInsideEVC() external {
        setupFork(BLOCK_NUMBER, false);

        SettlementData memory emptySettlement = getEmptySettlement();

        bytes memory emptySettlementData = abi.encodeCall(
            CowSettlement.settle,
            (
                emptySettlement.tokens,
                emptySettlement.clearingPrices,
                emptySettlement.trades,
                emptySettlement.interactions
            )
        );

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: solver,
            targetContract: address(cowSettlement),
            value: 0,
            data: emptySettlementData
        });

        vm.expectRevert(abi.encodeWithSignature("EVC_NotAuthorized()"));
        evc.batch(items);
    }

    // // Simple test to verify mutable storage works
    // function test_mutableStorage() external {
    //     storage.setValue(123);
    //     assertEq(storage.value(), 123);

    //     vm.startPrank(user);
    //     storage.setValue(456);
    //     assertEq(storage.value(), 456);
    //     vm.stopPrank();
    // }
}
