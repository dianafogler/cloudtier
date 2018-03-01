
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
#################################################################


function show_usage {
print "usage: mtree-copy-retentionlock.ksh -o <full or partial> -d <Data Domain> -u <User> -s <Source Directory> -m <Source
 Mtree> -t <Target Directory> -n <Target Directory> -r <Comparing Days> -l <yes if retention lock should be added to the fi
le> -k <retention lock days>"
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

#echo $dd $user $sdir $tdir $ret $lock
echo $full $lock $lockday

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
     find . -type f |  grep -v "snapshot" > $DIR/file-in-sdir
     echo "full search"
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
    mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | sed 's/^.//`
   echo mid directory is $mdir
    if [[ ! -d $tdir$mdir ]];then
        mkdir -p $tdir$mdir
        userid=`ls -ld $sdir$mdir | awk '{print $3}'`
        usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
        echo userid is $userid groupid is $usergp
        chown -R $userid:$usergp $tdir$mdir
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
#        echo "reached 20"
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

function fastcopy_retentionlock {
while IFS= read -r line
do
   mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | sed 's/^.//'`
   echo directory is $sdir$mdir
   if [[ ! -d $tdir$mdir ]];then
        mkdir -p $tdir$mdir
#        userid=`/usr/bin/ls -dl $sdir$mdir`
        userid=`ls -ld $sdir$mdir | awk '{print $3}'`
        usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
        echo userid is $userid groupid is $usergp
        chown -R $userid:$usergp $tdir$mdir
    fi
    bfile=`echo $line | awk -F "/" '{print $NF}'`
    grep -i $line $DIR/file-in-tdir
    if [ $? -ne 0 ]; then
         echo "$line is not in $tdir, fastcopy"
         echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile >> $DIR/fastcopy.ksh

         locktime=$(/bin/date '+%Y%m%d%H%M' -d "+$lockday days")
         echo $locktime
         echo "touch -a -t $locktime $tdir$mdir/$bfile" >> $DIR/setretention.ksh
         let numline=$numline+1
#        echo $numline
    else
         echo "$line is already in $tdir directlry, skip"
    fi

    if [[ $numline -eq 20 ]]; then
#        echo "reached 20"
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

chmod 700 $DIR/setretention.ksh
$DIR/setretention.ksh

if [ $? -ne 0 ]; then
    echo "Set Retention failed"
    exit 1
fi

}


if [[ $lock = "yes" || $lock = "Yes" || $lock = "YES" ]]; then
   echo "#/bin/ksh" > $DIR/setretention.ksh
   echo "will set up retention lock"
   if test $lockday; then
    echo "run copy"
   fastcopy_retentionlock
   else
      echo "missing retention lock time expressed in days"
      show_usage
      exit 1
   fi
else
   echo "no retention lock"
   fastcopy
fi
