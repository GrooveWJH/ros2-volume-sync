# ROS 2 Docker Volume 备份工具

> 仅支持 macOS / Linux；Windows 用户可在 WSL 或 Docker Desktop + WSL 中执行。

## 功能概览

本仓库提供四个 bash 脚本，帮助你把本地 `ros2tutorial` 容器的数据卷 `ros2tutorial-home` 定期打包并同步到云端，再在任意机器上恢复：

- `push/ros2_backup_push.sh`：停止容器 → 打包 volume → 使用 rsync（带自动重试）上传。
- `pull/ros2_backup_pull.sh`：下载最新或指定备份 → 解包回同名 volume → 尝试重启容器。
- `server/upload_setup_script.sh`：在本机把服务器部署脚本通过 `scp` 复制到远端。
- `server/setup_remote.sh`：在服务器上创建/校验备份目录（可自动 sudo）。
- `server/prune_remote_backups.sh`：在服务器本地执行的清理脚本；push 会自动通过 SSH 调用它以删除超过容量限制的旧备份。

## 使用前准备

1. **安装依赖**：Docker CLI、ssh/scp、rsync（本地与服务器都安装，缺失时会自动退回 scp）。
2. **配置 `.env`（默认备份目录为 `REMOTE_DIR`，即 `/srv/ros2_backups`）**：

   ```bash
   cp .env.example .env
   # 编辑 .env，设置 REMOTE_HOST、REMOTE_USER、SSH_IDENTITY_FILE 等
   ```

   可选变量：
   - `RSYNC_BW_LIMIT`：限速（单位 KB/s）。
   - `RSYNC_MAX_RETRIES`：rsync 失败后的重试次数（超出后自动改用 scp）。
   - `FORCE_CONTAINER_RESTART`：脚本结束后无论容器之前是否在运行，一律尝试 `docker start`。
   - `REMOTE_STORAGE_MAX_GB` / `REMOTE_STORAGE_KEEP_ONE`：限制远程目录的总大小；push 完成后会自动删除最旧备份，保留至少一个文件（除非显式关闭）。

3. **初始化服务器**：

   ```bash
   ./server/upload_setup_script.sh
   ssh -p <port> <user>@<host>
   bash ~/ros2_backup_setup.sh /srv/ros2_backups
   ```

   只需执行一次；脚本会在服务器本地创建备份目录并设置权限。

## 日常流程

### 推送备份

```bash
./push/ros2_backup_push.sh
```

脚本会生成 `ros2volume-YYYYmmdd-HHMMSS.tar.gz` 并上传到 `.env` 指定目录。若 rsync 过程中断线，会自动断点续传并最多重试 `RSYNC_MAX_RETRIES` 次，之后才回退 scp。

### 拉取/恢复

```bash
# 恢复最新备份
./pull/ros2_backup_pull.sh

# 或恢复指定文件
./pull/ros2_backup_pull.sh ros2volume-20251208-024704.tar.gz
```

恢复完成后重新启动容器，例如：

```bash
docker run -d \ 
  --name ros2tutorial \ 
  -p 6080:80 \ 
  --security-opt seccomp=unconfined \ 
  --shm-size=512m \ 
  --restart unless-stopped \ 
  -v ros2tutorial-home:/home/ubuntu \ 
  ghcr.io/tiryoh/ros2-desktop-vnc:jazzy
```

## 其他说明

- `.env` 已加入 `.gitignore`，放心写入真实主机/密钥信息。
- 若容器或 volume 名称不同，可直接在 `.env` 中修改 `VOLUME_NAME`、`CONTAINER_NAME`。
- 建议在服务器上配置 SSH 公钥，避免 push/pull 时频繁输入密码。
