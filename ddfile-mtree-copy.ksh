#!/bin/ksh
#
# Name:         ddfile-mtree-copy.ksh
#
# Function:     This script will copy files from one mtree to another mtree
#               in the same Data Domain using DD fastcopy. This can be used 
#               to safeguard the files that can not be deleted by applications
#               or move data to a mtree that CloudTier can be set up. The script
#               is recommended to run once a day or at least once in 5 days. It
#               only copies data that have not been copied yet and it compares
#               the files in both mtree in less than "short retention" days which
#               is one of the command input
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/08/16 Diana Yang   New script
# 11/28/16 Diana Yang   Change script name and added explanation
# 01/27/17 Diana Yang   Add full or patial copy option
# 02/03/17 Diana Yang   It now can handle files in sub-directories.
# 08/17/17 Diana Yang	Eliminate the need to specify the script directory
#################################################################

function show_usage {
print "usage: ddfile-mtree-copy.ksh -o <full or partial> -d <Data Domain> -u
<User> -s <Source Directory> -m <Source Mtree> -t <Target Directory> -n <Targ
et Directory> -r <Comparing Days>"
print "  -o : full if running full synchronization (first time), no if script
 runs everyday"
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory\n  -m : Source Mtree (optional)"
print "  -t : Target Directory\n  -n : Target Mtree (optional)"
print "  -r : How recent days files will be copied (recommend 5, unit is day)
"
}


while getopts ":o:d:u:s:t:r:m:n:" opt; do
  case $opt in
    o ) full=$OPTARG;;
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    s ) sdir=$OPTARG;;
    t ) tdir=$OPTARG;;
    r ) ret=$OPTARG;;
    m ) sm=$OPTARG;;
    n ) tm=$OPTARG;;
  esac
done

#echo $dd $user $sdir $tdir $ret $lock
#echo $full

# Check required parameters
if test $full && test $dd && test $user && test $sdir && test $tdir
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
    print "Source Directory $sdir does not exist"
    exit 1
fi

if [[ $full = "full" || $full = "Full" || $full = "FULL" ]]; then
     cd $sdir
     echo "full search in directory $sdir"
     find . -type f |  grep -v "snapshot" > $DIR/file-in-sdir
else
     if test $ret; then
        cd $sdir
        find . -type f -mtime -$ret|  grep -v "snapshot" > $DIR/file-in-sdir
     else
        echo "Missing short retention"
        show_usage
        exit 1
     fi
fi

if [[ ! -d $tdir ]]; then
    print "Target Directory $tdir does not exist"
    exit 1
fi

if [[ $full = "full" || $full = "Full" || $full = "FULL" ]]; then
     echo "will run full synchronizsation"
     cd $tdir
     find . -type f | grep -v "snapshot" > $DIR/file-in-tdir
else
     if test $ret; then
        cd $tdir
        find . -type f  -mtime -$ret| grep -v "snapshot" > $DIR/file-in-tdir
     else
        echo "Missing short retention"
        show_usage
        exit 1
     fi
fi

function get_mtree {
if [[ -z $sm ]]; then
    sm=/data/col1/`echo $sdir | awk -F "/" '{print $NF}'`
    print "Source Mtree is not provided, we assume it is same as the last field of Source Directory"
    print "Source Mtree is $sm"
fi

if [[ -z $tm ]]; then
    tm=/data/col1/`echo $tdir | awk -F "/" '{print $NF}'`
    print "Target Mtree is not provided, we assume it is same as the last field of Target Directory"
    print "Target Mtree is $tm"
fi
}

get_mtree

let numline=0
echo "ssh $user@$dd << EOF" > $DIR/fastcopy.ksh
echo "filesys show space" >> $DIR/fastcopy.ksh
echo "filesys show compression" >> $DIR/fastcopy.ksh
echo "mtree list" >> $DIR/fastcopy.ksh

function fastcopy {
while IFS= read -r line
do
#   echo line is $line
    mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | awk -F "." '{print $2}'`
   echo mid directory is $mdir
    if [[ ! -d $tdir$mdir ]];then
        mkdir -p $tdir$mdir
        userid=`ls -ld $sdir$mdir | awk '{print $3}'`
        usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
        echo userid is $userid groupid is $usergp
        chown $userid:$usergp $tdir$mdir
    fi
    bfile=`echo $line | awk -F "/" '{print $NF}'`
#echo file is $bfile
    grep -i $line $DIR/file-in-tdir
    if [ $? -ne 0 ]; then
         echo "$line is not in $tdir, fastcopy"
         echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile >> $DIR/fastcopy.ksh
         let numline=$numline+1
#        echo $numline
    else
         echo "$line is already in $tdir directlry, skip"
    fi

    if [[ $numline -eq 20 ]]; then
        echo "reached 20"
        echo "EOF" >> $DIR/fastcopy.ksh
        chmod 700 $DIR/fastcopy.ksh
        $DIR/fastcopy.ksh

        if [ $? -ne 0 ]; then
          echo "fastcopy script failed"
          exit 1
        fi

        let numline=0
        echo "ssh $user@$dd << EOF" > $DIR/fastcopy.ksh
     fi

done < $DIR/file-in-sdir
echo "filesys show space" >> $DIR/fastcopy.ksh
echo "filesys show compression" >> $DIR/fastcopy.ksh
echo "mtree list" >> $DIR/fastcopy.ksh
echo "EOF" >> $DIR/fastcopy.ksh

chmod 700 $DIR/fastcopy.ksh
$DIR/fastcopy.ksh

if [ $? -ne 0 ]; then
    echo "fastcopy script failed"
    exit 1
fi
}


fastcopy
