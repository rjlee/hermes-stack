#!/usr/bin/env bash
# Weekly hermes-stack backup (invoked from root's crontab on docker.home).
# Keeps a single archive in /root/docker/hermes-stack/backup/; PBS's daily
# LXC backup carries it off-host. Log: /var/log/hermes-stack-backup.log
set -u
LOG=/var/log/hermes-stack-backup.log
MAILTO=robl@rjlee.net
cd /root/docker/hermes-stack || exit 1
{
    echo "=== $(date '+%F %T') start ==="
    if ./hermes-stack backup --retain 1; then
        echo "=== $(date '+%F %T') OK ==="
    else
        rc=$?
        echo "=== $(date '+%F %T') FAILED rc=$rc ==="
        tail -n 30 "$LOG" | /usr/sbin/sendmail -t <<MAIL 2>/dev/null
To: $MAILTO
Subject: FAIL: hermes-stack backup on $(hostname)

hermes-stack backup failed (rc=$rc). Last log lines:

$(tail -n 30 "$LOG")
MAIL
        exit "$rc"
    fi
} >> "$LOG" 2>&1
