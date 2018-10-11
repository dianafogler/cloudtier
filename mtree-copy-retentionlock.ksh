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
# 07/30/18 Diana Yang   Search 2 more days data in target directory to make sure all files are found
# 09/20/18 Diana Yang   Add concurrent fastcopy processes to speed up performance 
# 10/02/18 Diana Yang   Add a logic to exit with exit code 2 if no new backup files are discovered.
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added, 
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send 
# you an alert.
#################################################################


function show_usage {
print "usage: mtree-copy-retentionlock.ksh -o <full or partial> -d <Data Domain> -u <User> 
-s <Source Directory> -m <Source Mtree> -t <Target Directory> -n <Target Mtree> 
-r <Comparing Days> -l <yes if retention lock should be added to the file> 
-k <retention lock days> -c <concurrent processes>"
print "\noption detail"
print "  -o : full if running full synchronization (first time), no if script runs everyday"
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory\n  -m : Source Mtree (optional,  start with /data/col1/ 
If source Mtree is not provided, we assume it is same as the last field of Source Directory)"
print "  -t : Target Directory\n  -n : Target Mtree (optional, start with /data/col1/ 
If target Mtree is not provided, we assume it is same as the last field of Target Directory)"
print "  -r : How recent days files will be copied (recommend 5, unit is day)"
print "  -l : yes if retention lock should be set on copied file\n  -k : Retention Lock in Days"
print "  -c : number of concurrent fastcopy processes (optional, default is 1)"
}


while getopts ":o:d:u:s:t:r:m:n:l:k:c:" opt; do
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
    c ) numcon=$OPTARG;;
  esac
done

let tret=$ret+2

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

if test $numcon
then
  :
else
  let numcon=1
fi
  
echo "number of concurrent processes is $numcon"

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

filesdir=$DIR/log/filesdir.$DATE_SUFFIX
filetdir=$DIR/log/filetdir.$DATE_SUFFIX
setret_ksh=$DIR/setretention.ksh
setret_log=$DIR/log/setret_log.$DATE_SUFFIX
run_log=$DIR/log/mtree-copy-retentionlock.$DATE_SUFFIX.log

#trim log directory
find $DIR/log -type f -mtime +7 -exec /bin/rm {} \;

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
     echo "full search in source directory $sdir started at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log 
     find . -type f |  grep -v "snapshot" > $filesdir
     echo "full search in source directory $sdir finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log 
     if [[ ! -s  $filesdir ]]; then
        echo "There is no files in $sdir" >> $run_log
        echo "This program will exit with exit code 2" >> $run_log
        exit 2
     fi
else
     if test $ret; then
        cd $sdir
        echo "Search last $ret days only in source directory $sdir started at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log 
        echo "Search range is from " `/bin/date -d" -$ret day"`  "to" `/bin/date` >> $run_log
        find . -type f -mtime -$ret|  grep -v "snapshot" > $filesdir
        echo "Search last $ret days only in source directory $sdir finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
        if [[ ! -s  $filesdir ]]; then
           echo "There is no new files discovered in $sdir" >> $run_log
           echo "This program will exit with exit code 2"  >> $run_log
	   exit 2 
        fi 
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
     echo "full search in target directory started $tdir at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
     find . -type f | grep -v "snapshot" > $filetdir
     echo "full search in target directory finished $tdir at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
else
     if test $ret; then
        cd $tdir
        echo "Search last $tret days only in target directory $tdir started at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
        echo "Search range is from " `/bin/date -d" -$ret day"`  "to" `/bin/date` >> $run_log
        find . -type f  -mtime -$tret| grep -v "snapshot" > $filetdir
        echo "Search last $tret days only in target directory $tdir finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
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

let c=1
while [[ $c -le $numcon ]]
do

    fastcopy_ksh_log[$c]=$DIR/log/ft${c}_ksh_log.$DATE_SUFFIX
    fastcopy_ksh[$c]=$DIR/fastcopy${c}.ksh
    fastcopy_log[$c]=$DIR/log/ft${c}_log.$DATE_SUFFIX
    echo "ssh $user@$dd << EOF" > ${fastcopy_ksh[$c]}
###debug start
#echo ${fastcopy_ksh_log[$c]}, ${fastcopy_ksh[$c]}, ${fastcopy_log[$c]}
### dedug done
    let c=$c+1
done

let numline=0
let c=1
let tot=0

function fastcopy {
echo "begin fastcopy at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
while IFS= read -r line
do
#   echo line is $line
    filename=$sdir${line:1}
#   fuser $filename
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
        if [[ `fuser $filename` -eq 0 ]]; then
#          echo file $filename is not open file
           echo "$line is not in $tdir, will copy it from source to target" >> $run_log
           echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_ksh[$c]}
###debug start
#           echo  ${fastcopy_ksh[$c]}
####debug stop
           echo fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_log[$c]}
           let numline=$numline+1
           let tot=$tot+1
####debug start
#          echo numline is $numline
#          echo tot is $tot
###debug stop
        fi
     else
           echo "$line is already in $tdir directlry, skip" >> $run_log
     fi

     if [[ $numline -eq 20 ]]; then
#        echo "reached 20"
        echo "EOF" >> ${fastcopy_ksh[$c]}
#        echo "if [ "\$\?" -ne 0 ]; then" >> ${fastcopy_ksh[$c]}
#        echo "    echo \"fastcopy script failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> "\$"run_log " >> ${fastcopy_ksh[$c]} 
#        echo "fi" >> ${fastcopy_ksh[$c]} 
        chmod 700 ${fastcopy_ksh[$c]} 
        
        let numline=0
        let c=$c+1
     fi

     if [[ $tot -eq 20*$numcon ]]; then 
         echo "tot is $tot. run fastcopy"
         psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

         while [[ $psup -gt 0 ]] 
            do
###debug start
echo sleep 2
###debug stop
            sleep 2
            psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`
         done
 
         let c=1
         while [[ $c -le $numcon ]]
         do
            ${fastcopy_ksh[$c]} >> ${fastcopy_ksh_log[$c]} 2>&1 &
###debug start
#echo "c is $c"
#echo "run ${fastcopy_ksh[$c]}"
###debug stop
            let c=$c+1
         done
 
         psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

         while [[ $psup -gt 0 ]]
            do
###debug start
echo sleep 2
###debug stop
            sleep 2
            psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`
         done

         let c=1
         while [[ $c -le $numcon ]]
           do
           echo "ssh $user@$dd << EOF" > ${fastcopy_ksh[$c]} 
           let c=$c+1
         done

         let tot=0 
         let c=1
     fi

done < $filesdir

echo "filesys show space" >> ${fastcopy_ksh[$c]} 
echo "filesys show compression" >> ${fastcopy_ksh[$c]} 
echo "mtree list" >> ${fastcopy_ksh[$c]} 
echo "EOF" >> ${fastcopy_ksh[$c]} 
#echo "if [ "\$\?" -ne 0 ]; then" >> ${fastcopy_ksh[$c]} 
#echo "    echo \"fastcopy script failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> "\$"run_log " >> ${fastcopy_ksh[$c]} 
#echo "fi" >> ${fastcopy_ksh[$c]} 

chmod 700 ${fastcopy_ksh[$c]} 
psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

while [[ $psup -gt 0 ]]
   do
###debug start
echo sleep 2
###debug stop
   sleep 2
   psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`
done

let c=1
echo "tot is $tot. run fastcopy"
if [[ $tot -ne 0 ]]; then
   while [[ $c -le $tot/20+1 ]]
   do  
      ${fastcopy_ksh[$c]} >> ${fastcopy_ksh_log[$c]} 2>&1 &
#debug start
#echo "c is $c"
#echo "run ${fastcopy_ksh[$c]}"
#debug finish
      let c=$c+1
   done
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
#      echo file $filename is not open file
    mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | sed 's/^.//'`
    echo directory is $sdir$mdir >> $run_log
    if [[ ! -d $tdir$mdir ]];then
        mkdir -p $tdir$mdir
#       userid=`/usr/bin/ls -dl $sdir$mdir`
        userid=`ls -ld $sdir$mdir | awk '{print $3}'`
        usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
        echo userid is $userid groupid is $usergp >> $run_log
        chown -R $userid:$usergp $tdir$mdir
     fi
     bfile=`echo $line | awk -F "/" '{print $NF}'`
     grep -i $line $filetdir
     if [ $? -ne 0 ]; then
        if [[ `fuser $filename` -eq 0 ]]; then
#          echo file $filename is not open file
           echo "$line is not in $tdir, will copy it from source to target" >> $run_log
           echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_ksh[$c]} 
###debug start
#           echo  ${fastcopy_ksh[$c]}
####debug stop
           echo fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_ksh[$c]} 

           locktime=$(/bin/date '+%Y%m%d%H%M' -d "+$lockday days")
           echo "this file $line will be locked until $locktime" >> $run_log
           echo "echo file $tdir$mdir/$bfile cannot be delete until $locktime" >> $setret_ksh
           echo "touch -a -t $locktime $tdir$mdir/$bfile" >> $setret_ksh
           let numline=$numline+1
           let tot=$tot+1
####debug start
#          echo numline is $numline
#          echo tot is $tot
###debug stop
        fi
     else
        echo "$line is already in $tdir directlry, skip" >> $run_log
     fi

     if [[ $numline -eq 20 ]]; then
#        echo "reached 20"
        echo "EOF" >> ${fastcopy_ksh[$c]} 
#        echo "if [ "\$\?" -ne 0 ]; then" >> ${fastcopy_ksh[$c]} 
#        echo "    echo \"fastcopy script failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> "\$"run_log " >> ${fastcopy_ksh[$c]} 
#        echo "fi" >> ${fastcopy_ksh[$c]} 
        chmod 700 ${fastcopy_ksh[$c]} 

        let numline=0
        let c=$c+1
     fi

     if [[ $tot -eq 20*$numcon ]]; then

         echo "tot is $tot. run fastcopy"
         psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

         while [[ $psup -gt 0 ]]
            do
###debug start
echo sleep 2
###debug stop
            sleep 2
            psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`
         done

         let c=1
         while [[ $c -le $numcon ]]
         do
            ${fastcopy_ksh[$c]} >> ${fastcopy_ksh_log[$c]} 2>&1 &
# debug start
#echo "c is $c"
#echo "run ${fastcopy_ksh[$c]}"
# debug stop
            let c=$c+1
         done

         psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

         while [[ $psup -gt 0 ]]
            do
###debug start
echo sleep 2
###debug stop
            sleep 2
            psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`
         done

         let c=1
         while [[ $c -le $numcon ]]
           do
           echo "ssh $user@$dd << EOF" >  ${fastcopy_ksh[$c]}  
           let c=$c+1
         done

         let tot=0
         let c=1
     fi


done < $filesdir
echo "filesys show space" >>  ${fastcopy_ksh[$c]} 
echo "filesys show compression" >>  ${fastcopy_ksh[$c]} 
echo "mtree list" >>  ${fastcopy_ksh[$c]} 
echo "EOF" >>  ${fastcopy_ksh[$c]} 
#echo "if [ "\$\?" -ne 0 ]; then" >>  ${fastcopy_ksh[$c]} 
#echo "    echo \"fastcopy script failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> "\$"run_log " >>   ${fastcopy_ksh[$c]} 
#echo "fi" >>  ${fastcopy_ksh[$c]} 

chmod 700  ${fastcopy_ksh[$c]} 
psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

while [[ $psup -gt 0 ]]
   do
###debug start
echo sleep 2
###debug stop
   sleep 2
   psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`
done

let c=1
echo "tot is $tot. run fastcopy"
if [[ $tot -ne 0 ]]; then
   while [[ $c -le $tot/20+1 ]]
   do
      ${fastcopy_ksh[$c]} >> ${fastcopy_ksh_log[$c]} 2>&1 &
#debug start
#echo "c is $c"
#echo "run ${fastcopy_ksh[$c]}"
#debug finish
      let c=$c+1
   done
fi

echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log

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
      print "missing retention lock time expressed in days which is -k option\n"
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
fi


