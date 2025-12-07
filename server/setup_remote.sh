#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${REMOTE_DIR:-${1:-/srv/ros2_backups}}"

# 用途：在服务器本地运行，创建/验证备份目录，并在需要时使用 sudo。

echo "=== 初始化备份目录（在服务器上执行） ==="
echo "目标目录：${REMOTE_DIR}"
echo

read -r -p "确认当前是在目标服务器上执行？(y/N): " CONFIRM
case "${CONFIRM}" in
  y|Y|yes|YES)
    ;;
  *)
    echo "已取消。请登录服务器后再运行此脚本。"
    exit 1
    ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[1/3] 尝试在当前用户权限下创建目录..."
  if mkdir -p "${REMOTE_DIR}" 2>/dev/null; then
    echo "  ✓ 已创建/存在：${REMOTE_DIR}"
  else
    echo "  ✗ 创建失败，尝试使用 sudo..."
    if command -v sudo >/dev/null 2>&1; then
      sudo mkdir -p "${REMOTE_DIR}"
      sudo chown "${USER}:${USER}" "${REMOTE_DIR}"
      echo "  ✓ 通过 sudo 创建并切换所有权。"
    else
      echo "错误：没有权限创建 ${REMOTE_DIR} 且无法使用 sudo。" >&2
      exit 1
    fi
  fi
else
  echo "[1/3] 当前为 root 用户，直接创建目录..."
  mkdir -p "${REMOTE_DIR}"
fi

echo "[2/3] 设置权限并输出状态..."
chmod 700 "${REMOTE_DIR}" >/dev/null 2>&1 || true
ls -ld "${REMOTE_DIR}"

echo "[3/3] 显示磁盘占用："
df -h "${REMOTE_DIR}" 2>/dev/null || df -h .

echo
echo "=== 服务器已准备完成，可用于 push/pull 备份 ==="
