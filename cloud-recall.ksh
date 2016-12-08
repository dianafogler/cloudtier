#!/bin/ksh
#
# Name:		cloud-recall.ksh
#
# Function:	recall files from Cloud to Data Domain
#
# Input:
#	$1	Name of Data Domain 
#	$2	Name of the restore file that lists all files that need to be recalled
#	$3	Yes means you are certain these files are in CloudTier
#	$4	Yes means you want to generate a list of files that moved to Cloud. 
#
# Operation:
# - Option 1. Verify whether files are in Cloud or not before run recall commands
# - Option 2. Recall the files without checking. If the files are in Cloud, it will recall the file. 
# - If the files are not in Cloud, the script will generate an error. 
#
# Changes:
# 10/15/16 Diana Yang	new script 
#########################################################################

function show_usage {
print "usage: cloud-recall.ksh -d <Data Domain> -f <Restore file list>  -s <yes if you are certain these files are in CloudTier or no if you need to check> -g <yes if generating new DD cloud report or no if use current one>" 
print "  -d : Data Domain\n  -f : Oracle restore file list"
print "  -s : yes or no skip checking\n  -g : yes or no new DD cloud report" 
}

function report_cloud {
       if [[ $GEN = "yes" || ! -f $DIR/dd-files ]]; then
          print "Will generate a Cloud file"
          if ! ssh sysadmin@$DD "filesys report generate file-location" > $DIR/dd-files; then
             rm $DIR/dd-files
             exit 1
          fi
       else
          print "The Cloud file is current"
       fi
}


function check_file {
   
   if [[ ! -s $DIR/dd-files ]]; then
       print "no DD report file"
       exit 1
   fi

   while IFS= read -r line
   do
       # display line or do somthing on $line
       piece=`grep $line $DIR/dd-files | awk '{print $1}'`
       where=`grep $line $DIR/dd-files | awk '{print $2}'`
#       echo "$piece" "in" "$where"
       if [[ `echo $where | sed 's/^[ \t]*//;s/[ \t]*$//'` != "Active" ]]; then
          print "$piece is currently in $where"
          echo $piece >> $DIR/cloud.list
          cloudlist=$DIR/cloud.list
       else
          print "$piece is currently in Active Tier" 
          cloudlist=$DIR/$File
       fi
   done <"$DIR/$File"
}

DIR=/home/oracle/scripts/rman

while getopts ":d:f:s:g:" opt; do
  case $opt in
    d ) DD=$OPTARG;;
    f ) File=$OPTARG;;
    s ) SKIP=$OPTARG;;
    g ) GEN=$OPTARG;;
  esac
done

#echo $DD $File $SKIP $GEN

# Check required parameters
if test $DD && test $File && test $SKIP && test $GEN
then
  :
else
  show_usage
  exit 1
fi

if [[ ! -f $DIR/$File ]]; then
    print "Oracle file list $DIR/$File does not exist"
    exit 1
fi


if [[ $SKIP = "yes" ]]; then
    print "run recall"
     
    echo "ssh sysadmin@$DD << EOF" > $DIR/recall.ksh
    while IFS= read -r line
    do
       echo "data-movement recall path $line" >> $DIR/recall.ksh
    done <"$DIR/$File"

    print "EOF" >> $DIR/recall.ksh
    chmod 700 $DIR/recall.ksh
    $DIR/recall.ksh
else 
    print "check first and recall the file if it is in Cloud"

    report_cloud
    rm $DIR/cloud.list
    check_file
   
    if [[ ! -f $DIR/cloud.list ]]; then
       print "\n All files are in active tier, no recall is needed"
       exit 0
    fi
    
    echo "ssh sysadmin@$DD << EOF" > $DIR/recall.ksh
    while IFS= read -r line
    do
       echo "data-movement recall path $line" >> $DIR/recall.ksh
    done <"$cloudlist"

    print "EOF" >> $DIR/recall.ksh
    chmod 700 $DIR/recall.ksh
    $DIR/recall.ksh
fi
