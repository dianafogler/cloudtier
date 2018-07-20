#!/bin/ksh
#
# Name:         mtree-copy-retentionlock.ksh
#
# Function:     This script will copy files from one mtree to another mtree
#               and set retention lock parameter on the copied files
#               in the same Data Domain using DD fastcopy. This can be used
#               to safeguard the files so that these files can not be deleted
#               by applications until their age reach the retention. The script
#               is recommended to run once a day or at least once in 5 days. It
#               only copies data that have not been copied yet. It has two options
#               to compare the files in both directories. One option is comparing
#               all files in both director. This is used in the first time copy or
#               the files have not been copied for a while. The other option is
#               comparing files less  than "short retention". This used in daily
#               schedule jobs. The "short retetion " is recommended to be 5 days.
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/08/16 Diana Yang   New script
# 11/28/16 Diana Yang   Change script name and added explanation
# 01/26/17 Diana Yang   Add retention lock on the copied data
# 01/27/17 Diana Yang   Add full or patial copy option
# 02/03/17 Diana Yang   It now can handle files in sub-directories.
# 03/01/18 Diana Yang   Eliminate the need to specify the script directory
# 03/01/18 Diana Yang   Handle wild charactor in a directory
# 05/03/18 Diana Yang   Skip open file
# 06/28/18 Diana Yang   Add a log directory and logs for troubleshooting
# 07/17/18 Diana Yang   Add begin time and end time to track the process
# 07/19/18 Diana Yang   Add force option to fastcopy to make sure all necessary files are copied
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added,
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send
# you an alert.
#################################################################


function show_usage {
print "usage: mtree-copy-retentionlock.ksh -o <full or partial> -d <Data Domain> -u <User> -s <Source Directory> -m <Source
Mtree> -t <Target Directory> -n <Target Mtree> -r <Comparing Days> -l <yes if retention lock should be added to the file
> -k <retention lock days>"
print "  -o : full if running full synchronization (first time), no if script runs everyday"
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory\n  -m : Source Mtree (optional)"
print "  -t : Target Directory\n  -n : Target Mtree (optional)"
print "  -r : How recent days files will be copied (recommend 5, unit is day)"
print "  -l : yes if retention lock should be set on copied file\n  -k : Retention Lock in Days"
}


while getopts ":o:d:u:s:t:r:m:n:l:k:" opt; do
  case $opt in
    o ) full=$OPTARG;;
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    s ) sdir=$OPTARG;;
    t ) tdir=$OPTARG;;
    r ) ret=$OPTARG;;
    m ) sm=$OPTARG;;
    n ) tm=$OPTARG;;
    l ) lock=$OPTARG;;
    k ) lockday=$OPTARG;;
  esac
done

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`

#echo $dd $user $sdir $tdir $ret $lock
#echo $full $lock $lockday

# Check required parameters
if test $full && test $dd && test $user && test $sdir && test $tdir && test $lock
then
  :
else
  show_usage
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
#echo " DIR is $DIR"
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
setret_ksh=$DIR/setretention.ksh
setret_log=$DIR/log/setret_log.$DATE_SUFFIX
run_log=$DIR/log/mtree-copy-retentionlock.$DATE_SUFFIX.log

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
echo "ssh $user@$dd << EOF" > $fastcopy_ksh
echo "filesys show space" >> $fastcopy_ksh
echo "filesys show compression" >> $fastcopy_ksh
echo "mtree list" >> $fastcopy_ksh

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

function fastcopy_retentionlock {
echo "begin fastcopy at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
while IFS= read -r line
do
#   echo line is $line
    filename=$sdir${line:1}
#   fuser $filename
    if [[ `fuser $filename` -eq 0 ]]; then
#        echo file $filename is not open file
       mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | sed 's/^.//'`
       echo directory is $sdir$mdir >> $run_log
       if [[ ! -d $tdir$mdir ]];then
           mkdir -p $tdir$mdir
#          userid=`/usr/bin/ls -dl $sdir$mdir`
           userid=`ls -ld $sdir$mdir | awk '{print $3}'`
           usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
           echo userid is $userid groupid is $usergp >> $run_log
           chown -R $userid:$usergp $tdir$mdir
       fi
       bfile=`echo $line | awk -F "/" '{print $NF}'`
       grep -i $line $filetdir
       if [ $? -ne 0 ]; then
           echo "$line is not in $tdir, will copy it from source to target" >> $run_log
           echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> $fastcopy_ksh
           echo fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> $fastcopy_log

           locktime=$(/bin/date '+%Y%m%d%H%M' -d "+$lockday days")
           echo "this file $line will be locked until $locktime" >> $run_log
           echo "echo file $tdir$mdir/$bfile cannot be delete until $locktime" >> $setret_ksh
           echo "touch -a -t $locktime $tdir$mdir/$bfile" >> $setret_ksh
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
              echo "fastcopy script failed when copying $line" >> $run_log
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
    echo "fastcopy script failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
else
    echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
fi

echo "begin setting retention lock at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
chmod 700 $setret_ksh
$setret_ksh > $setret_log

if [ $? -ne 0 ]; then
    echo "Set Retention failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
else
    echo "setting retention lock finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
fi

}


if [[ $lock = "yes" || $lock = "Yes" || $lock = "YES" ]]; then
   echo "#/bin/ksh" > $setret_ksh
   echo "will set up retention lock" >> $run_log
   if test $lockday; then
    echo "retention lock days is $lockday" >> $run_log
   fastcopy_retentionlock
   else
      echo "missing retention lock time expressed in days"
      show_usage
      exit 1
   fi
else
   echo "no retention lock" >> $run_log
   fastcopy
fi

if test $userid; then
   echo match the ownership to original directory >> $run_log
   chown -R $userid:$usergp $tdir
else
   echo there is no new files in $sdir >> $run_log
fi
