#!/bin/ksh
#
# Name:         mailtest.ksh

function show_usage {
echo "usage: mailtest -t <recipient email address>"
echo " -t : recipient email address"
}

while getopts ":t:" opt; do
  case $opt in
    t ) TO_ADDRESS=$OPTARG;;
  esac
done

# Check required parameters
if test $TO_ADDRESS
then
  :
else
  show_usage
  exit 1
fi

if [[ $TO_ADDRESS != *@* ]]
then
  echo "$TO_ADDRESS is not a valid email address"
  exit 1
fi

echo "Thiis is email content"> mailtest.dat
BODY_FILE="mailtest.dat"

mail -s "Test Email Setup" $TO_ADDRESS < $BODY_FILE
