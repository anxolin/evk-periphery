// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {IEVault, IERC4626, IERC20} from "lib/euler-vault-kit/src/EVault/IEVault.sol";

import {CowSettlement} from "../../src/CoW/vendor/CowSettlement.sol";
import {CowEvcWrapper} from "../../src/CoW/CowEvcWrapper.sol";
import {AllowListAuthentication} from "../../src/CoW/vendor/AllowListAuthentication.sol";
import {CowOrder} from "../../src/CoW/library/CowOrder.sol";

import {console} from "forge-std/Test.sol";

contract CowEvcWrapperTest is EVaultTestBase {
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

    function setUp() public virtual override {
        super.setUp();

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
        vm.startPrank(manager);
        allowList.addSolver(address(wrapper));
        vm.stopPrank();

        // Setup some liquidity for MilkSwap
        milkSwap = new MilkSwap();
        deal(DAI, address(milkSwap), 10000e18); // Add DAI to MilkSwap
        milkSwap.setPrice(WETH, 1000); // 1 ETH = 1,000 DAI

        // Set the approval for MilSwap in the settlement
        vm.startPrank(address(cowSettlement));
        IERC20(DAI).approve(address(milkSwap), type(uint256).max);
        IERC20(WETH).approve(address(milkSwap), type(uint256).max);

        // User has approved WETH for COW Protocol
        vm.startPrank(user);
        IERC20(WETH).approve(address(cowSettlement.vaultRelayer()), type(uint256).max);
        vm.stopPrank();

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
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        )
    {
        return (
            new address[](0),
            new uint256[](0),
            new CowSettlement.TradeData[](0),
            [
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0)
            ]
        );
    }

    function getOrderUid(CowSettlement.OrderData memory orderData) public view returns (bytes memory orderUid) {
        // Generate order digest using EIP-712
        bytes32 orderDigest = CowOrder.hash(orderData, cowSettlement.domainSeparator());

        // Create order UID by concatenating orderDigest, owner, and validTo
        return abi.encodePacked(orderDigest, address(cowSettlement), uint32(orderData.validTo));
    }

    function getSwapInteraction(uint256 sellAmount) public view returns (CowSettlement.InteractionData memory) {
        return CowSettlement.InteractionData({
            to: address(milkSwap),
            value: 0,
            callData: abi.encodeCall(MilkSwap.swap, (WETH, DAI, sellAmount))
        });
    }

    function getTradeData(uint256 sellAmount, uint256 buyAmount, uint32 validTo, address receiver)
        public
        pure
        returns (CowSettlement.TradeData memory)
    {
        // Set flags for (pre-sign, FoK sell order)
        // See
        // https://github.com/cowprotocol/contracts/blob/08f8627d8427c8842ae5d29ed8b44519f7674879/src/contracts/libraries/GPv2Trade.sol#L89-L94
        uint256 flags = 3 << 5; // 1100000

        return CowSettlement.TradeData({
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
            signature: abi.encodePacked(receiver)
        });
    }

    function getTokensAndPrices() public pure returns (address[] memory tokens, uint256[] memory clearingPrices) {
        tokens = new address[](2);
        tokens[0] = WETH;
        tokens[1] = DAI;

        clearingPrices = new uint256[](2);
        clearingPrices[0] = 1e18; // WETH price
        clearingPrices[1] = 1e18; // DAI price
    }

    function getSwapSettlement(uint256 sellAmount, uint256 buyAmount)
        public
        view
        returns (
            bytes memory orderUid,
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        )
    {
        uint32 validTo = uint32(block.timestamp + 1 hours);

        // Create order data
        CowSettlement.OrderData memory orderData = CowSettlement.OrderData({
            sellToken: WETH,
            buyToken: DAI,
            receiver: user,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: bytes32(0),
            feeAmount: 0,
            kind: bytes32("sell"),
            partiallyFillable: false,
            sellTokenBalance: bytes32("erc20"),
            buyTokenBalance: bytes32("erc20")
        });

        // Get order UID for the order
        orderUid = getOrderUid(orderData);

        // Get trade data
        trades = new CowSettlement.TradeData[](1);
        trades[0] = getTradeData(sellAmount, buyAmount, validTo, user);

        // Get tokens and prices
        (tokens, clearingPrices) = getTokensAndPrices();

        // Setup interactions
        interactions = [
            new CowSettlement.InteractionData[](1),
            new CowSettlement.InteractionData[](0),
            new CowSettlement.InteractionData[](0)
        ];
        interactions[0][0] = getSwapInteraction(sellAmount);

        return (orderUid, tokens, clearingPrices, trades, interactions);
    }

    function test_batchWithSettle_Empty() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        vm.startPrank(solver);

        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getEmptySettlement();

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);

        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);
    }

    function test_batchWithSettle_NonSolver() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        address nonSolver = makeAddr("nonSolver");
        vm.startPrank(nonSolver);

        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getEmptySettlement();

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);

        vm.expectRevert("Not a valid solver");
        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);
    }

    function test_batchWithSettle_WithCoWOrder() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        uint256 daiBalanceInMilkSwapBefore = IERC20(DAI).balanceOf(address(milkSwap));

        // Setup user with WETH
        deal(WETH, user, 1e18);
        vm.startPrank(user);

        // Create order parameters
        uint256 sellAmount = 1e18; // 1 WETH
        uint256 buyAmount = 1000e18; //  1000 DAI

        // Get settlement, that sells WETH for DAI
        (
            bytes memory orderUid,
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getSwapSettlement(sellAmount, buyAmount);

        // User, pre-approve the order
        console.logBytes(orderUid);
        cowSettlement.setPreSignature(orderUid, true);

        // Execute the settlement through the wrapper
        vm.stopPrank();
        vm.startPrank(solver);

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);
        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);

        // Verify the swap was executed
        assertEq(IERC20(DAI).balanceOf(user), buyAmount, "User should receive DAI");
        assertEq(IERC20(WETH).balanceOf(address(milkSwap)), sellAmount, "MilkSwap should receive WETH");

        uint256 daiBalanceInMilkSwapAfter = IERC20(DAI).balanceOf(address(milkSwap));
        assertEq(daiBalanceInMilkSwapAfter, daiBalanceInMilkSwapBefore - buyAmount, "MilkSwap should have less DAI");
    }
}

contract MilkSwap {
    mapping(address => uint256) public prices; // Price expressed in atoms of the quote per unit of the base token
    address public quoteToken;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        return (amountIn * prices[tokenIn]) / 1e18;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        require(tokenOut != quoteToken, "tokenOut must be the quote token");

        uint256 amountOut = this.getAmountOut(tokenIn, amountIn);

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}
