#!/bin/ksh
#
# Name:         ddfile-mtree-copy.ksh
#
# Function:     This script will copy files from one mtree to another mtree 
#               in the same Data Domain using DD fastcopy. This can be used
#               to safeguard the files that can not be deleted by applications
#               or move data to a mtree that CloudTier can be set up. The script
#		is recommended to run once a day or at least once in 5 days. It
#		only copies data that have not been copied yet and it compares
#		the files in both mtree in less than "short retention" days which
#		is one of the command input
#
# Input:
#       $1      Data Domain 
#       $2      Data Domain user 
#       $3      Source Directory
#       $4      Source Mtree 
#       $5      Target Directory
#       $6      Target Mtree
#       $7	Short term retention ( >5 ) 
#
# Changes:
# 11/08/16 Diana Yang   New script
# 11/28/16 Diana Yang   Change script name and added explanation
#################################################################

function show_usage {
print "usage: ddfile-mtree-copy.ksh -d <Data Domain> -u <User> -s <Source Directory> -sm <Source Mtree> -t <Target Directory> -tm <Target Directory> -r <Short Retention>" 
print "  -d : Data Domain\n  -u : DD user"
print "  -s : Source Directory\n  -sm : Source Mtree (optional)"
print "  -t : Target Directory\n  -tm : Target Mtree (optional)"
print "  -r : Short Retention" 
}


while getopts ":d:u:s:t:r:sm:tm:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    s ) sdir=$OPTARG;;
    t ) tdir=$OPTARG;;
    r ) ret=$OPTARG;;
    sm ) smtree=$OPTARG;;
    tm ) tmtree=$OPTARG;;
  esac
done

#echo $dd $user $sdir $tdir $ret

# Check required parameters
if test $dd && test $user && test $sdir && test $tdir && test $ret
then
  :
else
  show_usage
  exit 1
fi

DIR=/home/oracle/scripts/cloud

if [[ ! -d $sdir ]]; then
    print "Source Directory $sdir does not exist"
    exit 1
fi
find $sdir -type f |  grep -v "snapshot" > $DIR/file-in-sdir 

if [[ ! -d $tdir ]]; then
    print "Target Directory $tdir does not exist"
    exit 1
fi
find $tdir -type f  -mtime -$ret| grep -v "snapshot" > $DIR/file-in-tdir 

if [[ -z $sm ]]; then
    sm=/data/col1/`echo $sdir | awk -F "/" '{print $NF}'`
    print "Source Mtree is not provided, we assume it is same as the last field of Source Directory/n"
    print "Source Mtree is $sm"
fi

if [[ -z $tm ]]; then
    tm=/data/col1/`echo $tdir | awk -F "/" '{print $NF}'`
    print "Target Mtree is not provided, we assume it is same as the last field of Target Directory/n"
    print "Target Mtree is $tm"
fi

let numline=0 
echo "ssh $user@$dd << EOF" > $DIR/fastcopy.ksh
while IFS= read -r line
do
    bfile=`echo $line | awk -F "/" '{print $NF}'`
    grep -i $bfile $DIR/file-in-tdir
    if [ $? -ne 0 ]; then
#         echo $bfile
        echo filesys fastcopy source $sm/$bfile destination $tm/$bfile >> $DIR/fastcopy.ksh
	let numline=$numline+1
#	echo $numline
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
echo "EOF" >> $DIR/fastcopy.ksh

chmod 700 $DIR/fastcopy.ksh
$DIR/fastcopy.ksh

if [ $? -ne 0 ]; then
    echo "fastcopy script failed"
    exit 1
fi

