#/bin/bash
#
# Name:         incremerge.ksh
#
# Function:     This script does Oracle rman incremental merge backup.
#               It can do full backup or incremental forever backup.
#               After this script, DD fastcopy script is recommended to run
#               to keep old backup.
#
# Show Usage: run the command to show the usage
#
# Changes:
# 08/03/18 Diana Yang   New script
# 08/29/18 Diana Yang   Add remote execute fastcopy script
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added,
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send
# you an alert.
#################################################################

. /home/oracle/.bash_profile

function show_usage {
echo "usage: incremerge.ksh -h <host> -o <Oracle_sid> -t <backup type> -m <Mount point> -s <Linux server>"
echo " -h : host (optional)"
echo " -o : ORACLE_SID (optional)"
echo " -t : backup type: Full or Incre"
echo " -m : Mount point"
echo " -s : linux server"
}

while getopts ":h:o:t:m:" opt; do
  case $opt in
    h ) host=$OPTARG;;
    o ) oraclesid=$OPTARG;;
    t ) type=$OPTARG;;
    m ) mount=$OPTARG;;
    s ) server=$OPTARG;;
  esac
done

# Check required parameters
if test $type && test $mount
then
  :
else
  show_usage
  exit 1
fi

if test $host
then
  :
else
  host=`hostname -s`
fi

if test $oraclesid
then
  export ORACLE_SID=$oraclesid
else
  :
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
echo $DATE_SUFFIX

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`

#echo $DATE_SUFFIX > $DIR/incremerge.time
echo $DATE_SUFFIX > /tmp/$host.$oraclesid.incremerge.time

if [[ -n $server ]]; then
     echo "copy $host.$oraclesid.incremerge.time to $server " >> $run.log
     scp /tmp/$host.$oraclesid.incremerge.time $server:/tmp/$host.$oraclesid.incremerge.time
     if [ $? -ne 0 ]; then
        echo "scp /tmp/$host.$oraclesid.incremerge.time failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run.log
        exit 1
     fi
fi



if [[ ! -d $DIR/log ]]; then
    echo " $DIR/log does not exist, create it"
    mkdir $DIR/log
fi

backup_dir=$mount/$host/$ORACLE_SID
full_dir=$backup_dir/incre/datafile
archive_dir=$backup_dir/archivelog
control_dir=$backup_dir/controlfile
temp_dir=$backup_dir/temp
run_log=$DIR/log/$host.$oraclesid.incremerge.$DATE_SUFFIX.log
#echo $host $ORACLE_SID $type

#trim log directory
find $DIR/log -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
    echo "del old logs in $DIR/log failed" >> $run_log
    exit 1
fi


if mountpoint -q "$mount"; then
#make directory
    echo "$mount is mount point \n"

    if [[ ! -d "$control_dir" ]]; then
       echo "Directory $control_dir does not exist, create it"
       if mkdir -p $control_dir; then
          echo "$control_dir is created"
       fi
    fi

    if [[ ! -d "$full_dir" ]]; then
       echo "Directory $full_dir does not exist, create it"
       if mkdir -p $full_dir; then
          echo "$full_dir is created"
       fi
    fi

    if [[ ! -d "$archive_dir" ]]; then
       echo "Directory $archive_dir does not exist, create it"
       if mkdir -p $archive_dir; then
          echo  "$archive_dir is created"
       fi
    fi

    if [[ ! -d "$temp_dir" ]]; then
       echo "Directory $temp_dir does not exist, create it"
       if mkdir -p $temp_dir; then
          echo "$temp_dir is created"
       fi
    fi

else
    echo "$mount is not a mount point"
    exit 1
fi

function full_backup {

#echo $full_dir $archive_dir $control_dir

echo "full backup started at " `/bin/date '+%Y%m%d%H%M%S'`

rman target / log $run_log << EOF
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '$control_dir/%d_%F.ctl';
CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT   '$full_dir/%d_%T_%U';
configure retention policy to redundancy 1;
configure retention policy to recovery window of 30 days;

delete noprompt datafilecopy all;
delete datafilecopy like '$full_dir/%';
#delete archivelog all completed before "sysdate-25';
backup incremental level 1 cumulative for recover of copy database;
#backup incremental level 0 for recover of copy database with tag "incre_update";
recover copy of database with tag "incre_update";
sql 'alter system switch logfile';
backup archivelog like '+FRA/%' format '$archive_dir/%d_%T_%U.log';
backup as copy archivelog like '+FRA/%' format '$archive_dir/%U' delete input;
backup as copy current controlfile format '$control_dir/$ORACLE_SID.ctl.$DATE_SUFFIX';

exit;

EOF

echo "full backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
}

function incre_backup {

#echo $temp_dir $archive_dir $control_dir

echo "Incremental backup started at " `/bin/date '+%Y%m%d%H%M%S'`

rman target / log $run_log << EOF
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '$control_dir/%d_%F.ctl';
CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT   '$temp_dir/%d_%T_%U';
configure retention policy to redundancy 1;
configure retention policy to recovery window of 30 days;

DELETE NOPROMPT OBSOLETE;
#delete archivelog all completed before "sysdate-25';
backup incremental level 1 for recover of copy database;
recover copy of database;
sql 'alter system switch logfile';
backup archivelog like '+FRA/%' format '$archive_dir/%d_%T_%U.log';
backup as copy archivelog like '+FRA/%' format '$archive_dir/%U' delete input;
backup as copy current controlfile format '$control_dir/$ORACLE_SID.ctl.$DATE_SUFFIX';

exit;

EOF

echo "Incremental merge finished at " `/bin/date '+%Y%m%d%H%M%S'`

}

if [[ $type = "full" || $type = "Full" || $type = "FULL" ]]; then
     echo "Full backup"
     full_backup
     if [ $? -ne 0 ]; then
        echo "full backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run.log
     else
        echo "full backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run.log
     fi
elif [[  $type = "incre" || $type = "Incre" || $type = "INCRE" ]]; then
     echo "incremental merge"
     incre_backup
     if [ $? -ne 0 ]; then
        echo "incremental merge backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run.log
     else
        echo "incremental merge backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run.log
     fi
else
     echo "backup type entered is not correct. It should be full or incre"
     exit 1
fi
