# ROS 2 Docker Volume Backup Workflow

本仓库提供三段脚本，帮助你把本机 ROS 2 Docker volume（`ros2tutorial-home`）定期打包、推送到云服务器，再在任意机器上拉取恢复：

- `push/ros2_backup_push.sh`：打包本地 volume 并上传到远程服务器
- `pull/ros2_backup_pull.sh`：从远程服务器下载最新（或指定）的备份并恢复 volume
- `server/setup_remote.sh`：在本机运行，通过 SSH 初始化远端备份目录

## 准备工作

1. **安装依赖**
   - 本地机器需要 Docker CLI（脚本会自动启动临时 `busybox` 容器来打包/解包 volume）。
   - 需要可用的 `ssh` 和 `scp` 客户端。
2. **配置 `.env`（不会提交到 GitHub）**
   - 复制模板：`cp .env.example .env`
   - 按实际情况修改 `.env` 中的变量，例如远程主机地址、端口、备份目录等。
   - 如果希望脚本使用指定私钥，可把 `SSH_IDENTITY_FILE="/path/to/id_ed25519"` 填进去；留空则使用默认 SSH key。
   - `.env` 已加入 `.gitignore`，可以放心填写真实信息，脚本会自动读取这些值，无需直接改脚本。

## 初始化远程服务器

第一次使用前，在本机运行：

```bash
./server/setup_remote.sh
```

该脚本通过 SSH 连到 `.env` 指定的远程服务器并执行以下步骤：

1. 测试能否通过 `ssh -p REMOTE_PORT REMOTE_USER@REMOTE_HOST` 建立连接；
2. 在远端创建备份目录（默认 `/srv/ros2_backups`，可在 `.env` 修改），必要时自动用 `sudo`；
3. 输出目录权限与磁盘占用，方便确认。

> 提前在服务器上配置好 SSH 公钥登录能让所有脚本无需重复输入密码。

## 推送备份

在任意已有 `ros2tutorial-home` volume 的机器上运行：

```bash
./push/ros2_backup_push.sh
```

脚本会：

1.（如果在运行）停止 `ros2tutorial` 容器，避免写入冲突；
2. 用临时 `busybox` 容器把 volume 打包成 `ros2volume-YYYYmmdd-HHMMSS.tar.gz`；
3. 通过 `scp -P REMOTE_PORT` 上传至 `${REMOTE_DIR}`；
4. 删除本地临时 tar 包，并尝试重启容器。

备份文件都存放在服务器的 `${REMOTE_DIR}/ros2volume-*.tar.gz`。

## 拉取 / 恢复备份

在目标机器（装好 Docker）执行：

```bash
# 恢复最新备份
./pull/ros2_backup_pull.sh

# 恢复某个指定备份
./pull/ros2_backup_pull.sh ros2volume-20231208-120000.tar.gz
```

流程：

1. 从远端列出 `${REMOTE_DIR}` 下的 tar 包，默认取最新；
2. 下载到本地 `ros2volume-restore.tar.gz`；
3. 停止本地 `ros2tutorial` 容器，创建/清空 volume；
4. 解包数据后尝试重启容器。

恢复完成后，即可像平常一样启动你的 ROS 2 桌面容器，例如：

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

## 常见问题

- **如何列出现有备份？**  
  `ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "ls -lh ${REMOTE_DIR}"`

- **第一次 SSH 会提示 host key？**  
  脚本使用 `StrictHostKeyChecking=accept-new`，首次连接会自动写入 `known_hosts`，之后就不会提示。

- **想加密备份？**  
  可以在 push/pull 脚本中插入 `gpg` 或 openssl 命令，或在 `.env` 新增变量驱动你自己的加密流程。

有任何额外需求（例如在脚本里增加 `list`、`prune` 功能），可以继续拓展此仓库。祝开发顺利！
