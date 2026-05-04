Docker Compose Automated Update Script
This script safely automates updating Docker Compose stacks on a Linux host.
It is designed for production servers, cron execution, and mixed environments where compose projects may live in different locations.
The script auto-detects Docker Compose project paths, pulls updated images, restarts stacks only when updates are actually available, and generates a detailed summary report of what occurred.

✨ Features


🔍 Automatic compose path detection

Detects running Docker Compose projects using Docker container labels
Falls back to filesystem scanning if no running stacks are found



⏭ Skip stacks with no updates

Compares image IDs before and after docker compose pull
Skips docker compose up -d if images are unchanged (no unnecessary restarts)



📄 Summary reporting

Generates:

Human‑readable summary report (.txt)
Machine‑readable CSV report (.csv)


Records per‑stack status:

UPDATED
NO_UPDATES
SKIPPED
DRY_RUN
ERROR





🧪 Dry‑run mode

Shows what would be updated without changing containers or images



🤖 Non‑interactive mode

Fully unattended execution using --auto-yes (cron‑safe)



🪵 Centralised logging

All stdout/stderr logged to a configurable log file



🧹 Optional image cleanup

Prunes unused Docker images at the end of execution




📦 Requirements

Linux host
Docker Engine
Docker Compose v2 plugin (docker compose)
Bash


🚀 Usage
Shell# Interactive (default)./docker-compose-update.sh# Dry-run only (no changes)./docker-compose-update.sh --dry-run# Non-interactive (cron safe)./docker-compose-update.sh --auto-yes# Dry-run + non-interactive./docker-compose-update.sh --dry-run --auto-yes``Show more lines

📝 Output


Log file
/var/log/docker-compose-update.log



Summary report
/var/log/docker-compose-update-summary-YYYYMMDD-HHMMSS.txt



CSV report
/var/log/docker-compose-update-summary-YYYYMMDD-HHMMSS.csv




🔐 Safety Design

Validates compose files (docker compose config) before making changes
Continues safely if a single stack fails
Avoids restarting containers when no image updates exist
Suitable for scheduled maintenance windows or cron usage


📌 Typical Use Cases

Regular server hygiene without unnecessary downtime
Scheduled container updates via cron
Multi-stack hosts with inconsistent compose locations
Audit‑friendly environments requiring update evidence


📄 License
MIT (or update as required)
