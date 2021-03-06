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
# 06/28/18 Diana Yang   Add a log directory and logs for troubleshooting
# 07/17/18 Diana Yang   Add begin time and end time to track the process 
# 07/19/18 Diana Yang   Add force option to fastcopy to make sure all necessary files are copied
# 07/30/18 Diana Yang   Search 2 more days data in target directory to make sure all files are found
# 09/20/18 Diana Yang   Add concurrent fastcopy processes to speed up performance 
# 10/02/18 Diana Yang   Add a logic to exit with exit code 2 if no new backup files are discovered.
# 10/20/18 Diana Yang   Fix hang and partial fastcopy issues.
# 10/23/18 Diana Yang   The script will try 3 more times to collect data if no new backup files are discovered.
# 01/17/19 Diana Yang   Add checking dd user password expiration checking
# 01/17/19 Diana Yang   Check copied file size and copy it again if the file were open 
# 01/29/19 Diana Yang   Remove /data/col1 requirement 
# 05/06/19 Diana Yang   Only trim logs related to this fastcopy directory. 
# 05/08/19 Diana Yang   Delay touch command to allow fastcopy to finish. 
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added, 
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send 
# you an alert.
#################################################################


function show_usage {
print "usage: mtree-copy-retentionlock.ksh -o <full or partial> -d <Data Domain> -u <User> 
-s <Source Directory on server> -m <Source Directory on DD> -t <Target Directory on server> 
-n <Target  Directory on DD> -r <Comparing Days> 
-l <yes if retention lock should be added to the file> 
-k <retention lock days> -c <concurrent processes>"
print "\noption detail"
print "  -o : full if running full synchronization (first time), no if script runs everyday"
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory on server\n  -m : Source Directory on DD (If the last field of Source Directory on server is the mtree, this input is not required"
print "  -t : Target Directory server\n  -n : Target Directory on DD (If the last field of Target Directory on server is the mtree, this input is not required"
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
    print " $DIR/log is created. Script continue"
fi

shortdir=`echo $sdir | awk -F "/" '{print $NF}'`
if [[ ! -d $DIR/log/$shortdir ]]; then
    print " $DIR/log/$shortdir does not exist, create it"
    mkdir $DIR/log/$shortdir
    print " $DIR/log/$shortdir is created. Script continue"
fi

filesdir=$DIR/log/$shortdir/filesdir.$DATE_SUFFIX
filetdir=$DIR/log/$shortdir/filetdir.$DATE_SUFFIX
fastcopy_log=$DIR/log/${shortdir}/ft_log.$DATE_SUFFIX
setret_ksh=$DIR/setretention.ksh
setret_log=$DIR/log/$shortdir/setret_log.$DATE_SUFFIX
run_log=$DIR/log/$shortdir/mtree-copy-retentionlock.$DATE_SUFFIX.log
fail_log=$DIR/log/$shortdir/ft_fail.$DATE_SUFFIX.log

function check_dd {
   ssh $user@$dd "filesys show space" | grep -i "Your password has expired"

   if [[ $? -eq 0 ]]; then
      echo "DD user $user password has expired" >> $run_log
      exit 1
   fi 
}

check_dd

#trim log directory
find $DIR/log/$shortdir -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
    echo "del old logs in $DIR/log/shortdir failed" >> $run_log
    exit 1
fi

if [[ ! -d $sdir ]]; then
    print "Source Directory $sdir does not exist"
    exit 1
fi

let cyc=1
if [[ $full = "full" || $full = "Full" || $full = "FULL" ]]; then
     while [[ $cyc -le 3 ]]
     do  
        cd $sdir
        echo "full search in source directory $sdir started at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log 
        find . -type f |  grep -v "snapshot" > $filesdir
        echo "full search in source directory $sdir finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log 
        if [[ ! -s  $filesdir ]]; then
           echo "Finding no new files in $sdir, will rerun after 5 minutes" >> $run_log
           sleep 300 
           let cyc=$cyc+1
        else
           let cyc=4
        fi   
     done
     let newcyc=$cyc-1
     if [[ ! -s  $filesdir && $cyc -eq 4 ]]; then
        echo "Finding no new files in $sdir after $newcyc try" >> $run_log
        echo "This program will exit with exit code 2" >> $run_log
        exit 2
     fi
else
     if test $ret; then
        while [[ $cyc -le 3 ]]
        do
           cd $sdir
           echo "Search last $ret days only in source directory $sdir started at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log 
           echo "Search range is from " `/bin/date -d" -$ret day"`  "to" `/bin/date` >> $run_log
           find . -type f -mtime -$ret|  grep -v "snapshot" > $filesdir
           echo "Search last $ret days only in source directory $sdir finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
              if [[ ! -s  $filesdir ]]; then
 		 echo "Finding no new files in $sdir, will rerun after 5 minutes" >> $run_log
           	 sleep 300 
           	 let cyc=$cyc+1
              else
           	 let cyc=4
              fi
        done
        let newcyc=$cyc-1
        if [[ ! -s  $filesdir && $cyc -eq 4 ]]; then
           echo "Finding no new files in $sdir after $newcyc try" >> $run_log
           echo "This program will exit with exit code 2" >> $run_log
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
    mkdir -p $tdir
    userid=`ls -ld $sdir | awk '{print $3}'`
    usergp=`ls -ld $sdir | awk '{print $4}'`
    chown -R $userid:$usergp $tdir
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
    print "Source directory on DD is not provided, we assume it is same as the last field of Source Directory on server"
    print "Source directory on DD  is $sm"
else
    ddinits1=`echo $sm |  awk -F "/" '{print $2}'`
    ddinits2=`echo $sm |  awk -F "/" '{print $3}'`
    if [[ $ddinits1 != "data" || $ddinits2 != "col1" ]]; then
        
        firsts=`echo $sm | awk -F "/" '{print $1}'`
        if [[ -z $firsts ]]; then
           sm=${sm:1}
        fi
        sm=/data/col1/$sm
    fi
    print "Source directory on DD  is $sm"
fi

if [[ -z $tm ]]; then
    tm=/data/col1/`echo $tdir | awk -F "/" '{print $NF}'`
    print "Target directory on DD is not provided, we assume it is same as the last field of Target Directory on server"
    print "Target directory on DD is $tm"
else
    ddinitt1=`echo $tm |  awk -F "/" '{print $2}'`
    ddinitt2=`echo $tm |  awk -F "/" '{print $3}'`
    if [[ $ddinitt1 != "data" || $ddinitt2 != "col1" ]]; then
    
        firstt=`echo $tm | awk -F "/" '{print $1}'`
        if [[ -z $firstt ]]; then
           tm=${tm:1}
        fi
        tm=/data/col1/$tm
    fi
    print "Target directory on DD is $tm"
fi
}

get_mtree

let c=1
while [[ $c -le $numcon ]]
do

    fastcopy_ksh_log[$c]=$DIR/log/${shortdir}/ft${c}_ksh_log.$DATE_SUFFIX
    fastcopy_ksh[$c]=$DIR/${shortdir}_fastcopy${c}.ksh
    echo "ssh $user@$dd << EOF" > ${fastcopy_ksh[$c]}
###debug start
#echo ${fastcopy_ksh_log[$c]}, ${fastcopy_ksh[$c]}
### dedug done
    let c=$c+1
done

function fastcopy {
echo "begin fastcopy at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
while IFS= read -r line
do
#   echo line is $line
    filename=$sdir${line:1}
    mdir=`echo $line |  awk -F "/" 'sub(FS $NF,x)' | sed 's/^.//'`
    echo directory is $sdir$mdir >> $run_log
    if [[ ! -d $tdir$mdir ]];then
        mkdir -p $tdir$mdir
#       userid=`/usr/bin/ls -dl $sdir$mdir`
        userid=`ls -ld $sdir$mdir | awk '{print $3}'`
        usergp=`ls -ld $sdir$mdir | awk '{print $4}'`
        echo userid is $userid groupid is $usergp >> $run_log
        find $tdir$mdir -type d ! -name .snapshot -exec chown $userid:$usergp {} \;
     fi
     bfile=`echo $line | awk -F "/" '{print $NF}'`
     grep -i $line $filetdir
     if [[ $? -ne 0 ]]; then
#       echo file $filename is not open file
        echo "$line is not in $tdir, will copy it from source to target" >> $run_log
        echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_ksh[$c]} 
###debug start
#       echo  ${fastcopy_ksh[$c]}
####debug stop
        echo fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_log} 
#        ls -l $filename >> ${fastcopy_log} 

        if test $lockday; then
           ssize=`ls -l $sdir$mdir/$bfile | awk '{print $5}'`
  	   if [[ $ssize -gt 0 ]]; then
              locktime=$(/bin/date '+%Y%m%d%H%M' -d "+$lockday days")
              echo "this file $line will be locked until $locktime" >> $run_log
              echo "echo file $tdir$mdir/$bfile cannot be delete until $locktime" >> $setret_ksh
              echo "touch -a -t $locktime $tdir$mdir/$bfile" >> $setret_ksh
           else
  	      echo "this file $bfile has size 0, will not locked" >> $run_log
           fi
        fi
        let numline=$numline+1
        let tot=$tot+1
####debug start
#       echo numline is $numline
#       echo tot is $tot
###debug stop
     else
        echo "$line is already in $tdir directlry, check the size" >> $run_log
        ssize=`ls -l $sdir$mdir/$bfile | awk '{print $5}'`
        tsize=`ls -l $tdir$mdir/$bfile | awk '{print $5}'`
        if [[ $ssize -ne $tsize ]]; then
           echo "$sdir$mdir/$bfile was open file, will copy it from source to target again" >> $run_log
           echo filesys fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_ksh[$c]}
###debug start
#          echo  ${fastcopy_ksh[$c]}
####debug stop
           echo fastcopy source $sm$mdir/$bfile destination $tm$mdir/$bfile force >> ${fastcopy_log}
           ls -l $filename >> ${fastcopy_log}

           if test $lockday; then
               ssize=`ls -l $sdir$mdir/$bfile | awk '{print $5}'`
  	       if [[ $ssize -gt 0 ]]; then
                  locktime=$(/bin/date '+%Y%m%d%H%M' -d "+$lockday days")
                  echo "this file $line will be locked until $locktime" >> $run_log
                  echo "echo file $tdir$mdir/$bfile cannot be delete until $locktime" >> $setret_ksh
                  echo "touch -a -t $locktime $tdir$mdir/$bfile" >> $setret_ksh
               else
  	          echo "this file $bfile has size 0, will not locked" >> $run_log
               fi
           fi

           let numline=$numline+1
           let tot=$tot+1
####debug start
#       echo numline is $numline
#       echo tot is $tot
####debug stop
        fi
     fi

     if [[ $numline -eq 20 ]]; then
#        echo "reached 20"
        echo "EOF" >> ${fastcopy_ksh[$c]} 
        echo "if [[ "\$\?" -ne 0 ]]; then" >> ${fastcopy_ksh[$c]} 
        echo "    echo \"fastcopy script failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> "\$"run_log " >> ${fastcopy_ksh[$c]} 
        echo "fi" >> ${fastcopy_ksh[$c]} 
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
#echo sleep 2
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
#echo sleep 2
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
#echo "if [[ "\$\?" -ne 0 ]]; then" >>  ${fastcopy_ksh[$c]} 
#echo "    echo \"fastcopy script failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> "\$"run_log " >>   ${fastcopy_ksh[$c]} 
#echo "fi" >>  ${fastcopy_ksh[$c]} 

chmod 700  ${fastcopy_ksh[$c]} 
psup=`ps -ef | awk '{print $8}' | grep -i fastcopy | awk -F "/" '{print $NF}' | wc -l`

while [[ $psup -gt 0 ]]
   do
###debug start
#echo sleep 2
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


let numline=0
let c=1
let tot=0
if [[ $lock = "yes" || $lock = "Yes" || $lock = "YES" ]]; then
   echo "#/bin/ksh" > $setret_ksh
   echo "will set up retention lock" >> $run_log
   if test $lockday; then
      echo "begin setting retention lock at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
      chmod 700 $setret_ksh
      echo "retention lock days is $lockday" >> $run_log
      echo "fastcopy started at " `/bin/date '+%Y%m%d%H%M%S'`
      fastcopy
      echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'`
   
      sleep 120

      $setret_ksh > $setret_log
      if [[ $? -ne 0 ]]; then
         echo "Set Retention failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
      else
         echo "setting retention lock finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $run_log
      fi
   else
      print "missing retention lock time expressed in days which is -k option\n"
      show_usage
      exit 1
   fi
else
   echo "no retention lock" >> $run_log
   echo "fastcopy started at " `/bin/date '+%Y%m%d%H%M%S'`
   fastcopy
   echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

if test $userid; then
   echo match the ownership to original directory >> $run_log
   find $tdir -type d ! -name .snapshot -exec chown $userid:$usergp {} \;
fi
