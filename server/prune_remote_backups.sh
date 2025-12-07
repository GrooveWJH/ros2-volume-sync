#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${1:-}"
LIMIT_BYTES="${2:-}"
KEEP_ONE="${3:-true}"

if [[ -z "${REMOTE_DIR}" || -z "${LIMIT_BYTES}" ]]; then
  echo "用法: prune_remote_backups.sh <remote_dir> <limit_bytes> [keep_one=true|false]" >&2
  exit 1
fi

if [[ ! -d "${REMOTE_DIR}" ]]; then
  echo "目录不存在：${REMOTE_DIR}" >&2
  exit 0
fi

if ! [[ "${LIMIT_BYTES}" =~ ^[0-9]+$ ]]; then
  echo "limit_bytes 必须为整数：${LIMIT_BYTES}" >&2
  exit 1
fi

current=$(du -sb "${REMOTE_DIR}" 2>/dev/null | awk '{print $1}')
if [[ -z "${current}" ]]; then
  current=$(du -sk "${REMOTE_DIR}" 2>/dev/null | awk '{print $1 * 1024}')
fi
current=${current:-0}

mapfile -t files < <(ls -1tr "${REMOTE_DIR}"/ros2volume-*.tar.gz 2>/dev/null || true)
total=${#files[@]}
removed=0

if [[ "${total}" -eq 0 ]]; then
  echo "远程目录 ${REMOTE_DIR} 当前占用 ${current} 字节（无备份文件）。"
  exit 0
fi

for f in "${files[@]}"; do
  if [[ "${current}" -le "${LIMIT_BYTES}" ]]; then
    break
  fi
  remaining=$(( total - removed ))
  if [[ "${KEEP_ONE}" == "true" && "${remaining}" -le 1 ]]; then
    break
  fi
  size=$(stat -c %s "${f}" 2>/dev/null || stat -f %z "${f}" 2>/dev/null || echo 0)
  if rm -f "${f}"; then
    current=$(( current > size ? current - size : 0 ))
    removed=$(( removed + 1 ))
    echo "删除旧备份：${f} (${size} bytes)"
  fi
done

echo "远程目录 ${REMOTE_DIR} 当前占用 ${current} 字节，删除 ${removed} 个文件 (限制 ${LIMIT_BYTES} 字节)。"
