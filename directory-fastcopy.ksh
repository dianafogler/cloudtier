#!/bin/ksh
#
# Name:         directory-fastcopy.ksh
#
# Function:     This script will copy files in a directory from Data Doamin 
#               one mtree to another mtree following the same directory structure.
#               First DD secure login should be set up from this Linux server
#               to DD. The last field of mount point is assumed to be the same 
#               as the last field of mtree if mtree name is not provided.
#
# Show Usage: run the command to show the usage
#
# Changes:
# 08/17/16 Diana Yang   New script
#################################################################

function show_usage {
print "usage: mtree-fastcopy.ksh -d <Data Domain> -u <User> -s <Source Mount Point> 
-t <Target Mount Point> -b <directory> "
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Mount Point"
print "  -t : Target Mount Point\n  -b : Directory following Mount Point"
}


while getopts ":d:u:s:t:b:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    s ) sdir=$OPTARG;;
    t ) tdir=$OPTARG;;
    b ) filedir=$OPTARG;;
  esac
done

#echo $dd $user $sdir $tdir $filedir 

# Check required parameters
if test $dd && test $user && test $sdir && test $tdir && test $filedir
then
  :
else
  show_usage
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
#echo " DIR is $DIR, the file is $DIR/file-in-sdir"
if [[ $DIR = "." ]]; then
   DIR=`pwd`
   echo $DIR
fi


if [[ ! -d $sdir ]]; then
    print "Source Mount Point $sdir does not exist"
    exit 1
fi

if [[ ! -d $tdir ]]; then
    print "Target Mount Point $tdir does not exist"
    exit 1
fi


function get_mtree {
    sm=/data/col1/`echo $sdir | awk -F "/" '{print $NF}'`
    print "Source Mtree is $sm"

    tm=/data/col1/`echo $tdir | awk -F "/" '{print $NF}'`
    print "Target Mtree is $tm"
}

get_mtree

ssh $user@$dd "filesys fastcopy source $sm/$filedir destination $tm/$filedir force"

if [ $? -ne 0 ]; then
    echo "fastcopy script failed"
    exit 1
fi
