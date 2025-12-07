#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "找不到环境配置：${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${REMOTE_USER:?请在 .env 中设置 REMOTE_USER}"
: "${REMOTE_HOST:?请在 .env 中设置 REMOTE_HOST}"
: "${REMOTE_DIR:?请在 .env 中设置 REMOTE_DIR}"
REMOTE_PORT="${REMOTE_PORT:-22}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-}"

SSH_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_SCRIPT_PATH="${1:-~/ros2_backup_setup.sh}"

SCP_OPTS=(-P "${REMOTE_PORT}")
if [[ -n "${SSH_IDENTITY_FILE}" ]]; then
  SCP_OPTS+=(-i "${SSH_IDENTITY_FILE}")
fi

echo "=== 上传服务器初始化脚本 ==="
echo "目标主机：${SSH_TARGET}"
echo "Remote 文件：${REMOTE_SCRIPT_PATH}"
echo

scp "${SCP_OPTS[@]}" "${SCRIPT_DIR}/setup_remote.sh" "${SSH_TARGET}:${REMOTE_SCRIPT_PATH}"

echo
echo "✓ 上传完成。"
echo "接下来登录服务器执行："
SSH_HINT="ssh -p ${REMOTE_PORT}"
if [[ -n "${SSH_IDENTITY_FILE}" ]]; then
  SSH_HINT+=" -i ${SSH_IDENTITY_FILE}"
fi
SSH_HINT+=" ${SSH_TARGET}"
echo "  ${SSH_HINT}"
echo "  bash ${REMOTE_SCRIPT_PATH} ${REMOTE_DIR}"
echo
echo "脚本默认会在缺少 sudo 权限时抛错，请确保在服务器上可执行 sudo。"
