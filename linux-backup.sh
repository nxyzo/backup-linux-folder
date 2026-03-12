#!/bin/bash
set -euo pipefail

# Define color variables
YELLOW="\e[33m"
RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
PURPLE="\e[35m"
RESET="\e[0m"

BACKUP_LOG_FILE="${BACKUP_LOG_FILE:-/var/log/backup.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DAY=$(date +"%Y-%m-%d")
BACKUP_FILE=""

# FTP Settings
REMOTE_BACKUP_TARGET="${REMOTE_BACKUP_TARGET:-FTP}"
REMOTE_FTP_PORT="${REMOTE_FTP_PORT:-21}"

# SFTP Settings
REMOTE_SFTP_PORT="${REMOTE_SFTP_PORT:-22}"

# S3 Settings
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

#
# functions
#
function load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -o allexport
        source "$ENV_FILE"
        set +o allexport
    else
        echo -e "${RED}.env file not found: $ENV_FILE${RESET}"
        exit 1
    fi
}

function require_vars() {
    local missing=0
    for var in BACKUP_FILENAME BACKUP_SOURCE_PATH BACKUP_BASE_DIR LOCAL_TEMP_BACKUP_DIR; do
        if [[ -z "${!var:-}" ]]; then
            echo -e "${RED}Missing required variable: $var${RESET}"
            missing=1
        fi
    done
    return "$missing"
}

function log_to_file() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$BACKUP_LOG_FILE"
}

function cleanup() {
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        if [[ -n "${BACKUP_FILE:-}" && -f "$BACKUP_FILE" ]]; then
            rm -f -- "$BACKUP_FILE"
            log_to_file "Deleted backup file after error: $BACKUP_FILE"
        fi
    fi
}

function check_source_path() {
    if [[ ! -e "$BACKUP_SOURCE_PATH" ]]; then
        log_to_file "Directory does not exist: $BACKUP_SOURCE_PATH"
        log_to_file "Backup was cancelled"
        echo -e "${RED}Directory does not exist\nBackup was cancelled${RESET}"
        return 1
    fi
}

function check_temp_dir() {
    if [[ ! -e "$LOCAL_TEMP_BACKUP_DIR" ]]; then
        log_to_file "Temporary backup directory does not exist: ${LOCAL_TEMP_BACKUP_DIR}"
        return 1
    fi
}

function create_LOCAL_TEMP_BACKUP_DIR() {
    mkdir -p "$LOCAL_TEMP_BACKUP_DIR"
    log_to_file "Created temporary backup directory: $LOCAL_TEMP_BACKUP_DIR"
}

function delete_LOCAL_TEMP_BACKUP_DIR() {
    [[ -n "$LOCAL_TEMP_BACKUP_DIR" && "$LOCAL_TEMP_BACKUP_DIR" != "/" ]] || return 1
    rm -rf -- "$LOCAL_TEMP_BACKUP_DIR"
    log_to_file "Deleted temporary backup directory"
}

function create_backup() {
    log_to_file "Starting backup from ${BACKUP_SOURCE_PATH}/${BACKUP_BASE_DIR}"

    BACKUP_FILE="${LOCAL_TEMP_BACKUP_DIR%/}/${BACKUP_DAY}-${BACKUP_FILENAME}"

    tar -czf "$BACKUP_FILE" -C "$BACKUP_SOURCE_PATH" "$BACKUP_BASE_DIR"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        log_to_file "Backup failed with exit code: $rc"
        echo -e "${RED}Backup failed${RESET}"
        return "$rc"
    fi

    log_to_file "Backup created successfully: $BACKUP_FILE"
    echo -e "${GREEN}Backup created: $BACKUP_FILE${RESET}"
}

function upload_backup_to_ftp() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}Backup file not found: $BACKUP_FILE${RESET}"
        log_to_file "FTP upload failed: backup file not found: $BACKUP_FILE"
        return 1
    fi

    if [[ -z "${REMOTE_FTP_HOSTNAME:-}" || -z "${REMOTE_FTP_USERNAME:-}" || -z "${REMOTE_FTP_PASSWORD:-}" || -z "${REMOTE_FTP_TARGET_DIRECTORY:-}" ]]; then
        echo -e "${RED}FTP configuration incomplete (hostname/username/password/target dir missing)${RESET}"
        log_to_file "FTP upload failed: incomplete FTP config"
        return 1
    fi

    local ftp_url="ftp://$REMOTE_FTP_HOSTNAME"
    [[ -n "$REMOTE_FTP_PORT" ]] && ftp_url+=":$REMOTE_FTP_PORT"
    ftp_url+="/$REMOTE_FTP_TARGET_DIRECTORY/"

    log_to_file "Uploading backup via FTP to ${REMOTE_FTP_USERNAME}@${REMOTE_FTP_HOSTNAME}:${REMOTE_FTP_TARGET_DIRECTORY}"
    echo -e "${BLUE}Uploading backup to FTP...${RESET}"

    if ! curl -T "$BACKUP_FILE" -u "$REMOTE_FTP_USERNAME:$REMOTE_FTP_PASSWORD" "$ftp_url"; then
        echo -e "${RED}FTP upload failed${RESET}"
        log_to_file "FTP upload failed"
        return 1
    fi

    echo -e "${GREEN}FTP upload successful${RESET}"
    log_to_file "FTP upload finished successfully"
}

function upload_backup_to_sftp() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}Backup file not found: $BACKUP_FILE${RESET}"
        log_to_file "SFTP upload failed: backup file not found: $BACKUP_FILE"
        return 1
    fi

    if [[ -z "${REMOTE_SFTP_HOSTNAME:-}" || -z "${REMOTE_SFTP_USERNAME:-}" || -z "${REMOTE_SFTP_TARGET_DIRECTORY:-}" ]]; then
        echo -e "${RED}SFTP configuration incomplete (hostname/username/target dir missing)${RESET}"
        log_to_file "SFTP upload failed: incomplete SFTP config"
        return 1
    fi

    local sftp_opts=()
    [[ -n "${REMOTE_SFTP_PORT:-}" ]] && sftp_opts+=( -P "$REMOTE_SFTP_PORT" )
    [[ -n "${REMOTE_SFTP_PRIVATE_KEY:-}" ]] && sftp_opts+=( -i "$REMOTE_SFTP_PRIVATE_KEY" )

    log_to_file "Uploading backup via SFTP to ${REMOTE_SFTP_USERNAME}@${REMOTE_SFTP_HOSTNAME}:${REMOTE_SFTP_TARGET_DIRECTORY}"
    echo -e "${BLUE}Uploading backup to SFTP...${RESET}"

    if ! sftp "${sftp_opts[@]}" "${REMOTE_SFTP_USERNAME}@${REMOTE_SFTP_HOSTNAME}" <<EOF
mkdir $REMOTE_SFTP_TARGET_DIRECTORY
cd $REMOTE_SFTP_TARGET_DIRECTORY
put $BACKUP_FILE
EOF
    then
        echo -e "${RED}SFTP upload failed${RESET}"
        log_to_file "SFTP upload failed"
        return 1
    fi

    echo -e "${GREEN}SFTP upload successful${RESET}"
    log_to_file "SFTP upload finished successfully"
}

function upload_backup_to_s3() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}Backup file not found: $BACKUP_FILE${RESET}"
        log_to_file "S3 upload failed: backup file not found: $BACKUP_FILE"
        return 1
    fi

    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${RED}aws CLI not found in PATH${RESET}"
        log_to_file "S3 upload failed: aws CLI not installed"
        return 1
    fi

    if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
        echo -e "${RED}S3_BUCKET_NAME is not set${RESET}"
        log_to_file "S3 upload failed: S3_BUCKET_NAME missing"
        return 1
    fi

    local s3_prefix_path=""
    if [[ -n "${S3_PREFIX:-}" ]]; then
        s3_prefix_path="${S3_PREFIX%/}/"
    fi

    local s3_target="s3://${S3_BUCKET_NAME}/${s3_prefix_path}${BACKUP_DAY}-${BACKUP_FILENAME}"

    log_to_file "Uploading backup to S3: ${s3_target}"
    echo -e "${BLUE}Uploading backup to S3...${RESET}"

    if ! aws s3 cp "$BACKUP_FILE" "$s3_target"; then
        echo -e "${RED}S3 upload failed${RESET}"
        log_to_file "S3 upload failed"
        return 1
    fi

    echo -e "${GREEN}S3 upload successful${RESET}"
    log_to_file "S3 upload finished successfully"
}

#
# main
#

trap cleanup EXIT

load_env

if ! require_vars; then
    exit 1
fi

if ! check_source_path; then
    exit 1
fi

if ! check_temp_dir; then
    create_LOCAL_TEMP_BACKUP_DIR
fi

if ! create_backup; then
    exit 1
fi

case "$REMOTE_BACKUP_TARGET" in
    FTP)
        if ! upload_backup_to_ftp; then
            exit 1
        fi
        ;;
    SFTP)
        if ! upload_backup_to_sftp; then
            exit 1
        fi
        ;;
    S3)
        if ! upload_backup_to_s3; then
            exit 1
        fi
        ;;
    *)
        echo -e "${RED}Unsupported REMOTE_BACKUP_TARGET: $REMOTE_BACKUP_TARGET${RESET}"
        log_to_file "Unsupported REMOTE_BACKUP_TARGET: $REMOTE_BACKUP_TARGET"
        exit 1
        ;;
esac

delete_LOCAL_TEMP_BACKUP_DIR