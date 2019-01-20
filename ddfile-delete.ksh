#!/bin/ksh
#
# Name:         ddfile-delete.ksh
#
# Function:     This script will delete data older than specifed days  
#
# Input:
#       $1      Directory
#       $2	Retention  
#       $3	force
#
# Changes:
# 11/28/16 Diana Yang   New script
# 08/17/17 Diana Yang   Eliminate the need to specify the script directory
# 07/17/18 Diana Yang   change description and add more messages
# 01/11/19 Diana Yang   change description and add more messages
#################################################################


function show_usage {
print "usage: ddfile-delete.ksh -d <Directory> -r <specified day> -f <yes/no>" 
print "  -d : Directory\n  -r : specified day" 
print "  -f : yes if old files should be deleted, no if only list the files"
}


while getopts ":d:r:f:" opt; do
  case $opt in
    d ) dir=$OPTARG;;
    r ) ret=$OPTARG;;
    f ) confirm=$OPTARG;;
  esac
done

print "#the script will delete files in $dir longer than the specified \n"

# Check required parameters
if test $dir && test $ret 
then
  :
else
  show_usage
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ $DIR = "." ]]; 
then   DIR=`pwd`   
   echo "#the scripts directory is ${DIR}"
else
   echo "#the script directory is ${DIR}"
fi



if [[ ! -d $dir ]]; then
    print "#Directory $dir does not exist"
    exit 1
fi
postfixn=`echo $dir | awk -F "/" '{print $NF}'`

echo "#postfixn is $postfixn"

if [[ -f $DIR/$postfixn-delete-list ]]; then
   /bin/rm $DIR/$postfixn-delete-list
fi

if [[ $confirm = "yes" || $confirm = "Yes" || $confirm = "YES" ]] 
then
   echo "#Delete files in directory $dir older than $ret days"
#   echo "$dir $ret $postfixn"
   echo "#find all files that are older than $ret and store them in file $DIR/$postfixn-${ret}-delete"
   find $dir -type f -mtime +$ret | grep -v "snapshot" >$DIR/$postfixn-${ret}-delete 
  
   ls -l  $DIR/$postfixn-${ret}-delete
   
   while IFS= read -r line
   do
      /bin/rm $line
       echo "#deleted $line"

       if [ $? -ne 0 ]; then
          echo "#deletion failed"
          exit 1
       fi
   done < $DIR/$postfixn-${ret}-delete
  
echo "#deletion finished"
   /bin/rm $DIR/$postfixn-${ret}-delete

   find $dir -type d -empty -delete
else
   echo "#List the files in directory $dir"
#   find $dir -type f -mtime +$ret |  grep -v "snapshot" > $DIR/$postfixn-$ret-list
   find $dir -type f |  grep -v "snapshot" > $DIR/$postfixn-$ret-list
   ls $DIR/$postfixn-$ret-list
   echo "#The files found on DD is listed below"
   echo "# "
   echo "--------------------"

   while IFS= read -r line
   do
      /bin/ls -l $line
   done < $DIR/$postfixn-$ret-list

echo "#ls finished"
#   /bin/rm $DIR/$postfixn-$ret-list

   find $dir -type d -empty -print
fi

