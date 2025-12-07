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

# 参数：指定某个备份文件名，否则默认取最新的
BACKUP_FILE_REMOTE="${1:-latest}"

echo "=== 从云服务器恢复 ROS2 volume ==="
echo "Volume:    ${VOLUME_NAME}"
echo "Container: ${CONTAINER_NAME}"
echo "Remote:    ${SSH_TARGET}:${REMOTE_DIR}"
echo

# 1. 在云端选定要用的备份文件
if [[ "${BACKUP_FILE_REMOTE}" = "latest" ]]; then
  echo "[1/6] 从云端选择最新备份文件..."
  LATEST_FILE="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "ls -1t ${REMOTE_DIR}/ros2volume-*.tar.gz 2>/dev/null | head -n 1")"
  if [[ -z "${LATEST_FILE}" ]]; then
    echo "错误：云端目录 ${REMOTE_DIR} 下没有找到 ros2volume-*.tar.gz" >&2
    exit 1
  fi
  REMOTE_FILE_PATH="${LATEST_FILE}"
else
  REMOTE_FILE_PATH="${REMOTE_DIR}/${BACKUP_FILE_REMOTE}"
fi

echo "  ✓ 使用云端备份文件：${REMOTE_FILE_PATH}"

# 2. 下载到本地当前目录
LOCAL_BACKUP_FILE="ros2volume-restore.tar.gz"
echo "[2/6] 下载备份到本地：${LOCAL_BACKUP_FILE} ..."
scp "${SCP_OPTS[@]}" "${SSH_TARGET}:${REMOTE_FILE_PATH}" "./${LOCAL_BACKUP_FILE}"

cleanup() {
  rm -f "${LOCAL_BACKUP_FILE}"
}
trap cleanup EXIT

# 3. 停止本地容器（如果存在且在跑）
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[3/6] 停止本地容器 ${CONTAINER_NAME} ..."
  docker stop "${CONTAINER_NAME}"
else
  echo "[3/6] 容器 ${CONTAINER_NAME} 未在运行，跳过停止。"
fi

# 4. 确保 volume 存在
echo "[4/6] 确保 Docker volume ${VOLUME_NAME} 存在 ..."
docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1 || docker volume create "${VOLUME_NAME}" >/dev/null

# 5. 用临时容器清空 volume 再解包数据
echo "[5/6] 将备份解包到 volume ${VOLUME_NAME} ..."
docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  -v "$PWD:/backup" \
  busybox sh -c "cd /data && rm -rf ./* && tar xzf /backup/${LOCAL_BACKUP_FILE}"

# 清理本地备份文件
rm -f "${LOCAL_BACKUP_FILE}"
trap - EXIT

echo "  ✓ 恢复完成"

# 可选：重启容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[6/6] 尝试重新启动容器 ${CONTAINER_NAME} ..."
  docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo
echo "=== 从云服务器恢复完成 ==="
echo "现在可以用本机的 ros2tutorial 容器继续你的 ROS2 Jazzy 开发。"
