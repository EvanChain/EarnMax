# EarnMax — Usage Handbook

This handbook summarizes how to use the contracts in this repository (Router, PIV, IPIV and swap adapters) based on the current Solidity sources.

Actors
- PIV owner: the account that deploys or receives a PIV contract (has owner-only privileges such as createPosition, migrateFromAave, updateExpectProfit).
- Taker / Trader: an account that wants to buy collateral from positions by paying debt tokens (calls Router.swap or PIV.takePosition).
- Router: coordinates multi-position swaps for takers and maps users to PIV contracts.

Key contracts and interfaces
- Router (src/Router.sol): deploys per-user PIVs and executes swaps via SwapData. swap(SwapData) pulls tokenIn from the caller and iterates over positionDatas to call previewTakePosition / takePosition on each PIV.
- PIV (src/PIV.sol): manages positions, Aave flash-loans for migration or new loans, and implements takePosition / previewTakePosition logic.
- IPIV (src/IPIV.sol): interface for PIV, defines Position and Order structs and methods.
- IERC20SwapAdapter (src/interfaces/IERC20SwapAdapter.sol): adapters for swapping tokens inside PIV operations (used during new position creation).

Quick reference: relevant external approvals
- When creating a position (PIV.createPosition) with useAaveBalance == false: the PIV contract will call safeTransferFrom(msg.sender, address(this), position.principal). The caller (PIV owner) MUST approve the PIV contract to spend position.principal on the ERC20 token first.
- When migrating an existing Aave position to PIV (PIV.migrateFromAave): the original user (whose aToken balance is transferred) must approve the PIV contract to transfer their aToken. The PIV owner (caller of migrateFromAave) is the owner and triggers the migration via flash loan; the migration will transfer aTokens from the original user to the PIV.
- When a taker calls Router.swap: the taker MUST approve Router to spend tokenIn for amountIn (Router performs tokenIn.safeTransferFrom(caller, address(this), amountIn)).
- When PIV.takePosition is called directly: the taker must approve the PIV contract to spend the required debt token amount (takePosition performs safeTransferFrom(msg.sender,...)).

Using Router.swap (recommended flow)
1. Construct IRouter.PositionData[] with entries for the target PIVs and position IDs you want to take:
   - Each entry: { pivAddress: address, positionId: uint256 }
2. Create IRouter.SwapData with tokenIn (debt token), tokenOut (collateral token), amountIn, minAmountOut and the positionDatas array.
3. Approve the Router to spend tokenIn:
   - IERC20(tokenIn).approve(address(router), amountIn);
4. Call router.swap(swapData) from the taker account.

Example (Solidity-like pseudocode):
IRouter.PositionData[] memory positionDatas = new IRouter.PositionData[](1);
positionDatas[0] = IRouter.PositionData({ pivAddress: pivAddress, positionId: positionId });
IRouter.SwapData memory swapData = IRouter.SwapData({ tokenIn: debtToken, tokenOut: collateralToken, amountIn: inputAmount, minAmountOut: minOutput, positionDatas: positionDatas });
IERC20(debtToken).approve(address(router), inputAmount);
(router.swap(swapData));

What happens during Router.swap (current behavior)
- Router pulls amountIn of tokenIn from the taker into the Router contract.
- Router iterates the provided positionDatas and calls previewTakePosition on each PIV to determine how much debtInput will be consumed and how much collateralOutput will be returned for each position.
- Router calls takePosition on each PIV to execute the trade for the computed debt input and receives collateral output.
- Router enforces remainningAmount == 0 and netAmountOut >= minAmountOut before emitting SwapExecuted.

Important implementation note and recommended fix (must-read)
- Current PIV.takePosition expects the caller (msg.sender) to be the account that provides the debt tokens and performs IERC20(debtToken).safeTransferFrom(msg.sender, address(this), debtInput).
- During Router.swap the Router contract becomes msg.sender when Router calls PIV.takePosition. This means PIV will call transferFrom(Router, PIV, debtInput). For this to succeed, the Router contract must have approved the PIV contract to spend Router's tokenIn balance.
- However, Router.swap does not currently set those allowances. As a result, in the current codebase Router.swap will revert at PIV.takePosition because PIV will attempt to transferFrom the Router without an allowance.

Two practical resolutions (choose one):
1) Update Router.swap to approve each PIV for the required input before calling takePosition. e.g. IERC20(tokenIn).approve(pivAddress, input) for each target pivAddress (and reset/handle allowances safely).
2) Update PIV.takePosition to accept tokens that are already transferred into PIV (change the flow to transfer tokens into PIV or accept the Router as a trusted caller). For example, modify takePosition to check IERC20(...).balanceOf(msg.sender) or accept transferred tokens and not call transferFrom(msg.sender,...).

Until one of these fixes is applied, Router.swap cannot be used end-to-end in the current implementation without a contract change.

Other useful interactions
- PIV.previewTakePosition(positionId, inputAmount): view function that returns (debtInput, collateralOutput) for a given input amount without state changes. Use this to quote fills.
- PIV.updateExpectProfit(positionId, expectProfit, deadline): owner-only function to update the expected profit and deadline for a position (affects whether takePosition is allowed/returns >0).
- PIV.getBalance(token): check contract balances for tokens held by a PIV.
- PIV.withdrawAssets(token, amount, recipient): owner-only emergency withdrawal.

Debugging tips
- When a swap reverts, call previewTakePosition locally to check expected debtInput / collateralOutput values.
- Verify all ERC20 approvals before calling high-level flows: approve PIV when creating positions, approve Router when calling swap.
- Track events: LoanCreated, LoanMigrated, PositionTakeProfit, SwapExecuted — they reveal position lifecycle and swap outcomes.

If you want, I can:
- Produce a small script (foundry script or a JavaScript/ethers script) that performs the correct approve + swap sequence and optionally patches Router.swap to add approvals.
- Open a PR that applies the recommended fix to Router.swap or PIV.takePosition.

(End of handbook)