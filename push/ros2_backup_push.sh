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
RSYNC_BW_LIMIT="${RSYNC_BW_LIMIT:-}"
RSYNC_MAX_RETRIES="${RSYNC_MAX_RETRIES:-3}"
FORCE_CONTAINER_RESTART="${FORCE_CONTAINER_RESTART:-true}"
REMOTE_STORAGE_MAX_GB="${REMOTE_STORAGE_MAX_GB:-}"
REMOTE_STORAGE_KEEP_ONE="${REMOTE_STORAGE_KEEP_ONE:-true}"
REMOTE_STORAGE_LIMIT_BYTES=""
if [[ -n "${REMOTE_STORAGE_MAX_GB}" ]]; then
  if [[ "${REMOTE_STORAGE_MAX_GB}" =~ ^[0-9]+$ ]]; then
    REMOTE_STORAGE_LIMIT_BYTES=$((REMOTE_STORAGE_MAX_GB * 1024 * 1024 * 1024))
  else
    echo "警告：REMOTE_STORAGE_MAX_GB 需为整数，当前值 '${REMOTE_STORAGE_MAX_GB}' 被忽略。"
  fi
fi

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

CONTAINER_WAS_RUNNING=false
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "容器 ${CONTAINER_NAME} 当前正在运行，为保证数据一致需要先停止。"
  read -r -p "请确认已保存所有工作内容，输入 y 后继续 (y/N): " CONFIRM
  case "${CONFIRM}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "已取消 push。"
      exit 0
      ;;
  esac
  CONTAINER_WAS_RUNNING=true
fi

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
use_rsync=false
if command -v rsync >/dev/null 2>&1; then
  if ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "command -v rsync >/dev/null 2>&1"; then
    use_rsync=true
  else
    echo "  ⚠️  远程主机未安装 rsync，回退为 scp（无法断点续传）。"
  fi
else
  echo "  ⚠️  本地未安装 rsync，回退为 scp（无法断点续传）。"
fi

if [[ "${use_rsync}" == true ]]; then
  RSYNC_CMD=(rsync -az --partial --progress)
  if [[ -n "${RSYNC_BW_LIMIT}" ]]; then
    RSYNC_CMD+=(--bwlimit="${RSYNC_BW_LIMIT}")
  fi
  RSYNC_RSH="ssh"
  for opt in "${SSH_OPTS[@]}"; do
    RSYNC_RSH+=" $(printf '%q' "${opt}")"
  done
  RSYNC_CMD+=(-e "${RSYNC_RSH}" "${BACKUP_FILE}" "${SSH_TARGET}:${REMOTE_DIR}/")

  RSYNC_SUCCESS=false
  for attempt in $(seq 1 "${RSYNC_MAX_RETRIES}"); do
    echo "  ▶ rsync 尝试 ${attempt}/${RSYNC_MAX_RETRIES} ..."
    if "${RSYNC_CMD[@]}"; then
      RSYNC_SUCCESS=true
      break
    else
      echo "  ⚠️  rsync 传输失败（第 ${attempt} 次），稍后重试..."
    fi
  done

  if [[ "${RSYNC_SUCCESS}" != true ]]; then
    echo "  ✗ rsync 在 ${RSYNC_MAX_RETRIES} 次尝试后仍失败，改用 scp。"
    use_rsync=false
  fi
fi

if [[ "${use_rsync}" != true ]]; then
  scp "${SCP_OPTS[@]}" "${BACKUP_FILE}" "${SSH_TARGET}:${REMOTE_DIR}/"
fi

echo "  ✓ 上传完成"

if [[ -n "${REMOTE_STORAGE_LIMIT_BYTES}" ]]; then
  echo "[可选] 检查远程备份目录大小（限制 ${REMOTE_STORAGE_MAX_GB} GB）..."
  PRUNE_SCRIPT="${PROJECT_ROOT}/server/prune_remote_backups.sh"
  if [[ -f "${PRUNE_SCRIPT}" ]]; then
    ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" 'bash -s' -- "${REMOTE_DIR}" "${REMOTE_STORAGE_LIMIT_BYTES}" "${REMOTE_STORAGE_KEEP_ONE}" < "${PRUNE_SCRIPT}"
  else
    echo "警告：找不到 ${PRUNE_SCRIPT}，无法执行远程清理。"
  fi
fi

# 4. 清理本地 tar（可选）
echo "[4/4] 清理本地备份文件 ..."
rm -f "${BACKUP_FILE}"
trap - EXIT

# 5. 可选：重新启动容器（仅在脚本开始前处于运行状态时）
if [[ "${CONTAINER_WAS_RUNNING}" == true || "${FORCE_CONTAINER_RESTART}" == true ]]; then
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "尝试重新启动容器 ${CONTAINER_NAME} ..."
    docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  else
    echo "容器 ${CONTAINER_NAME} 不存在，无法重新启动。"
  fi
elif [[ "${CONTAINER_WAS_RUNNING}" != true ]]; then
  echo "容器 ${CONTAINER_NAME} 在脚本开始前未运行，跳过重新启动。"
fi

echo
echo "=== 备份推送完成 ==="
echo "云端文件保存在：${SSH_TARGET}:${REMOTE_DIR}/ros2volume-*.tar.gz"
