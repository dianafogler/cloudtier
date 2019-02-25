#!/bin/ksh
#
# Name:         file-fastcopy.ksh
#
# Function:     This script will copy files from one mtree to another mtree
#               in the same Data Domain using DD fastcopy. The data files that
#		should be copied should be first added to a file using 
#		"ls -d /.../<prefix>*" command or "cd /.../, ls -d <prefix>*". 
#		Directory needs to exist first.
#
# Show Usage: run the command to show the usage
#
# Changes:
# 02/24/19 Diana Yang   New script
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added, 
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send 
# you an alert.
#################################################################


function show_usage {
print "usage: file-fastcopy.ksh -f <file> -d <Data Domain> -u <User> 
-m <Source Directory on DD> -n <Target  Directory on DD> -c <concurrent>"
print " " 
print "  -f : file that contains the list of files that should be copied"
print "  -d : Data Domain\n  -u : DD user"
print "  -m : Source Directory on DD (If the last field of Source Directory on server is the mtree, this input is not required"
print "  -n : Target Directory on DD (If the last field of Target Directory on server is the mtree, this input is not required"
print "  -c : number of concurrent fastcopy processes (optional, default is 1)"
}


while getopts ":f:d:u::m:n:c:" opt; do
  case $opt in
    f ) file=$OPTARG;;
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    m ) sm=$OPTARG;;
    n ) tm=$OPTARG;;
    c ) numcon=$OPTARG;;
  esac
done

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`

#echo $dd $user $sdir $tdir  $lock
#echo $full $lock $lockday

# Check required parameters
if test $file && test $dd && test $user && test $sm && test $tm 
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


fastcopy_log=$DIR/log/ft_log.$DATE_SUFFIX
run_log=$DIR/log/file-fastcopy.$DATE_SUFFIX.log
fail_log=$DIR/log/ft_fail.$DATE_SUFFIX.log

function check_dd {
   ssh $user@$dd "filesys show space" | grep -i "Your password has expired"

   if [[ $? -eq 0 ]]; then
      echo "DD user $user password has expired" >> $run_log
      exit 1
   fi 
}

check_dd

#trim log directory
find $DIR/log -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
    echo "del old logs in $DIR/log failed" >> $run_log
    exit 1
fi

let c=1
while [[ $c -le $numcon ]]
do

    fastcopy_ksh_log[$c]=$DIR/log/ft${c}_ksh_log.$DATE_SUFFIX
    fastcopy_ksh[$c]=$DIR/fastcopy${c}.ksh
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
     bfile=`echo $line | awk -F "/" '{print $NF}'`
     echo filesys fastcopy source $sm/$bfile destination $tm/$bfile force >> ${fastcopy_ksh[$c]} 
###debug start
#       echo  ${fastcopy_ksh[$c]}
####debug stop
     echo fastcopy source $sm/$bfile destination $tm/$bfile force >> ${fastcopy_log} 
#        ls -l $filename >> ${fastcopy_log} 

     let numline=$numline+1
     let tot=$tot+1
####debug start
#       echo numline is $numline
#       echo tot is $tot
###debug stop

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


done < $file
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
echo "fastcopy started at " `/bin/date '+%Y%m%d%H%M%S'`
fastcopy
echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'`
