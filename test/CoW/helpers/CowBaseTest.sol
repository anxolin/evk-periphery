// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {GPv2Signing} from "cow/mixins/GPv2Signing.sol";
import {GPv2Order} from "cow/libraries/GPv2Order.sol";
import {GPv2Trade, IERC20} from "cow/libraries/GPv2Trade.sol";

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";

import {CowEvcWrapper} from "../../../src/CoW/CowEvcWrapper.sol";
import {AllowListAuthentication} from "../../../src/CoW/vendor/AllowListAuthentication.sol";
import {CowSettlement, GPv2Trade} from "../../../src/CoW/vendor/CowSettlement.sol";

import {MilkSwap} from "./MilkSwap.sol";
import {GPv2OrderHelper} from "./GPv2OrderHelper.sol";

import {console} from "forge-std/Test.sol";

contract CowBaseTest is EVaultTestBase {
    uint256 mainnetFork;
    uint256 BLOCK_NUMBER = 22546006;
    string FORK_RPC_URL = vm.envOr("FORK_RPC_URL", string(""));

    address constant solver = 0x7E2eF26AdccB02e57258784957922AEEFEe807e5; // quasilabs
    address constant allowListManager = 0xA03be496e67Ec29bC62F01a428683D7F9c204930;

    address constant DAI = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    CowSettlement constant cowSettlement = CowSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);

    CowEvcWrapper public wrapper;
    MilkSwap public milkSwap;
    address user;

    GPv2OrderHelper helper;

    function setUp() public virtual override {
        super.setUp();
        helper = new GPv2OrderHelper();

        if (bytes(FORK_RPC_URL).length != 0) {
            mainnetFork = vm.createSelectFork(FORK_RPC_URL);
            vm.rollFork(BLOCK_NUMBER);
        }

        user = makeAddr("user");
        wrapper = new CowEvcWrapper(address(evc), address(cowSettlement));

        // Add wrapper as solver
        AllowListAuthentication allowList = cowSettlement.authenticator();
        address manager = allowList.manager();
        // vm.deal(address(manager), 1e18);
        vm.prank(manager);
        allowList.addSolver(address(wrapper));

        // Setup some liquidity for MilkSwap
        milkSwap = new MilkSwap(DAI);
        deal(DAI, address(milkSwap), 10000e18); // Add DAI to MilkSwap
        milkSwap.setPrice(WETH, 1000); // 1 ETH = 1,000 DAI

        // Set the approval for MilSwap in the settlement
        vm.prank(address(cowSettlement));
        IERC20(WETH).approve(address(milkSwap), type(uint256).max);

        // User has approved WETH for COW Protocol
        address vaultRelayer = cowSettlement.vaultRelayer();
        vm.prank(user);
        IERC20(WETH).approve(vaultRelayer, type(uint256).max);

        // Setup labels
        vm.label(solver, "solver");
        vm.label(allowListManager, "allowListManager");
        vm.label(user, "user");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(address(cowSettlement), "cowSettlement");
        vm.label(address(wrapper), "wrapper");
        vm.label(address(milkSwap), "milkSwap");
    }

    function getEmptySettlement()
        public
        pure
        returns (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        )
    {
        return (
            new address[](0),
            new uint256[](0),
            new GPv2Trade.Data[](0),
            [
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0)
            ]
        );
    }

    function getOrderUid(address owner, GPv2Order.Data memory orderData) public view returns (bytes memory orderUid) {
        // Generate order digest using EIP-712
        bytes32 orderDigest = GPv2Order.hash(orderData, cowSettlement.domainSeparator());

        // Create order UID by concatenating orderDigest, owner, and validTo
        return abi.encodePacked(orderDigest, address(owner), uint32(orderData.validTo));
    }

    function getSwapInteraction(uint256 sellAmount) public view returns (CowSettlement.InteractionData memory) {
        return CowSettlement.InteractionData({
            to: address(milkSwap),
            value: 0,
            callData: abi.encodeCall(MilkSwap.swap, (WETH, DAI, sellAmount))
        });
    }

    function getTradeData(uint256 sellAmount, uint256 buyAmount, uint32 validTo, address owner, address receiver)
        public
        pure
        returns (GPv2Trade.Data memory)
    {
        // Set flags for (pre-sign, FoK sell order)
        // See
        // https://github.com/cowprotocol/contracts/blob/08f8627d8427c8842ae5d29ed8b44519f7674879/src/contracts/libraries/GPv2Trade.sol#L89-L94
        uint256 flags = 3 << 5; // 1100000

        return GPv2Trade.Data({
            sellTokenIndex: 0,
            buyTokenIndex: 1,
            receiver: receiver,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: bytes32(0),
            feeAmount: 0,
            flags: flags,
            executedAmount: 0,
            signature: abi.encodePacked(owner)
        });
    }

    function getTokensAndPrices() public pure returns (address[] memory tokens, uint256[] memory clearingPrices) {
        tokens = new address[](2);
        tokens[0] = WETH;
        tokens[1] = DAI;

        clearingPrices = new uint256[](2);
        clearingPrices[0] = 1000; // WETH price
        clearingPrices[1] = 1; // DAI price
    }

    function getSwapSettlement(address owner, uint256 sellAmount, uint256 buyAmount)
        public
        view
        returns (
            bytes memory orderUid,
            GPv2Order.Data memory orderData,
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        )
    {
        uint32 validTo = uint32(block.timestamp + 1 hours);

        // Create order data
        orderData = GPv2Order.Data({
            sellToken: IERC20(WETH),
            buyToken: IERC20(DAI),
            receiver: owner,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: bytes32(0),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        // Get order UID for the order
        orderUid = getOrderUid(owner, orderData);

        // Get trade data
        trades = new GPv2Trade.Data[](1);
        trades[0] = getTradeData(sellAmount, buyAmount, validTo, owner, orderData.receiver);

        // Get tokens and prices
        (tokens, clearingPrices) = getTokensAndPrices();

        // Setup interactions
        interactions = [
            new CowSettlement.InteractionData[](0),
            new CowSettlement.InteractionData[](1),
            new CowSettlement.InteractionData[](0)
        ];
        interactions[1][0] = getSwapInteraction(sellAmount);

        return (orderUid, orderData, tokens, clearingPrices, trades, interactions);
    }
}
