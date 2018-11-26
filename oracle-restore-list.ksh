#!/bin/ksh
#
# Name:		oracle-restore-list.ksh	
#
# Function:	Generate a list of Oracle backup files needed for Oracle restore 
# 		using DD Boost RMAN agent	
#
# Input:
#	$1	Oracle SID
#	$2	Restore Point-in-Time time 
#
# Changes:
# 10/15/16 Diana Yang	New script 
# 11/26/18 Diana Yang	Add support to RMAN agent 4.5 and 4.6 
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

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
#echo " DIR is $DIR"
if [[ $DIR = "." ]]; then
   DIR=`pwd`
#   echo $DIR
fi

orafile=$DIR/ora-pre-lists

#restore_preview | grep -i handle
restore_preview | grep -i handle > $orafile

while IFS= read -r line
do
  stu=`echo $line | awk '{print $4}' |  awk -F "/" '{print $NF}'`
  a=`echo $line | awk '{print $2}' | awk -F '/' '{print $1}'`
  if [[ $a = "." ]]; then
    file=`echo $line | awk '{print $2}'| sed 's/^.\///'`
  else
    file=`echo $line | awk '{print $2}'`
  fi
#  echo "stu is $stu, file is $file"
  echo /data/col1/${stu}/${file}
done < $orafile
