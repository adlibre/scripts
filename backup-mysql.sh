#!/bin/bash

# Adlibre 2012-13: Backup MySQL databases and send passive check result to Nagios/Icinga (NSCA)

# Install:
# yum -y install nsca-client

## Source config file
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -e "${DIR}/config" ]; then
  . ${DIR}/config
fi

## Config
PASS=`cat /etc/mysql_root_password`
USER=${USER-root}
HOST=${HOST-localhost}
BACKUPDIR=${BACKUPDIR-/srv/backup}
KEEP=${KEEP-30}
NAGIOS_SERVER=${NAGIOS_SERVER-monitor.example.com}
NAGIOS_SERVICE_NAME=${NAGIOS_SERVICE_NAME-MySQL Dump Daily}
LOCKFILE="/var/run/`basename $0 | sed s/\.sh// `.pid"
##

DAY=`date +'%F %T'`

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

# Init
DATE=`date +%F`
cd $BACKUPDIR;

# Check for mysql options file
if [ ! -e "${HOME}/.my.cnf" ] || [ ! "`mysql -s -e \"SELECT 1\" >/dev/null 2>&1; echo $?`" -eq 0 ]; then
  MYAUTH="--password=${PASS} --user=${USER-root} -h ${HOST-localhost}"
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
    fi
}

function doBackup {    
    # do the backup
    mysqldump --single-transaction --all-databases --flush-logs --opt --ignore-table=mysql.event ${MYAUTH} > ${BACKUPDIR}/${DATE}.mysql.dump ;
}

function delBackup {
    # delete the old backups
    find $BACKUPDIR -name "*.dump.gz" -mtime +$KEEP -exec rm -f {} \;
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
