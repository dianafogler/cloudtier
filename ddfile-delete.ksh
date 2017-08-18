#!/bin/ksh
#
# Name:         ddfile-delete.ksh
#
# Function:     This script will delete data older than retention  
#
# Input:
#       $1      Directory
#       $2	Retention  
#       $3	force
#
# Changes:
# 11/28/16 Diana Yang   New script
# 08/17/17 Diana Yang   Eliminate the need to specify the script directory
#################################################################


function show_usage {
print "usage: ddfile-delete.ksh -d <Directory> -r <Retention in days> -f <yes>" 
print "  -d : Directory\n  -r : Retention (in days)"
print "  -f : yes if old files should be deleted"
}


while getopts ":d:r:f:" opt; do
  case $opt in
    d ) dir=$OPTARG;;
    r ) ret=$OPTARG;;
    f ) confirm=$OPTARG;;
  esac
done

echo $dir $ret $confirm

# Check required parameters
if test $dir && test $ret 
then
  :
else
  show_usage
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
#echo " DIR is $DIR, the file is $DIR/file-in-sdir"
if [[ $DIR = "." ]]; 
then   DIR=`pwd`   
       echo $DIR
fi



if [[ ! -d $dir ]]; then
    print "Directory $dir does not exist"
    exit 1
fi
postfixn=`echo $dir | awk -F "/" '{print $NF}'`
/bin/rm $DIR/$postfixn-delete-list

if [[ $confirm = "yes" || $confirm = "Yes" || $confirm = "YES" ]] 
then
   echo "Delete files in directory $dir older than $ret days"
#   echo "$dir $ret $postfixn"
   find $dir -type f -mtime +$ret | grep -v "snapshot" >$DIR/$postfixn-delete-list 
  
   ls -l  $DIR/$postfixn-delete-list
   
   while IFS= read -r line
   do
      /bin/rm $line
       echo $line

       if [ $? -ne 0 ]; then
          echo "deletion failed"
          exit 1
       fi
   done < $DIR/$postfixn-delete-list
   
#   /bin/rm $DIR/$postfixn-delete-list
else
   echo "List the files in directory $dir"
   find $dir -type f -mtime +$ret |  grep -v "snapshot"
fi

