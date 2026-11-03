#!/usr/bin/env bash
# 安装提交前检查钩子（钩子不进版本库，需各自安装）
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .git/hooks
cp scripts/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "✅ 已安装 .git/hooks/pre-commit"
