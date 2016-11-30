#!/bin/ksh
#
# Name:		oracle-restore-list.ksh	
#
# Function:	Generate a list of Oracle backup files needed for Oracle restore 
#
# Input:
#	$1	Oracle SID
#	$2	Restore Point-in-Time time 
#
# Changes:
# 10/15/16 Diana Yang	New script 
#################################################################

function show_usage {
print "usage: oracle-restore-list.ksh -i <ORACLE_SID> -t <restore time 'YYYY/MM/DD HH24:MI:SS'> "
print "  -i : Oracle instance name\n  -t : restore time like '2016/09/23 12:27:00'"
}

function restore_preview {
  rman target / << EOF 
  RUN
  {
  set until time "to_date('$TIME','YYYY/MM/DD HH24:MI:SS')";
  RESTORE DATABASE preview;
  }
EOF
}


while getopts ":i:t:" opt; do
  case $opt in
    i ) SID=$OPTARG;;
    t ) TIME=$OPTARG;;
  esac
done

DATE=`echo $TIME | awk '{print $1}'`
#echo $SID $TIME $DATE

# Check required parameters
if test $SID && test $DATE 
then
  :
else
  show_usage
  exit 1
fi

export ORACLE_SID=$SID

#restore_preview | grep -i handle
restore_preview | grep -i handle | awk '{print "/data/col1/" $4 "/" $2}'
#list=`restore_preview | grep -i handle | awk '{print $2}'`
#echo $list
