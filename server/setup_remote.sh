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
SSH_OPTS=(-p "${REMOTE_PORT}" -o StrictHostKeyChecking=accept-new)

if [[ -n "${SSH_IDENTITY_FILE}" ]]; then
  SSH_OPTS+=(-i "${SSH_IDENTITY_FILE}")
fi

echo "=== 初始化远程备份服务器 ==="
echo "SSH:  ${SSH_TARGET}"
echo "目录: ${REMOTE_DIR}"
echo

echo "[1/3] 测试 SSH 连通性..."
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "echo '  ✓ 远程服务器在线：' \"\$(hostname)\""

echo "[2/3] 确保备份目录存在并归属当前用户..."
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "bash -s" -- "${REMOTE_DIR}" <<'EOF'
set -euo pipefail
remote_dir="$1"
if ! mkdir -p "${remote_dir}" 2>/dev/null; then
  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "${remote_dir}"
    sudo chown "$USER":"$USER" "${remote_dir}"
  else
    echo "无法创建目录 ${remote_dir}（缺少权限）" >&2
    exit 1
  fi
fi
chmod 700 "${remote_dir}" >/dev/null 2>&1 || true
EOF

echo "[3/3] 当前目录信息："
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "ls -ld '${REMOTE_DIR}' && df -h '${REMOTE_DIR}' 2>/dev/null || true"

echo
echo "=== 远程服务器准备完成 ==="
echo "现在可以使用 push/pull 脚本与 ${REMOTE_DIR} 同步备份。"
