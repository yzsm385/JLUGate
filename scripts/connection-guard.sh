#!/usr/bin/env bash
# 连接路径冻结守卫：受保护文件被改动而冻结清单没更新时，CI 直接失败。
set -euo pipefail
cd "$(dirname "$0")/.."

LIST=(
  Sources/JLUGateNet/DrcomEngine.swift
  Sources/JLUGateNet/AuthCoordinator.swift
  Sources/JLUGateNet/DatagramChannel.swift
  Sources/JLUGateNet/BSDChannel.swift
  Sources/JLUGateNet/NWChannel.swift
  Sources/JLUGateNet/InterfaceResolver.swift
  Sources/JLUGateCore/DrcomCodec.swift
  Sources/JLUGateCore/PacketLayout.swift
  Sources/JLUGateCore/DrcomPacket.swift
  Sources/JLUGateCore/MD5.swift
)

FROZEN="docs/connection-freeze.sha256"
current="$(for f in "${LIST[@]}"; do shasum -a 256 "$f"; done)"

if [ "${1:-}" = "--freeze" ]; then
  mkdir -p "$(dirname "$FROZEN")"
  echo "$current" > "$FROZEN"
  echo "✅ 已更新冻结清单（连接路径被有意修改）"
  exit 0
fi

if [ ! -f "$FROZEN" ]; then
  echo "❌ 缺少冻结清单 $FROZEN"
  echo "   如果是第一次建立冻结，运行：./scripts/connection-guard.sh --freeze"
  exit 1
fi

if ! diff -q <(echo "$current") "$FROZEN" >/dev/null; then
  echo "❌ 连接路径被改动，但冻结清单没更新："
  diff <(echo "$current") "$FROZEN" | sed 's/^/   /' || true
  echo ""
  echo "   如果确实要改连接："
  echo "   1. 单独提交，信息以 [CONN] 开头"
  echo "   2. ./scripts/connection-guard.sh --freeze 并提交 docs/connection-freeze.sha256"
  echo "   3. 附真机验证结果"
  exit 1
fi
echo "✅ 连接路径未改动（冻结生效）"
