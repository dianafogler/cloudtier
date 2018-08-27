#!/bin/ksh
#
# Name:         ddfile-mtree-copy.ksh
#
# Function:     This script will copy files from one mtree to another mtree
#               in the same Data Domain using DD fastcopy. This can be used
#               to keep the long term backup data in a separate mtree even the
#               orginal backup data in orginal mtree is deleted by applications.
#               The difference between this script and directory fastcopy is
#               that this script only copy new backup files to the mtree the
#               CloudTier is setup. The directory fastcopy also delete data and
#               should not be used in this situation. The script
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
# 08/17/17 Diana Yang   Eliminate the need to specify the script directory
# 03/01/18 Diana Yang   Handle wild charactor in a directory
# 05/03/18 Diana Yang   Skip open file
# 06/28/18 Diana Yang   Add a log directory and logs for troubleshooting
# 07/17/18 Diana Yang   Add begin time and end time to track the process
# 07/19/18 Diana Yang   Add force option to fastcopy to make sure all necessary files are copied
# 07/30/18 Diana Yang   Search 2 more days data in target directory to make sure all files are found
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added,
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send
# you an alert.
#################################################################

function show_usage {
print "usage: ddfile-mtree-copy.ksh -o <full or partial> -d <Data Domain> -u
<User> -s <Source Directory> -m <Source Mtree> -t <Target Directory> -n <Targ
et Directory> -r <Comparing Days>"
print "  -o : full if running full synchronization (first time), no if script
 runs everyday"
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory\n  -m : Source Mtree (optional, start with /data/col1/,  \n If source Mtree is not prov
ided, we assume it is same as the last field of Source Directory)"
print "  -t : Target Directory\n  -n : Target Mtree (optional, start with /data/col1/,  \n If target Mtree is not prov
ided, we assume it is same as the last field of Target Directory)"
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

let tret=$ret+2

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`


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


if [[ ! -d $DIR/log ]]; then
    print " $DIR/log does not exist, create it"
    mkdir $DIR/log
fi

fastcopy_ksh_log=$DIR/log/ft_ksh_log.$DATE_SUFFIX
filesdir=$DIR/log/filesdir.$DATE_SUFFIX
filetdir=$DIR/log/filetdir.$DATE_SUFFIX
fastcopy_ksh=$DIR/fastcopy.ksh
fastcopy_log=$DIR/log/ft_log.$DATE_SUFFIX
run_log=$DIR/log/ddfile-mtree-copy.$DATE_SUFFIX.log

#trim log directory
find $DIR/log -type f -mtime +30 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
    echo "del old logs in $DIR/log failed" >> $run_log
    exit 1
fi


if [[ ! -d $sdir ]]; then
    print "Source Directory $sdir does not exist"
    exit 1
fi

if [[ $full = "full" || $full = "Full" || $full = "FULL" ]]; then
     cd $sdir
     find . -type f |  grep -v "snapshot" > $filesdir
     echo "full search in source directory $sdir at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
else
     if test $ret; then
        cd $sdir
        find . -type f -mtime -$ret|  grep -v "snapshot" > $filesdir
        echo "Search last $ret days only in source directory $sdir at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
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
     echo "will run full synchronizsation" >> $run_log
     cd $tdir
     find . -type f | grep -v "snapshot" > $filetdir
     echo "full search in target directory $tdir at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
else
     if test $ret; then
        cd $tdir
        find . -type f  -mtime -$ret| grep -v "snapshot" > $filetdir
        echo "Search last $ret days only in target directory $tdir at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
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
echo "begin fastcopy at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
while IFS= read -r line
do
#   echo line is $line
    filename=$sdir${line:1}
#   fuser $filename
    if [[ `fuser $filename` -eq 0 ]]; then
#        echo file $filename is not open file
        mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | sed 's/^.//`
        echo directory is $sdir$mdir >> $run_log
        if [[ ! -d $tdir$mdir ]];then
           mkdir -p $tdir$mdir
           userid=`ls -ld $sdir$mdir | awk '{print $3}'`
           usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
           echo userid is $userid groupid is $usergp >> $run_log
           chown -R $userid:$usergp $tdir$mdir
        fi
        bfile=`echo $line | awk -F "/" '{print $NF}'`
#echo file is $bfile
        grep -i $line $filetdir
        if [ $? -ne 0 ]; then
#           echo "$line is not in $tdir, will copy it from source to target" >> $run_log
           echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force>> $fastcopy_ksh
           echo fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> $fastcopy_log
           let numline=$numline+1
#          echo $numline
        else
           echo "$line is already in $tdir directlry, skip" >> $run_log
        fi

        if [[ $numline -eq 20 ]]; then
#          echo "reached 20"
           echo "EOF" >> $fastcopy_ksh
           chmod 700 $fastcopy_ksh
          $fastcopy_ksh >> $fastcopy_ksh_log 2>&1

           if [ $? -ne 0 ]; then
              echo "fastcopy script failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
           fi

           let numline=0
           echo "ssh $user@$dd << EOF" > $fastcopy_ksh
        fi
    fi

done < $filesdir
echo "filesys show space" >> $fastcopy_ksh
echo "filesys show compression" >> $fastcopy_ksh
echo "mtree list" >> $fastcopy_ksh
echo "EOF" >> $fastcopy_ksh

chmod 700 $fastcopy_ksh
$fastcopy_ksh >> $fastcopy_ksh_log 2>&1

if [ $? -ne 0 ]; then
    echo "fastcopy script failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run.log
fi

echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
}

fastcopy
