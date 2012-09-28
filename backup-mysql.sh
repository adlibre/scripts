#!/bin/bash

# Adlibre 2012-08-30 Backup MySQL databases and send passive check result to Nagios/Icinga (NSCA)

## Config
PASS=`cat /etc/mysql_root_password`
BACKUPDIR='/srv/backup'
KEEP='30'
NAGIOS_DIR=/usr/sbin/
NAGIOS_CFG=/etc/nagios/
NAGIOS_SERVER=monitor.example.com
NAGIOS_PORT=5667
NAGIOS_SERVICE_NAME='MySQL Dump Daily'
LOCK='/tmp/mysql-dump-in-progress.lock'
##

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

# Init
DATE=`date +%F`
cd $BACKUPDIR;

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

function doBackup {    
    # do the backup
    mysqldump --all-databases --opt --password=${PASS} --user=root > ${BACKUPDIR}/${DATE}.mysql.dump ;
}

function delBackup {
    # delete the old backups
    find $BACKUPDIR -name "*.dump.gz" -mtime $KEEP -exec rm -f {} \;
}

function compressBackup {
    # Gzip
    gzip -f -9 --rsyncable $BACKUPDIR/$DATE.*.dump;
}

function linkLatest {
    # Latest link
    ln -f ${DATE}.mysql.dump.gz ${BACKUPDIR}/latest.mysql.dump.gz
}

CMD=`doBackup`;
if [ $? -ne 0 ] ;
then
    raiseAlert "$NAGIOS_SERVICE_NAME" 2 "Backup Failed during doBackup. $CMD"
    exit 99;
fi

CMD=`delBackup`;
if [ $? -ne 0 ] ;
then
    raiseAlert "$NAGIOS_SERVICE_NAME" 2 "Backup Failed during delBackup. $CMD"
    exit 99;
fi

CMD=`compressBackup`;
if [ $? -ne 0 ] ;
then
    raiseAlert "$NAGIOS_SERVICE_NAME" 2 "Backup Failed during compressBackup. $CMD"
    exit 99;
fi

CMD=`linkLatest`;
if [ $? -ne 0 ] ;
then
    raiseAlert "$NAGIOS_SERVICE_NAME" 2 "Backup Failed during linkLatest. $CMD"
    exit 99;
fi

# default exit
raiseAlert "$NAGIOS_SERVICE_NAME" 0 "Backup Completed OK at $DAY"
exit 0
