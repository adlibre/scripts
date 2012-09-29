#!/bin/bash

# Rsync.net backup script - Backup to rsync target and send passive check result to Nagios/Icinga (NSCA)
#
# NB: No backup rotation is done. Assumes snapshots / rotation is done on the target.
#
# Adlibre Pty Ltd 2012

# Install:
# yum -y install nsca-client



## Config
BACKUP_PATH='/etc /root /srv/www'

## Constants
NAGIOS_DIR=/usr/sbin/
NAGIOS_CFG=/etc/nagios/
NAGIOS_SERVER=monitor.example.com
NAGIOS_PORT=5667
NAGIOS_SERVICE_NAME='Rsync.net Backup Daily'
LOCK='/tmp/rsync-net-in-progress.lock'
## end config

PATH="/sbin:/bin:/usr/sbin:/usr/bin:$PATH";
DAY=`date +'%F %T'`

# Sanity Checks

# Check to see if we are already running / locked, limit to one instance
if [ -f ${LOCK} ]; then
    echo "Already running, or locked"
    exit $99
fi

# Upon exit, remove lockfile.
trap "{ rm -f ${LOCK}; }" EXIT
touch ${LOCK};

#
# Send passive alert information to Nagios / Icinga
#
function raiseAlert {
    # $1 - Service name that has been set up on nagios/nagiosdev server
    # $2 - Return code 0=success, 1=warning, 2=critical
    # $3 - Message you want to send
    # <host_name>,<svc_description>,<return_code>,<plugin_output>
    if [ -f ${NAGIOS_DIR}send_nsca ]; then
        echo "`hostname`,$1,$2,$3" | ${NAGIOS_DIR}send_nsca -H ${NAGIOS_SERVER} \
        -p ${NAGIOS_PORT} -d "," -c ${NAGIOS_CFG}send_nsca.cfg > /dev/null;
        echo "Debug: Message Sent to Nagios: $1 $2 $3.";
    else
        echo "Warning: NSCA (Nagios) Plugin not found.";
    fi
}

# Command
function uploadBackup {
    rsync -aH --numeric-ids --delete ${BACKUP_PATH} rsync.net:`hostname -s`/
}

# upload backup
CMD=`uploadBackup`;
if [ $? -ne 0 ] ;
then
    raiseAlert "$NAGIOS_SERVICE_NAME" 2 "Backup Failed during uploadBackup. $CMD"
else
    raiseAlert "$NAGIOS_SERVICE_NAME" 0 "Backup Completed OK at $DAY"
    exit 0
fi
