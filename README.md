# ROS 2 Docker Volume Backup Workflow  
![macOS supported](https://img.shields.io/badge/macOS-13%20%2B-success) ![Linux supported](https://img.shields.io/badge/Linux-Ubuntu%2FDebian-success)

[中文说明 / Chinese guide](README_CN.md)

## Overview

Shell scripts to keep a local ROS 2 desktop container fast (GUI runs locally) while syncing its Docker volume (`ros2tutorial-home`) to a remote server. Work on macOS or Linux; Windows users can run them inside WSL/Docker Desktop with a bash shell.

Tools included:

- `push/ros2_backup_push.sh` – stop the container, tar the volume, and upload to the server (rsync with retries, fallback to scp).
- `pull/ros2_backup_pull.sh` – download the latest or named backup, recreate the volume, and restart the container.
- `server/upload_setup_script.sh` – copy the server-side bootstrap script via `scp`.
- `server/setup_remote.sh` – run this **on the server** to create `/srv/ros2_backups` (or any directory) with the right ownership.
- `server/prune_remote_backups.sh` – optional server-side cleaner that deletes the oldest archives once a size limit is reached (push script pipes it over SSH automatically when `REMOTE_STORAGE_MAX_GB` is set).

## Requirements

- Docker CLI (the scripts launch a temporary `busybox` container to tar/unpack the volume).
- `ssh`, `scp`, and preferably `rsync` installed on both the local machine and the server (the scripts fall back to scp when rsync is missing).
- SSH access to the backup server plus enough disk space for the tar archives.

## Configuration

1. Copy the env template and update values for your environment (backups are stored under `REMOTE_DIR`, default `/srv/ros2_backups`).

   ```bash
   cp .env.example .env
   # edit .env to set REMOTE_HOST, REMOTE_USER, SSH_IDENTITY_FILE, etc.
   ```

2. Optional tweaks:
   - `RSYNC_BW_LIMIT` (kB/s) throttles upload speed.
   - `RSYNC_MAX_RETRIES` controls how many times rsync will resume before falling back to scp.
   - `FORCE_CONTAINER_RESTART` (default `true`) restarts the ROS container after push/pull even if it was previously stopped.
   - `REMOTE_STORAGE_MAX_GB` & `REMOTE_STORAGE_KEEP_ONE` enforce a size limit on the remote backup directory—oldest archives are pruned after each push while optionally keeping at least one backup.

## Server Preparation

```bash
./server/upload_setup_script.sh              # run on your laptop/workstation
ssh -p <port> <user>@<host>
bash ~/ros2_backup_setup.sh /srv/ros2_backups
```

This only needs to be done once per server (or whenever you change target directories).

## Daily Workflow

### Push (backup current machine)

```bash
./push/ros2_backup_push.sh
```

Produces files like `ros2volume-YYYYmmdd-HHMMSS.tar.gz` under the remote backup directory.

### Pull (restore onto another machine)

```bash
# latest backup
./pull/ros2_backup_pull.sh

# specific archive
./pull/ros2_backup_pull.sh ros2volume-20251208-024704.tar.gz
```

After pulling, start your ROS 2 desktop container again (e.g. `docker run -d ... -v ros2tutorial-home:/home/ubuntu`).

> These scripts were originally tailored for the following container setup:
>
> ```bash
> docker run -d \
>   --name ros2tutorial \
>   -p 6080:80 \
>   --security-opt seccomp=unconfined \
>   --shm-size=512m \
>   --restart unless-stopped \
>   -v ros2tutorial-home:/home/ubuntu \
>   ghcr.io/tiryoh/ros2-desktop-vnc:jazzy
> ```
>
> If you use different container/volume names or images, simply update `.env` to match.

## Notes

- Keep `.env` out of version control; it already appears in `.gitignore`.
- The scripts assume your container name is `ros2tutorial` and your volume is `ros2tutorial-home`; adjust `.env` if you use different names.
- Make sure SSH keys are installed on the server if you want passwordless runs; otherwise the commands will prompt for credentials.
