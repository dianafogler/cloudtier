#!/bin/ksh
#
# Name:		oracle-restore-seq-list.ksh	
#
# Function:	Generate a list of Oracle backup files needed for Oracle restore 
#               using DD Boost RMAN agent
#
# Input:
#	$1	Oracle SID
#	$2	Restore to archivelog sequence number 
#
# Changes:
# 11/21/18 Diana Yang	New script 
#################################################################

function show_usage {
print "usage: oracle-restore-seq-list.ksh -i <ORACLE_SID> -s <sequence> "
print "  -i : Oracle instance name\n  -s : archivelog sequence'"
}

function restore_preview {
  rman target / << EOF 
  RUN
  {
  set until sequence $SEQ;
  RESTORE DATABASE preview;
  }
EOF
}


while getopts ":i:s:" opt; do
  case $opt in
    i ) SID=$OPTARG;;
    s ) SEQ=$OPTARG;;
  esac
done

#echo $SID $TIME $DATE

# Check required parameters
if test $SID && test $SEQ 
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
