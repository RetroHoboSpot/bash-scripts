#!/bin/bash

# ==========================================================
# Docker Compose Auto-Detect Update Script
# - Detect compose paths from running containers (labels)
# - Fallback filesystem scan if none running
# - Pull images; only "up -d" if images changed
# - Summary report (TXT + CSV)
# - Logging (stdout+stderr) to log file
# Options:
#   --dry-run|-n    : do not pull/up/prune; show intended actions only
#   --auto-yes|-y   : non-interactive; assume yes
#   --log FILE      : override log file path
#   --report FILE   : override report base path (without extension)
# ==========================================================

DRY_RUN=false
AUTO_YES=false
LOG_FILE="/var/log/docker-compose-update.log"

# Report base name (we'll create .txt and .csv)
TS="$(date +%Y%m%d-%H%M%S)"
REPORT_BASE="/var/log/docker-compose-update-summary-${TS}"

# Fallback scan roots (if no running compose stacks)
FALLBACK_SCAN_ROOTS=(/opt /srv /docker /home)

# ----------------------------------------------------------
# Arg parsing
# ----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)   DRY_RUN=true; shift ;;
    --auto-yes|-y)  AUTO_YES=true; shift ;;
    --log)          LOG_FILE="$2"; shift 2 ;;
    --report)       REPORT_BASE="$2"; shift 2 ;;
    *)              echo "Unknown arg: $1"; exit 2 ;;
  esac
done

REPORT_TXT="${REPORT_BASE}.txt"
REPORT_CSV="${REPORT_BASE}.csv"

# ----------------------------------------------------------
# Logging setup
# ----------------------------------------------------------
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$REPORT_BASE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo "Docker Compose Update Script"
date
echo "Dry-run:   $DRY_RUN"
echo "Auto-yes:  $AUTO_YES"
echo "Log file:  $LOG_FILE"
echo "Report:    $REPORT_TXT"
echo "CSV:       $REPORT_CSV"
echo "============================================="
echo

# ----------------------------------------------------------
# Safety checks
# ----------------------------------------------------------
command -v docker >/dev/null || { echo "ERROR: docker not found in PATH"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose plugin not available"; exit 1; }

# ----------------------------------------------------------
# Helpers
# ----------------------------------------------------------
safe_compose_images_quiet() {
  # Returns sorted unique image IDs (one per line). Empty if none.
  docker compose images --quiet 2>/dev/null | sort -u | sed '/^$/d'
}

# Output containers -> "project|working_dir" pairs
detect_running_compose_dirs() {
  local ids
  ids="$(docker ps -q)"
  if [[ -z "$ids" ]]; then
    return 0
  fi

  docker inspect $ids \
    --format '{{ index .Config.Labels "com.docker.compose.project" }}|{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' \
    2>/dev/null \
    | grep -vE '^\|$' \
    | grep -v '<no value>' \
    | sort -u
}

fallback_scan_compose_dirs() {
  find "${FALLBACK_SCAN_ROOTS[@]}" -type f \
    \( -iname "docker-compose.yml" -o -iname "compose.yml" \) \
    2>/dev/null \
    | xargs -r -n1 dirname \
    | sort -u
}

# ----------------------------------------------------------
# Detect compose projects (project|dir)
# ----------------------------------------------------------
echo "Detecting docker-compose stacks from running containers..."
mapfile -t PAIRS < <(detect_running_compose_dirs)

if [[ ${#PAIRS[@]} -eq 0 ]]; then
  echo "No running compose stacks detected. Falling back to filesystem scan..."
  mapfile -t DIRS < <(fallback_scan_compose_dirs)

  if [[ ${#DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No compose directories found (running stacks or filesystem scan)."
    exit 1
  fi

  # Create pseudo-pairs using directory basename as "project"
  PAIRS=()
  for d in "${DIRS[@]}"; do
    PAIRS+=("$(basename "$d")|$d")
  done
fi

echo
echo "Detected ${#PAIRS[@]} stack(s):"
for p in "${PAIRS[@]}"; do
  proj="${p%%|*}"
  dir="${p#*|}"
  echo " - ${proj} => ${dir}"
done
echo

# ----------------------------------------------------------
# Confirmation (unless auto-yes)
# ----------------------------------------------------------
if ! $AUTO_YES; then
  read -rp "Proceed with processing these stacks? (y/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0
fi

# ----------------------------------------------------------
# Report headers
# ----------------------------------------------------------
{
  echo "Docker Compose Update Summary"
  echo "Started: $(date)"
  echo "Dry-run: $DRY_RUN"
  echo "Auto-yes: $AUTO_YES"
  echo "---------------------------------------------"
  echo
} > "$REPORT_TXT"

echo "timestamp,project,dir,status,details" > "$REPORT_CSV"

# Counters
TOTAL=0
UPDATED=0
NO_UPDATES=0
SKIPPED=0
ERRORS=0
DRYRUNS=0

# ----------------------------------------------------------
# Process stacks
# ----------------------------------------------------------
for p in "${PAIRS[@]}"; do
  ((TOTAL++))
  proj="${p%%|*}"
  dir="${p#*|}"
  ts_now="$(date +%Y-%m-%dT%H:%M:%S)"

  echo
  echo "============================================="
  echo "Processing: $proj"
  echo "Dir:        $dir"
  echo "============================================="

  if ! $AUTO_YES; then
    read -rp "Process this stack? (y/N): " CONFIRM_ONE
    if [[ ! "$CONFIRM_ONE" =~ ^[Yy]$ ]]; then
      echo "Skipping (user choice): $proj"
      ((SKIPPED++))
      echo "$ts_now,$proj,$dir,SKIPPED,User chose not to process" >> "$REPORT_CSV"
      {
        echo "[$ts_now] $proj"
        echo "  Dir: $dir"
        echo "  Status: SKIPPED (user choice)"
        echo
      } >> "$REPORT_TXT"
      continue
    fi
  fi

  if [[ ! -d "$dir" ]]; then
    echo "ERROR: Directory does not exist: $dir"
    ((ERRORS++))
    echo "$ts_now,$proj,$dir,ERROR,Directory missing" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: ERROR (directory missing)"
      echo
    } >> "$REPORT_TXT"
    continue
  fi

  cd "$dir" || {
    echo "ERROR: Cannot cd into $dir"
    ((ERRORS++))
    echo "$ts_now,$proj,$dir,ERROR,Cannot cd into directory" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: ERROR (cannot cd)"
      echo
    } >> "$REPORT_TXT"
    continue
  }

  echo "--- Validating compose file ---"
  if ! docker compose config >/dev/null 2>&1; then
    echo "ERROR: docker compose config failed (invalid compose?)"
    ((ERRORS++))
    echo "$ts_now,$proj,$dir,ERROR,Compose validation failed" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: ERROR (compose validation failed)"
      echo
    } >> "$REPORT_TXT"
    continue
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN] Would run: docker compose pull"
    echo "[DRY-RUN] Would run: docker compose up -d (only if updates found)"
    ((DRYRUNS++))
    echo "$ts_now,$proj,$dir,DRY_RUN,No changes made" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: DRY_RUN (no changes made)"
      echo
    } >> "$REPORT_TXT"
    continue
  fi

  # Capture image IDs before pull
  BEFORE="$(safe_compose_images_quiet | tr '\n' ' ')"

  echo "--- docker compose pull ---"
  if ! PULL_OUT="$(docker compose pull 2>&1)"; then
    echo "$PULL_OUT"
    echo "ERROR: pull failed"
    ((ERRORS++))
    echo "$ts_now,$proj,$dir,ERROR,Pull failed" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: ERROR (pull failed)"
      echo "  Details:"
      echo "$PULL_OUT" | sed 's/^/    /'
      echo
    } >> "$REPORT_TXT"
    continue
  fi
  echo "$PULL_OUT"

  # Capture image IDs after pull
  AFTER="$(safe_compose_images_quiet | tr '\n' ' ')"

  if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "No image changes detected -> skipping 'docker compose up -d'"
    ((NO_UPDATES++))
    echo "$ts_now,$proj,$dir,NO_UPDATES,Images unchanged; up -d skipped" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: NO_UPDATES (up -d skipped)"
      echo
    } >> "$REPORT_TXT"
    continue
  fi

  echo "Image changes detected -> running 'docker compose up -d'"
  echo "--- docker compose up -d ---"
  if ! UP_OUT="$(docker compose up -d 2>&1)"; then
    echo "$UP_OUT"
    echo "ERROR: up -d failed"
    ((ERRORS++))
    echo "$ts_now,$proj,$dir,ERROR,up -d failed after updates" >> "$REPORT_CSV"
    {
      echo "[$ts_now] $proj"
      echo "  Dir: $dir"
      echo "  Status: ERROR (up -d failed after updates)"
      echo "  Details:"
      echo "$UP_OUT" | sed 's/^/    /'
      echo
    } >> "$REPORT_TXT"
    continue
  fi
  echo "$UP_OUT"

  ((UPDATED++))
  echo "$ts_now,$proj,$dir,UPDATED,Images changed; pull+up completed" >> "$REPORT_CSV"
  {
    echo "[$ts_now] $proj"
    echo "  Dir: $dir"
    echo "  Status: UPDATED"
    echo "  Notes: Images changed; pull+up completed"
    echo
  } >> "$REPORT_TXT"
done

# ----------------------------------------------------------
# Image prune (only if not dry-run)
# ----------------------------------------------------------
echo
echo "---------------------------------------------"
echo "Pruning unused Docker images..."
if ! PRUNE_OUT="$(docker image prune -f 2>&1)"; then
  echo "$PRUNE_OUT"
  echo "WARNING: image prune failed"
else
  echo "$PRUNE_OUT"
fi

# ----------------------------------------------------------
# Final summary
# ----------------------------------------------------------
END_TS="$(date)"
{
  echo "---------------------------------------------"
  echo "Finished: $END_TS"
  echo "Totals:"
  echo "  Total stacks:     $TOTAL"
  echo "  Updated:          $UPDATED"
  echo "  No updates:       $NO_UPDATES"
  echo "  Skipped:          $SKIPPED"
  echo "  Dry-run entries:  $DRYRUNS"
  echo "  Errors:           $ERRORS"
  echo
  echo "CSV report: $REPORT_CSV"
} >> "$REPORT_TXT"

echo
echo "============================================="
echo "SUMMARY"
echo "  Total stacks:     $TOTAL"
echo "  Updated:          $UPDATED"
echo "  No updates:       $NO_UPDATES"
echo "  Skipped:          $SKIPPED"
echo "  Dry-run entries:  $DRYRUNS"
echo "  Errors:           $ERRORS"
echo "Report written to:  $REPORT_TXT"
echo "CSV written to:     $REPORT_CSV"
echo "============================================="
