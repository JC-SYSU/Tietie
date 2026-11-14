#!/bin/bash
# 真实数据搜索对账: 在 Copy 库的快照上比对搜索结果与逐条暴力匹配 (见
# TietieCore/Tests/TietieCoreTests/SearchParityTests.swift)。源库只读, 不会被写。
#
# 用法: Scripts/search-parity.sh [live|<库目录>|<copy.sqlite>] [查询条数] [报告.json]
# 改了搜索、归一化或迁移之后跑一遍; 退出码非 0 表示有漏检/多检或搜索文本过期。
# 报告里的延迟是 release + enable-testing 构建下的数字。
set -uo pipefail
cd "$(dirname "$0")/../TietieCore"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export COPY_PARITY_STORE="${1:-live}"
export COPY_PARITY_QUERIES="${2:-400}"
export COPY_PARITY_REPORT="${3:-}"
log="$(mktemp -t copy-parity)"
swift test -c release -Xswiftc -enable-testing --filter SearchParityTests >"$log" 2>&1
status=$?
sed -n '/SEARCH PARITY REPORT/,/^}/p;/error:/p;/Executed .* tests/p' "$log"
[ "$status" -eq 0 ] || echo "完整日志: $log"
# swift test 可能改写 Package.resolved (CONTRIBUTING 提到的已知问题), 还原它。
git checkout -- Package.resolved 2>/dev/null || true
exit "$status"
