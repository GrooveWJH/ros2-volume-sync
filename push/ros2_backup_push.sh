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

: "${VOLUME_NAME:?请在 .env 中设置 VOLUME_NAME}"
: "${CONTAINER_NAME:?请在 .env 中设置 CONTAINER_NAME}"
: "${REMOTE_USER:?请在 .env 中设置 REMOTE_USER}"
: "${REMOTE_HOST:?请在 .env 中设置 REMOTE_HOST}"
: "${REMOTE_DIR:?请在 .env 中设置 REMOTE_DIR}"
REMOTE_PORT="${REMOTE_PORT:-22}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-}"

SSH_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
SSH_OPTS=(-p "${REMOTE_PORT}" -o StrictHostKeyChecking=accept-new)
SCP_OPTS=(-P "${REMOTE_PORT}")

if [[ -n "${SSH_IDENTITY_FILE}" ]]; then
  SSH_OPTS+=(-i "${SSH_IDENTITY_FILE}")
  SCP_OPTS+=(-i "${SSH_IDENTITY_FILE}")
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="ros2volume-${STAMP}.tar.gz"

echo "=== ROS2 volume 备份并推送到云服务器 ==="
echo "Volume:    ${VOLUME_NAME}"
echo "Container: ${CONTAINER_NAME}"
echo "Remote:    ${SSH_TARGET}:${REMOTE_DIR}"
echo

cleanup() {
  rm -f "${BACKUP_FILE}"
}
trap cleanup EXIT

# 1. 若容器在跑，先停掉（避免写入时不一致）
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[1/4] 停止容器 ${CONTAINER_NAME} ..."
  docker stop "${CONTAINER_NAME}"
else
  echo "[1/4] 容器 ${CONTAINER_NAME} 未在运行，跳过停止。"
fi

# 2. 打包 volume 到当前目录的 tar.gz
echo "[2/4] 打包 Docker volume ${VOLUME_NAME} -> ${BACKUP_FILE} ..."
docker run --rm \
  -v "${VOLUME_NAME}:/data:ro" \
  -v "$PWD:/backup" \
  busybox sh -c "cd /data && tar czf /backup/${BACKUP_FILE} ."

echo "  ✓ 打包完成：$PWD/${BACKUP_FILE}"

# 3. 上传到云服务器
echo "[3/4] 上传到云服务器 ${SSH_TARGET}:${REMOTE_DIR} ..."
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "mkdir -p '${REMOTE_DIR}'"
scp "${SCP_OPTS[@]}" "${BACKUP_FILE}" "${SSH_TARGET}:${REMOTE_DIR}/"

echo "  ✓ 上传完成"

# 4. 清理本地 tar（可选）
echo "[4/4] 清理本地备份文件 ..."
rm -f "${BACKUP_FILE}"
trap - EXIT

# 5. 可选：重新启动容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "尝试重新启动容器 ${CONTAINER_NAME} ..."
  docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo
echo "=== 备份推送完成 ==="
echo "云端文件保存在：${SSH_TARGET}:${REMOTE_DIR}/ros2volume-*.tar.gz"
