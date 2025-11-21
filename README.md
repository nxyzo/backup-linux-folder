# linux-backup-folder
Here is a clean and complete **English documentation** for your backup tool, including a section explaining the `.env` file and the required `chmod 600` permission setting.

---

# 📘 **Backup Tool Documentation**

This document provides an overview of the backup script, its configuration, and how to securely manage credentials using the `.env` file.
The script supports **FTP**, **SFTP**, and **Amazon S3** as upload targets.

---

## 📁 **1. Overview**

The backup script creates a compressed archive (`.tar.gz`) of a specified directory on a Linux system and uploads it to one or more remote destinations:

* FTP server
* SFTP server
* Amazon S3 bucket

The script is designed to run automatically (e.g., via cron) and uses a secure `.env` file to store all credentials.

---

## 📦 **2. Folder Structure**

Example project layout:

```
linux-backup/
│
├── backup_linux.sh       # Main backup script
├── .env                  # Configuration + credentials
├── backup_dir/           # Temporary directory for backup files
└── backup_log.log        # Log file
```

---

## 🔧 **3. Configuration via `.env` File**

All credentials and environment-specific settings are stored in a `.env` file located in the same directory as the script.

### ✨ Why `.env`?

* Keeps passwords **out of the script**
* Makes the backup tool portable across systems
* Allows secure storage of keys and login data
* Compatible with automated tools and CI/CD

---

## 🔐 **4. `.env` File Format**

Here is the complete structure of the `.env` file:

```env
#########################################
# FTP CONFIG                            #
#########################################

REMOTE_FTP_HOSTNAME='ftp.example.com'
REMOTE_FTP_PORT=21
REMOTE_FTP_USERNAME='ftpuser'
REMOTE_FTP_PASSWORD='Very!Secure$123'
REMOTE_FTP_TARGET_DIRECTORY='backups'


#########################################
# SFTP CONFIG                           #
#########################################

REMOTE_SFTP_HOSTNAME='sftp.example.com'
REMOTE_SFTP_PORT=22
REMOTE_SFTP_USERNAME='sftp-user'
REMOTE_SFTP_PRIVATE_KEY='/home/user/.ssh/id_rsa'
# REMOTE_SFTP_PASSWORD='StrongPassword123!'  # Optional
REMOTE_SFTP_TARGET_DIRECTORY='/remote/backups'


#########################################
# S3 CONFIG                             #
#########################################

S3_BUCKET_NAME='my-backup-bucket'
S3_PREFIX='server1/backups'
AWS_ACCESS_KEY_ID='AKIA...'
AWS_SECRET_ACCESS_KEY='abc123!XYZ%'
AWS_DEFAULT_REGION='eu-central-1'
```

---

## 🔒 **5. Secure Permissions for `.env`**

The `.env` file contains **sensitive credentials** and must be protected from unauthorized access.

### **Set secure permissions:**

```bash
chmod 600 .env
```

### Explanation:

* `600` → only the file owner can read and write
* prevents other users from accessing credentials
* recommended best practice for secrets in plaintext files

### Recommended owner:

The file should be owned by the user who runs the backup script, e.g.:

```bash
chown user:user .env
```

---

## 🧠 **6. Loading the `.env` File in the Script**

The script automatically loads the `.env` file:

```bash
set -o allexport
source "$ENV_FILE"
set +o allexport
```

This makes every variable available to the backup functions.

---

## 🚀 **7. Running the Backup Script**

Make the script executable:

```bash
chmod +x backup_linux.sh
```

Run the script manually:

```bash
./backup_linux.sh
```

Or schedule it via cron:

```bash
crontab -e
```

Example cronjob (every day at 02:00):

```
0 2 * * * /home/backup_linux.sh
```

---

## 🧪 **8. Supported Upload Methods**

The script includes **three separate upload functions**:

* `upload_backup_to_ftp`
* `upload_backup_to_sftp`
* `upload_backup_to_s3`

You can activate only the one(s) you need in the `main` block:

```bash
upload_backup_to_ftp
# upload_backup_to_sftp
# upload_backup_to_s3
```

---

## 📜 **9. Log File**

All actions and errors are logged in:

```
backup_log.log
```

Log entries include a timestamp, making it easy to audit backup operations.

---

## 🎉 **10. Summary**

* The backup tool supports **FTP, SFTP, and S3 uploads**
* All credentials live securely in a `.env` file
* Always set `.env` permissions to **600**
* The script is modular, extendable, and cron-friendly

