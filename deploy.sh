#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  FLIXX ENGINE — Cronos Mainnet Deployment + MICRO-GENESIS SEED
#  Chain:   Cronos (chainId: 25)
#  Wallet:  0x36DF3a0570218E4d86f74e6150439DaA43B0365C
#
#  Accepts EITHER:
#    DEPLOYER_MNEMONIC="word1 word2 ... word12"  (12-word phrase)
#    DEPLOYER_KEY=0x<64-char hex>                (raw private key)
# ═══════════════════════════════════════════════════════════════

set -e

FORGE="$HOME/.foundry/bin/forge"
CAST="$HOME/.foundry/bin/cast"
RPC="https://evm.cronos.org"

# Token addresses on Cronos Mainnet
USDC="0xc21223249CA28397B4B6541dfFaEcC539BfF0c59"
USDT="0x66e428c3f67a68878562e79A0234c1F83c208770"

# MICRO-GENESIS amounts (198 SZNX + 19.80 USDC → $0.10/SZNX price)
SEED_SZNX_WEI="198000000000000000000"   # 198 * 1e18
SEED_USDC_UNITS="19800000"             # 19.80 * 1e6

# ── Build signer flags ────────────────────────────────────────
# Supports 12-word mnemonic OR raw private key
if [ -n "$DEPLOYER_MNEMONIC" ]; then
  SIGNER_FLAGS=(--mnemonic "$DEPLOYER_MNEMONIC" --mnemonic-index 0)
  DEPLOYER=$(${CAST} wallet address --mnemonic "$DEPLOYER_MNEMONIC" --mnemonic-index 0)
elif [ -n "$DEPLOYER_KEY" ]; then
  SIGNER_FLAGS=(--private-key "$DEPLOYER_KEY")
  DEPLOYER=$(${CAST} wallet address --private-key "$DEPLOYER_KEY")
else
  echo ""
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║  Set your 12-word phrase:                           ║"
  echo "  ║  export DEPLOYER_MNEMONIC=\"word1 word2 ... word12\"  ║"
  echo "  ║                                                     ║"
  echo "  ║  Or raw private key:                                ║"
  echo "  ║  export DEPLOYER_KEY=0x<64-char-hex>               ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  exit 1
fi

echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   FLIXX ENGINE — SOVEREIGN DEPLOYMENT              ║"
echo "  ║   Cronos Mainnet · chainId 25                      ║"
echo "  ║   MICRO-GENESIS: 198 SZNX + 19.80 USDC            ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Deployer: $DEPLOYER"
echo ""

# ── STEP 1: Deploy SZNToken ───────────────────────────────────
echo "  [1/6] Deploying SZNToken (SZNX)..."
SZNX_JSON=$(${FORGE} create src/SZNToken.sol:SZNToken \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" --legacy --json 2>/dev/null)
SZNX=$(echo "$SZNX_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['deployedTo'])")
echo "  ✓ SZNX:     $SZNX"

# ── STEP 2: Deploy SZNRegistry ────────────────────────────────
echo "  [2/6] Deploying SZNRegistry..."
REG_JSON=$(${FORGE} create src/SZNRegistry.sol:SZNRegistry \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" \
  --constructor-args "$SZNX" --legacy --json 2>/dev/null)
REGISTRY=$(echo "$REG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['deployedTo'])")
echo "  ✓ REGISTRY: $REGISTRY"

# ── STEP 3: Deploy SZNPool (SZNX/USDC) ───────────────────────
echo "  [3/6] Deploying SZNPool (SZNX/USDC AMM)..."
POOL_JSON=$(${FORGE} create src/SZNPool.sol:SZNPool \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" \
  --constructor-args "$SZNX" "$USDC" --legacy --json 2>/dev/null)
POOL=$(echo "$POOL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['deployedTo'])")
echo "  ✓ POOL:     $POOL"

# ── STEP 4: Deploy SZNRouter ──────────────────────────────────
echo "  [4/6] Deploying SZNRouter..."
ROUTER_JSON=$(${FORGE} create src/SZNRouter.sol:SZNRouter \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" \
  --constructor-args "$SZNX" "$USDC" "$USDT" "$REGISTRY" "$POOL" \
  --legacy --json 2>/dev/null)
ROUTER=$(echo "$ROUTER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['deployedTo'])")
echo "  ✓ ROUTER:   $ROUTER"

# ── STEP 5: Wire authorizations ───────────────────────────────
echo "  [5/6] Wiring authorizations..."

${CAST} send "$POOL" "authorizeRouter(address)" "$ROUTER" \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" --legacy >/dev/null 2>&1
echo "  ✓ Pool: router authorized"

${CAST} send "$REGISTRY" "authorizeRouter(address)" "$ROUTER" \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" --legacy >/dev/null 2>&1
echo "  ✓ Registry: router authorized"

# ── STEP 6: MICRO-GENESIS SEED ────────────────────────────────
echo "  [6/6] MICRO-GENESIS SEED: 198 SZNX + 19.80 USDC..."

${CAST} send "$SZNX" "approve(address,uint256)" "$POOL" "$SEED_SZNX_WEI" \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" --legacy >/dev/null 2>&1
echo "  ✓ SZNX approved"

${CAST} send "$USDC" "approve(address,uint256)" "$POOL" "$SEED_USDC_UNITS" \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" --legacy >/dev/null 2>&1
echo "  ✓ USDC approved"

${CAST} send "$POOL" \
  "addLiquidity(uint256,uint256,uint256,uint256,bool)" \
  "$SEED_SZNX_WEI" "$SEED_USDC_UNITS" "0" "0" "false" \
  --rpc-url "$RPC" "${SIGNER_FLAGS[@]}" --legacy >/dev/null 2>&1
echo "  ✓ GENESIS SEED COMPLETE — pool live at \$0.10/SZNX"

# ── Write .env ────────────────────────────────────────────────
ENV_FILE="../.env.contracts"
cat > "$ENV_FILE" << ENVEOF
# Generated by szn-deploy/deploy.sh — $(date)
EXPO_PUBLIC_SZN_CONTRACT=$SZNX
EXPO_PUBLIC_SZN_POOL=$POOL
EXPO_PUBLIC_SZN_ROUTER=$ROUTER
EXPO_PUBLIC_SZN_REGISTRY=$REGISTRY
ENVEOF

echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   SZNX IS LIVE ON CRONOS MAINNET                   ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo "  SZNX:     $SZNX"
echo "  POOL:     $POOL"
echo "  ROUTER:   $ROUTER"
echo "  REGISTRY: $REGISTRY"
echo ""
echo "  Price:  \$0.10 / SZNX"
echo "  TVL:    ~\$39.60 (Phase 1 of 4)"
echo ""
echo "  Verify: https://cronoscan.com/address/$SZNX"
echo ""
cat "$ENV_FILE"
