# Docker Compose Automated Update Script

![Bash](https://img.shields.io/badge/Bash-Script-4EAA25?logo=gnu-bash&logoColor=white)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Cron Safe](https://img.shields.io/badge/Cron-Safe-success?logo=linux&logoColor=white)

A production‑safe Bash script to **automatically update Docker Compose stacks** on a Linux host.

The script **detects Docker Compose projects automatically**, pulls updated images, **restarts stacks only when updates exist**, and generates **audit‑ready summary reports**. It is designed for **servers, maintenance windows, and unattended cron execution**.

---

## ✨ Features

- 🔍 **Automatic Compose Path Detection**
  - Uses Docker container labels to detect running Compose projects
  - Falls back to filesystem scanning if no running stacks are found

- ⏭ **Skip Stacks With No Updates**
  - Compares image IDs before and after `docker compose pull`
  - Skips `docker compose up -d` when images are unchanged
  - Prevents unnecessary container restarts and downtime

- 📄 **Summary Reporting**
  - Generates:
    - Human‑readable summary report (`.txt`)
    - Machine‑readable CSV report (`.csv`)
  - Per‑stack status:
    - `UPDATED`
    - `NO_UPDATES`
    - `SKIPPED`
    - `DRY_RUN`
    - `ERROR`

- 🧪 **Dry‑Run Mode**
  - Shows what *would* be updated without changing containers or images

- 🤖 **Cron‑Safe / Non‑Interactive**
  - Fully unattended execution using `--auto-yes`

- 🪵 **Centralised Logging**
  - All stdout and stderr written to a log file

- 🧹 **Post‑Run Image Cleanup**
  - Optional `docker image prune` to remove unused images

---

## 📦 Requirements

- Linux host
- Docker Engine
- Docker Compose v2 (`docker compose`)
- Bash

---

## 🚀 Usage

```bash
# Interactive (default)
./docker-compose-update.sh

# Dry-run only (no changes)
./docker-compose-update.sh --dry-run

# Non-interactive (cron safe)
./docker-compose-update.sh --auto-yes

# Dry-run + non-interactive
./docker-compose-update.sh --dry-run --auto-yes
