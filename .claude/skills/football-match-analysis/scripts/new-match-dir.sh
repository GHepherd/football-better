#!/usr/bin/env bash
# 幂等创建 matches/YYYY-MM-DD/ 目录。
# 用法: scripts/new-match-dir.sh 2026-09-11
# 注意: Write 工具本身会自建目录，这个脚本只是让"建目录"这一步在 shell 里显式可见。
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "用法: $0 YYYY-MM-DD" >&2
  exit 2
fi

date_dir="$1"
if ! printf '%s' "$date_dir" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "错误: 日期必须是 YYYY-MM-DD 格式，收到 '$date_dir'" >&2
  exit 2
fi

mkdir -p "matches/$date_dir"
echo "matches/$date_dir"
