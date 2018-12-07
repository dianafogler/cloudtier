#!/bin/ksh
#
# Name:		backup-location-list.ksh
#
# Function:	List backup files locations (active tier or cloud tier) on Data Domain
#
# Input:
#	$1	Name of Data Domain 
#	$2	DD user. 
#	$3	Name of the file that has backup file paths. 
#
#	The file content example
#	/data/col1/oracleboost/ORCL_20181205_3jtk0vt9_1_1
#	/data/col1/oracleboost/ORCL_20181203_26tjrn5a_1_1
#
# Changes:
# 12/07/18 Diana Yang	new script 
#########################################################################

function show_usage {
echo "usage: backup-location-list.ksh -d <Data Domain> -u <Data Domain User> -f <file name>" 
echo "-d : Data Domain"
echo "-u : Data Domain User"
echo "-f : file name"
echo "  The file content example
       /data/col1/oracleboost/ORCL_20181205_3jtk0vt9_1_1
       /data/col1/oracleboost/ORCL_20181203_26tjrn5a_1_1 
"
}


function check_file {
   
   while IFS= read -r line
   do
#       echo $line
       echo "filesys report generate file-location path $line" >> $check_script
   done <"$DIR/$file"
}

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ $DIR = "." ]]; then
   DIR=`pwd`
fi


while getopts ":d:u:f:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    f ) file=$OPTARG;;
  esac
done

#echo $dd $file $user

# Check required parameters
if test $dd && test $user && test $file
then
  :
else
  show_usage
  exit 1
fi

if [[ ! -f $DIR/$file ]]; then
    echo "File $DIR/$file does not exist"
    exit 1
fi

if [[ ! -d $DIR/log ]]; then
    print " $DIR/log does not exist, create it"
    mkdir $DIR/log
    print " $DIR/log is created. Script continue"
fi

check_script=$DIR/check.ksh

echo "ssh $user@$dd << EOF" > $check_script
check_file
echo "EOF" >> $check_script
chmod 700 $check_script
$check_script

