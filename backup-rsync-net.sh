#!/bin/bash

# Rsync.net backup script - Backup to rsync target and send passive check result to Nagios/Icinga (NSCA)
#
# NB: No backup rotation is done. Assumes snapshots / rotation is done on the target.
#     Rsync.net do not maintain full / correct file permissions. 
#
# Adlibre Pty Ltd 2012

# Install:
# yum -y install nsca-client
#
# Usage: backup-rsync-net.sh <test>

## Source config file
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -e "${DIR}/config" ]; then
  . ${DIR}/config
fi

## Config Defaults
BACKUP_PATH=${BACKUP_PATH-'/etc /root /srv/www'}
BACKUP_EXCLUDE_PATH=${BACKUP_EXCLUDE_PATH-'/dev /proc /sys /tmp /var/tmp /var/run /selinux /cgroups lost+found'}
REMOTE=${REMOTE-'rsync.net'}
REMOTE_PATH=${REMOTE_PATH-`hostname -s`/}
BACKUPS_KEEP=${BACKUPS_KEEP-'7'} # This will keep the last 7 backups
NAGIOS_SERVER=${NAGIOS_SERVER-monitor.example.com}
NAGIOS_SERVICE_NAME=${NAGIOS_SERVICE_NAME-'Rsync.net Backup Daily'}

## Constants
LOCKFILE="/var/run/`basename $0 | sed s/\.sh// `.pid"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:$PATH";
DAY=`date +'%F %T'`
BACKUP_TIME=`date +%Y%m%d%H%M%S`

# expand excludes
for e in $BACKUP_EXCLUDE_PATH; do
    RSYNC_EXCLUDES="$RSYNC_EXCLUDES --exclude=${e}"
done

# Sanity Checks
# Check to see if we are already running / locked, limit to one instance
if [ -f ${LOCKFILE} ] ; then
    echo "Error: Already running, or locked. Lockfile exists [`ls -ld $LOCKFILE`]."
    exit 99
else
    echo $$ > ${LOCKFILE}
    # Upon exit, remove lockfile.
    trap "{ rm -f ${LOCKFILE}; }" EXIT
fi

#
# Send passive alert information to Nagios / Icinga
#
function raiseAlert {
    # $1 - Service name that has been set up on nagios/nagiosdev server
    # $2 - Return code 0=success, 1=warning, 2=critical
    # $3 - Message you want to send
    # <host_name>,<svc_description>,<return_code>,<plugin_output>
    # defaults that can be overridden
    NAGIOS_DIR=${NAGIOS_DIR-/usr/sbin/}
    NAGIOS_CFG=${NAGIOS_CFG-/etc/nagios/}
    NAGIOS_PORT=${NAGIOS_PORT-5667}
    if [ -f ${NAGIOS_DIR}send_nsca ]; then
        echo "`hostname`,$1,$2,$3" | ${NAGIOS_DIR}send_nsca -H ${NAGIOS_SERVER} \
        -p ${NAGIOS_PORT} -d "," -c ${NAGIOS_CFG}send_nsca.cfg > /dev/null;
        echo "Debug: Message Sent to Nagios ($NAGIOS_SERVER): $1 $2 $3.";
    else
        echo "Warning: NSCA (Nagios) Plugin not found.";
        echo "Message would have been sent to Nagios ($NAGIOS_SERVER): \"$1\" $2 \"$3\"";
    fi
}

# Command
function uploadBackup {
    existing=(`ssh ${REMOTE} "ls ${REMOTE_PATH}" | egrep '[0-9]{14}' | sort -n`)
    while [ "${#existing[@]}" -ge "${BACKUPS_KEEP}" ] && [ "${#existing[@]}" -ne "1" ]; do
        ssh ${REMOTE} "rm -rf ${REMOTE_PATH}/${existing[0]}"
        existing=(`ssh ${REMOTE} "ls ${REMOTE_PATH}" | egrep '[0-9]{14}' | sort -n`)
    done
    if [ -n "${existing}" ]; then
        latest="${existing[$((${#existing[@]}-1))]}"
        ssh ${REMOTE} "cp -al ${REMOTE_PATH}/${latest} ${REMOTE_PATH}/${BACKUP_TIME}"
    fi
    rsync -aHz --numeric-ids --chmod=u+rw --delete ${RSYNC_EXCLUDES} ${BACKUP_PATH} ${REMOTE}:${REMOTE_PATH}/${BACKUP_TIME}/
}

if [ ! ${1} ]; then
    # upload backup
    timestart=`date +%s`
    CMD=`uploadBackup`;
    CMD_RET=$?
    timetotal=$((`date +%s`-${timestart}))
    if [ "${CMD_RET}" -ne 0 ];
    then
        raiseAlert "$NAGIOS_SERVICE_NAME" 2 "Backup Failed during uploadBackup. ${CMD}|in ${timetotal} sec"
    else
        raiseAlert "$NAGIOS_SERVICE_NAME" 0 "Backup Completed OK at ${DAY}|in ${timetotal} sec"
        exit 0
    fi
else
    # Test
    echo "Test Mode"
    raiseAlert "$NAGIOS_SERVICE_NAME" 0 "Backup Tested at ${DAY}|in ${timetotal} sec"
fi