#!/usr/bin/env bash
# Static checks: Rojo sourcemap + luau-lsp analysis with Roblox types.
# Requires .tools/rojo, .tools/luau-lsp and .tools/globalTypes.d.luau
# (see README "Toolchain").
set -euo pipefail
cd "$(dirname "$0")/.."
.tools/rojo sourcemap default.project.json -o sourcemap.json
.tools/luau-lsp analyze \
  --sourcemap=sourcemap.json \
  --definitions=.tools/globalTypes.d.luau \
  --base-luaurc=.luaurc \
  --ignore "**/Packages/**" \
  src tools/EconomySim.luau "$@"
