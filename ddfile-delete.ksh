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
#################################################################

function show_usage {
print "usage: ddfile-delete.ksh -d <Directory> -r <Retention in days> -f <force>" 
print "  -d : Directory\n  -r : Retention (in days)"
print "  -f : yes"
}


while getopts ":d:r:f:" opt; do
  case $opt in
    d ) dir=$OPTARG;;
    r ) ret=$OPTARG;;
    f ) yes=$OPTARG;;
  esac
done

echo $dir $ret $yes

# Check required parameters
if test $dir && test $ret 
then
  :
else
  show_usage
  exit 1
fi

if [[ ! -d $dir ]]; then
    print "Directory $dir does not exist"
    exit 1
fi

if test $yes
then
   find $dir -type f -mtime +$ret  -exec /bin/rm {} \; 

   if [ $? -ne 0 ]; then
    echo "deletion failed"
    exit 1
fi
else
   echo directory is $dir
   #"find $dir -type f -mtime +$ret |  grep -v "snapshot" " 
   find $dir -type f -mtime +$ret |  grep -v "snapshot"
fi

