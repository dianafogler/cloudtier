#!/bin/ksh
#
# Name:         mtree-fullcopy-retentionlock.ksh
#
# Function:     This script will copy all files from one mtree to another mtree's 
#		new directory and set retention lock parameter on the copied files 
#               in the same Data Domain using DD fastcopy. This can be used
#               to safeguard the files so that these files can not be deleted 
#               by applications until their age reach the retention. The new 
#		directory is named by time at its creation. 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/08/16 Diana Yang   New script
# 11/28/16 Diana Yang   Change script name and added explanation
# 01/26/17 Diana Yang	Add retention lock on the copied data 
# 02/03/17 Diana Yang   It now can handle files in sub-directories.
#################################################################

DIR=/home/oracle/scripts/cloud

function show_usage {
print "usage: mtree-fullcopy-retentionlock.ksh -d <Data Domain> -u <User> -s <Source Directory> -m <Source Mtree> -t <Target Directory> -n <Target Directory> -k <retention lock days>" 
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory\n  -m : Source Mtree (optional)"
print "  -t : Target Directory\n  -n : Target Mtree (optional)"
print "  -k : Retention Lock in Days" 
}


while getopts ":d:u:s:t:m:n:k:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    s ) sdir=$OPTARG;;
    t ) tdir=$OPTARG;;
    m ) sm=$OPTARG;;
    n ) tm=$OPTARG;;
    k ) lockday=$OPTARG;;
  esac
done

#echo $dd $user $sdir $tdir $ret $lock
#echo $lockday

# Check required parameters
if test $dd && test $user && test $sdir && test $tdir && test $lockday
then
  :
else
  show_usage
  exit 1
fi

if [[ ! -d $sdir ]]; then
    print "Source Directory $sdir does not exist"
    exit 1
fi

cd $sdir
find . -type f |  grep -v "snapshot" > $DIR/file-in-sdir 

if [[ ! -d $tdir ]]; then
    print "Target Directory $tdir does not exist"
    exit 1
fi

cd $tdir
find . -type f | grep -v "snapshot" > $DIR/file-in-tdir 

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


function fastcopy_retentionlock {
timedir=rl`/bin/date '+%Y%m%d%H%M%S'`
newtdir=$tdir/$timedir
mkdir $newtdir
userid=`ls -ld $sdir | awk '{print $3}'`
usergp=`ls -ld $sdir | awk '{print $4}'`
#echo userid is $userid groupid is $usergp
chown $userid:$usergp $newtdir

while IFS= read -r line
do
   mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | awk -F "." '{print $2}'`
#   echo directory is $sdir$mdir
   if [[ ! -d $newtdir$mdir ]];then
	mkdir -p $newtdir$mdir
#        userid=`/usr/bin/ls -dl $sdir$mdir` 
        userid=`ls -ld $sdir$mdir | awk '{print $3}'`
        usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
        echo userid is $userid groupid is $usergp
        chown $userid:$usergp $newtdir$mdir
   fi

   bfile=`echo $line | awk -F "/" '{print $NF}'`
   echo filesys fastcopy source $sm$mdir/$bfile destination $tm/$timedir$mdir/$bfile >> $DIR/fastcopy.ksh

    locktime=$(/bin/date '+%Y%m%d%H%M' -d "+$lockday days")
#    echo $locktime
    echo "touch -a -t $locktime $newtdir$mdir/$bfile" >> $DIR/setretention.ksh
    let numline=$numline+1
#   echo $numline

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


echo "#/bin/ksh" > $DIR/setretention.ksh
fastcopy_retentionlock
