#!/bin/ksh
#
# Name:         mtree-fastcopy.ksh
#
# Function:     This script will copy files from one mtree to another mtree
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
-m <Source Mtree> -t <Target Mount Point> -n <Target Mtree> "
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Mount Point\n  -m : Source Mtree (optional)"
print "  -t : Target Mount Point\n  -n : Target Mtree (optional)"
}


while getopts ":d:u:s:t:m:n:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    s ) sdir=$OPTARG;;
    t ) tdir=$OPTARG;;
    m ) sm=$OPTARG;;
    n ) tm=$OPTARG;;
  esac
done

#echo $dd $user $sdir $tdir $ret $lock
#echo $full

# Check required parameters
if test $dd && test $user && test $sdir && test $tdir
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
if [[ -z $sm ]]; then
    sm=/data/col1/`echo $sdir | awk -F "/" '{print $NF}'`
    print "Source Mtree is not provided, we assume it is same as the last field of Source Mount Point"
    print "Source Mtree is $sm"
fi

if [[ -z $tm ]]; then
    tm=/data/col1/`echo $tdir | awk -F "/" '{print $NF}'`
    print "Target Mtree is not provided, we assume it is same as the last field of Target Mount Point"
    print "Target Mtree is $tm"
fi
}

get_mtree

ssh $user@$dd "filesys fastcopy source $sm destination $tm force"

if [ $? -ne 0 ]; then
    echo "fastcopy script failed"
    exit 1
fi
