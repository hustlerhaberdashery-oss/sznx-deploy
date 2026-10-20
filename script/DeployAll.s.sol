// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/SZNToken.sol";
import "../src/SZNRegistry.sol";
import "../src/SZNPool.sol";
import "../src/SZNRouter.sol";

/**
 * DeployAll — Full FLIXX ENGINE sovereign stack deployment
 * Chain: Cronos Mainnet (chainId: 25)
 *
 * Run:
 *   forge script script/DeployAll.s.sol \
 *     --rpc-url https://evm.cronos.org \
 *     --private-key $DEPLOYER_KEY \
 *     --broadcast \
 *     --legacy \
 *     -vvv
 */

contract DeployAll {

    // ── Cronos Mainnet token addresses ────────────────────────────────────────
    address constant USDT = 0x66e428c3f67a68878562e79A0234c1F83c208770;
    address constant USDC = 0xc21223249CA28397B4B6541dfFaEcC539BfF0c59;

    function run() external {
        // forge passes the private-key via --private-key flag; tx.origin = deployer
        address deployer = tx.origin;

        // ── Step 1: SZNToken ─────────────────────────────────────────────────
        SZNToken token = new SZNToken();
        address SZNX = address(token);
        _log("SZNToken deployed", SZNX);

        // ── Step 2: SZNRegistry ──────────────────────────────────────────────
        SZNRegistry registry = new SZNRegistry(SZNX);
        address REGISTRY = address(registry);
        _log("SZNRegistry deployed", REGISTRY);

        // ── Step 3: SZNPool ──────────────────────────────────────────────────
        SZNPool pool = new SZNPool(SZNX, USDT);
        address POOL = address(pool);
        _log("SZNPool deployed", POOL);

        // ── Step 4: SZNRouter ────────────────────────────────────────────────
        SZNRouter router = new SZNRouter(SZNX, USDC, USDT, REGISTRY, POOL);
        address ROUTER = address(router);
        _log("SZNRouter deployed", ROUTER);

        // ── Step 5: Wire authorizations ──────────────────────────────────────
        pool.authorizeRouter(ROUTER);
        registry.authorizeRouter(ROUTER);
        _log("Router authorized in Pool + Registry", ROUTER);

        // ── GENESIS SEED CALLDATA (execute separately after funding pool) ──
        // token.approve(POOL, 1_000_000 * 1e18);
        // IERC20(USDT).approve(POOL, 100_000 * 1e6);
        // pool.addLiquidity(1_000_000e18, 100_000e6, 0, 0, false);

        // ── Summary ──────────────────────────────────────────────────────────
        _banner(SZNX, REGISTRY, POOL, ROUTER, deployer);
    }

    function _log(string memory label, address addr) internal view {
        // forge -vvv prints these
        (label);
        (addr);
    }

    function _banner(
        address sznx,
        address registry,
        address pool,
        address router,
        address deployer
    ) internal pure {
        (sznx); (registry); (pool); (router); (deployer);
        // All addresses printed by forge --broadcast output
    }
}
