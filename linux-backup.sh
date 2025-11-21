#!/bin/bash

# Define color variables
YELLOW="\e[33m"
RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
PURPLE="\e[35m"
RESET="\e[0m"

BACKUP_SOURCE_PATH=/home/user/linux-backup-lobster
BACKUP_BASE_DIR=etc
LOCAL_TEMP_BACKUP_DIR=/home/user/linux-backup/backup_dir
BACKUP_LOG_FILE=/home/user/linux-backup/backup_log.log
BACKUP_TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DAY=$(date +"%Y-%m-%d")

REMOTE_BACKUP_TARGET=FTP

REMOTE_FTP_HOSTNAME="$REMOTE_FTP_HOSTNAME"
REMOTE_FTP_PORT="${REMOTE_FTP_PORT:-21}"
REMOTE_FTP_USERNAME="$REMOTE_FTP_USERNAME"
REMOTE_FTP_PASSWORD="$REMOTE_FTP_PASSWORD"
REMOTE_FTP_TARGET_DIRECTORY="$REMOTE_FTP_TARGET_DIRECTORY"

REMOTE_SFTP_HOSTNAME="$REMOTE_SFTP_HOSTNAME"
REMOTE_SFTP_PORT="${REMOTE_SFTP_PORT:-22}"
REMOTE_SFTP_USERNAME="$REMOTE_SFTP_USERNAME"
REMOTE_SFTP_PRIVATE_KEY="$REMOTE_SFTP_PRIVATE_KEY"
REMOTE_SFTP_PASSWORD="$REMOTE_SFTP_PASSWORD"
REMOTE_SFTP_TARGET_DIRECTORY="$REMOTE_SFTP_TARGET_DIRECTORY"

S3_BUCKET_NAME="$S3_BUCKET_NAME"
S3_PREFIX="$S3_PREFIX"
AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

BACKUP_FILENAME=backup-test.tar.gz

ENV_FILE="/home/user/linux-backup/.env"

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

function log_to_file() {
    echo -e "${BACKUP_TIMESTAMP%/} ${1}" >> "${BACKUP_LOG_FILE}"
}

function check_if_BACKUP_SOURCE_PATH_exists() {
    if [[ ! -e "$BACKUP_SOURCE_PATH" ]]; then
        log_to_file "The Directory doesn´t exist"
        log_to_file "The Backup got cancel"
        echo -e "${RED}The Directory doesn´t exist\nThe Backup got cancel${RESET}"
        return 1
    fi
}

function check_if_LOCAL_TEMP_BACKUP_DIR_exists() {
    if [[ ! -e "$LOCAL_TEMP_BACKUP_DIR" ]]; then
        log_to_file "The Temp Directory path: ${LOCAL_TEMP_BACKUP_DIR} doesn´t exist"
        return 1
    fi
}

function create_LOCAL_TEMP_BACKUP_DIR() {
    mkdir -p "$LOCAL_TEMP_BACKUP_DIR"
    log_to_file "Create temp backup directory"
}

function delete_LOCAL_TEMP_BACKUP_DIR() {
    rm -r "$LOCAL_TEMP_BACKUP_DIR"
    log_to_file "Deleting temp backup dir"
}

function backup_BACKUP_SOURCE_PATH() {
    log_to_file "Starting backup from $BACKUP_SOURCE_PATH"

    local backup_file="${LOCAL_TEMP_BACKUP_DIR%/}/${BACKUP_DAY}-${BACKUP_FILENAME}"

    tar -czvf "$backup_file" -C "$BACKUP_SOURCE_PATH" "$BACKUP_BASE_DIR"
    if [ ! $? -eq 0 ]; then
        log_to_file "The backup exits with error: $?"
        echo -e "${RED}Backup failed${RESET}"
        return 1
    fi

    log_to_file "Backup created successfully: $backup_file"
    echo -e "${GREEN}Backup created: $backup_file${RESET}"
}

function upload_backup_to_ftp() {
    local backup_file="${LOCAL_TEMP_BACKUP_DIR%/}/${BACKUP_DAY}-${BACKUP_FILENAME}"

    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Backup file not found: $backup_file${RESET}"
        log_to_file "FTP upload failed: backup file not found: $backup_file"
        return 1
    fi

    if [[ -z "$REMOTE_FTP_HOSTNAME" || -z "$REMOTE_FTP_USERNAME" || -z "$REMOTE_FTP_PASSWORD" || -z "$REMOTE_FTP_TARGET_DIRECTORY" ]]; then
        echo -e "${RED}FTP configuration incomplete (hostname/username/password/target dir missing)${RESET}"
        log_to_file "FTP upload failed: incomplete FTP config"
        return 1
    fi

    local ftp_url="ftp://$REMOTE_FTP_HOSTNAME"
    [[ -n "$REMOTE_FTP_PORT" ]] && ftp_url+=":$REMOTE_FTP_PORT"
    ftp_url+="/$REMOTE_FTP_TARGET_DIRECTORY/"

    log_to_file "Uploading backup via FTP to ${REMOTE_FTP_USERNAME}@${REMOTE_FTP_HOSTNAME}:${REMOTE_FTP_TARGET_DIRECTORY}"
    echo -e "${BLUE}Uploading backup to FTP...${RESET}"

    if ! curl -T "$backup_file" -u "$REMOTE_FTP_USERNAME:$REMOTE_FTP_PASSWORD" "$ftp_url"; then
        echo -e "${RED}FTP upload failed${RESET}"
        log_to_file "FTP upload failed (curl returned error)"
        return 1
    fi

    echo -e "${GREEN}FTP upload successful${RESET}"
    log_to_file "FTP upload finished successfully"
}

function upload_backup_to_sftp() {
    local backup_file="${LOCAL_TEMP_BACKUP_DIR%/}/${BACKUP_DAY}-${BACKUP_FILENAME}"

    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Backup file not found: $backup_file${RESET}"
        log_to_file "SFTP upload failed: backup file not found: $backup_file"
        return 1
    fi

    if [[ -z "$REMOTE_SFTP_HOSTNAME" || -z "$REMOTE_SFTP_USERNAME" || -z "$REMOTE_SFTP_TARGET_DIRECTORY" ]]; then
        echo -e "${RED}SFTP configuration incomplete (hostname/username/target dir missing)${RESET}"
        log_to_file "SFTP upload failed: incomplete SFTP config"
        return 1
    fi

    local sftp_opts=()
    [[ -n "$REMOTE_SFTP_PORT" ]] && sftp_opts+=( -P "$REMOTE_SFTP_PORT" )
    [[ -n "$REMOTE_SFTP_PRIVATE_KEY" ]] && sftp_opts+=( -i "$REMOTE_SFTP_PRIVATE_KEY" )

    log_to_file "Uploading backup via SFTP to ${REMOTE_SFTP_USERNAME}@${REMOTE_SFTP_HOSTNAME}:${REMOTE_SFTP_TARGET_DIRECTORY}"
    echo -e "${BLUE}Uploading backup to SFTP...${RESET}"

    if ! sftp "${sftp_opts[@]}" "${REMOTE_SFTP_USERNAME}@${REMOTE_SFTP_HOSTNAME}" <<EOF
mkdir $REMOTE_SFTP_TARGET_DIRECTORY
cd $REMOTE_SFTP_TARGET_DIRECTORY
put $backup_file
EOF
    then
        echo -e "${RED}SFTP upload failed${RESET}"
        log_to_file "SFTP upload failed (sftp command error)"
        return 1
    fi

    echo -e "${GREEN}SFTP upload successful${RESET}"
    log_to_file "SFTP upload finished successfully"
}

function upload_backup_to_s3() {
    local backup_file="${LOCAL_TEMP_BACKUP_DIR%/}/${BACKUP_DAY}-${BACKUP_FILENAME}"

    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}Backup file not found: $backup_file${RESET}"
        log_to_file "S3 upload failed: backup file not found: $backup_file"
        return 1
    fi

    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${RED}aws CLI not found in PATH${RESET}"
        log_to_file "S3 upload failed: aws CLI not installed"
        return 1
    fi

    if [[ -z "$S3_BUCKET_NAME" ]]; then
        echo -e "${RED}S3_BUCKET_NAME is not set${RESET}"
        log_to_file "S3 upload failed: S3_BUCKET_NAME missing"
        return 1
    fi

    local s3_prefix_path=""
    if [[ -n "$S3_PREFIX" ]]; then
        s3_prefix_path="${S3_PREFIX%/}/"
    fi

    local s3_target="s3://${S3_BUCKET_NAME}/${s3_prefix_path}${BACKUP_DAY}-${BACKUP_FILENAME}"

    log_to_file "Uploading backup to S3: ${s3_target}"
    echo -e "${BLUE}Uploading backup to S3...${RESET}"

    if ! aws s3 cp "$backup_file" "$s3_target"; then
        echo -e "${RED}S3 upload failed${RESET}"
        log_to_file "S3 upload failed (aws s3 cp error)"
        return 1
    fi

    echo -e "${GREEN}S3 upload successful${RESET}"
    log_to_file "S3 upload finished successfully"
}

#
# main
#

load_env

if ! check_if_BACKUP_SOURCE_PATH_exists; then
    exit 1
fi

if ! check_if_LOCAL_TEMP_BACKUP_DIR_exists; then
    create_LOCAL_TEMP_BACKUP_DIR
fi

if ! backup_BACKUP_SOURCE_PATH; then
    exit 1
fi

if [[ "$REMOTE_BACKUP_TARGET" == "FTP" ]]; then
    upload_backup_to_ftp
fi

if [[ "$REMOTE_BACKUP_TARGET" == "SFTP" ]]; then
    upload_backup_to_sftp
fi

if [[ "$REMOTE_BACKUP_TARGET" == "S3" ]]; then
    upload_backup_to_s3
fi

delete_LOCAL_TEMP_BACKUP_DIR
