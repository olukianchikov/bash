#!/bin/bash -xv
# Gets three arguments:
# 1 - interface name
# 2 - Getfiles
# 3 - number of attempts
#  It will calculate how many attempts it should use

function cute_date() {
  local cutedate=`date +'%d.%m.%y %H:%M:%S  '`
  echo "$cutedate"
}

OS=""
INTERFACE=$1
getfiles=$2
BYTES=$3

echo `cute_date`"Start downloading $BYTES bytes."
# Define ip iddress of given interface
ip_addr=`ifconfig $interface | grep 'inet' | awk '{if(match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){print substr($0,RSTART,RLENGTH); exit;}}'`

# get all urls from Getfiles into one list
LIST_OF_FILES=`cat $getfiles | awk 'BEGIN{ORS=" ";}{print $0;}'`
# Get the number of given resources
ENTRIES=`echo $LIST_OF_FILES | awk 'END{ print NF;}'`

# Define our operation system:
OS=`uname -s`

# initializing some variables
dwnldd=0
errors=0
f_to_dl=""
f_to_dl_entry=1

# Downloading part. Do it until we reach the desired amount of bytes.
while [ $dwnldd -lt $BYTES ];
do
  # Stop downloading if there were as many errors as a number of different urls
  test $errors -gt $ENTRIES && break
  # Choose what file to download
  f_to_dl_entry=` expr $RANDOM % $ENTRIES `
  f_to_dl=`echo $LIST_OF_FILES | awk '{ print $"'$f_to_dl_entry'" ;}'`
   
  # Different programs on Linux and FreeBSD
  if [ $OS = "Linux" ];
  then
      # calculate how many bytes it is
      to_download=`wget --spider --no-cache --connect-timeout=3 --bind-address=$ip_addr -4 -O - $f_to_dl 2>&1 \
      >/dev/null | awk 'BEGIN { total=0;} {if ($1 == "Length:") { total=total + $2; }} END {print total;}'`
      # Choose another file if this file is too big
      if [[ `echo "($dwnldd + $to_download) > $BYTES"` -ne 0  ]];
      then
         errors=` expr $errors + 1 `
         continue
      fi
      # Downloading itself
      to_download=`wget --connect-timeout=3 --bind-address=$ip_addr -4 -O - $f_to_dl 2>&1 \
      >/dev/null | awk 'BEGIN { total=0;} {if ($1 == "Length:") { total=total + $2; }} END {print total;}'`
      # Aggregate the values of downloaded bytes
      dwnldd=` expr $dwnldd + $to_download `       
  elif [ $OS = "FreeBSD" ];
  then
      # calculate how many bytes it is
      to_download=`fetch -s -4 -o - $f_to_dl`
      # Choose another file if this file is too big
      if [[ `echo "($dwnldd + $to_download) > $BYTES"` -ne 0  ]];
      then
         errors=` expr $errors + 1 `
         continue
      fi
      # Downloading itself
      to_download=`curl -s -L --proto =http -4 --interface $ip_addr --limit-rate 200K \
      --connect-timeout 8 -w "%{size_download}" $f_to_dl -o /dev/null`
      # Aggregate the values of downloaded bytes
      dwnldd=` expr $dwnldd + $to_download `
  else
     exit 1
  fi
done
echo `cute_date`"$dwnldd bytes have been downloaded."
exit 0