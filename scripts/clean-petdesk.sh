#!/bin/zsh
# PetDesk 本地产物清理脚本：
# 删除构建产物、测试残留、崩溃日志与临时测量文件。
# 保留：用户数据（~/Library/Application Support/PetDesk）、源码、picture.png。
set -euo pipefail

echo "== PetDesk cleanup =="

# 0. 先退出运行中的实例，避免占用容器/文件。
if pgrep -x PetDesk >/dev/null 2>&1; then
  pkill -x PetDesk || true
  sleep 1
  echo "  killed running PetDesk"
fi

# 1. 仓库内构建产物（等价 make clean）。
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")"
rm -rf "$REPO_ROOT/.build" "$REPO_ROOT/DerivedData" "$REPO_ROOT/PetDesk.xcodeproj" 2>/dev/null || true
echo "  removed in-repo artifacts (.build / DerivedData / PetDesk.xcodeproj)"

# 2. Xcode 默认 DerivedData（主要构建残留，通常几百 MB）。
rm -rf ~/Library/Developer/Xcode/DerivedData/PetDesk-*(N) 2>/dev/null || true
echo "  removed Xcode DerivedData (PetDesk-*)"

# 3. UI 测试 runner 容器（受 containermanagerd 保护时静默跳过）。
rm -rf ~/Library/Containers/io.github.tmchao7.PetDeskUITests.xctrunner 2>/dev/null || true
echo "  removed UI test runner container (may be protected, skip if locked)"

# 4. 崩溃日志归档（含 Retired 目录；zsh glob 无匹配时不报错）。
rm -f ~/Library/Logs/DiagnosticReports/PetDesk*.ips(N) \
      ~/Library/Logs/DiagnosticReports/Retired/PetDesk*.ips(N) 2>/dev/null || true
echo "  removed crash reports (PetDesk*)"

# 5. 临时测量/构建/研究文件（大小写两种前缀都覆盖）。
rm -rf /tmp/PetDesk*(N) /tmp/petdesk-*(N) 2>/dev/null || true
echo "  removed temp files (/tmp/PetDesk* and /tmp/petdesk-*)"

echo "== Done. User data kept: ~/Library/Application Support/PetDesk =="
