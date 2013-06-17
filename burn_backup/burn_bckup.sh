#!/bin/bash -
# Burning script
# It creates iso file from given files and burn it to the disk

MD5SUM=""
ISO_FILE=""
TMP_DIR=""

# check where our dvd rom:
DRIVE_NAME=`cat /proc/sys/dev/cdrom/info | grep "drive name" | awk '{print $2;}'`
test -z $DRIVE_NAME || DRIVE_NAME="/dev/"$DRIVE_NAME

test `ls $DRIVE_NAME >/dev/null 2>/dev/null` -ne 0 && \
{
   echo "Device not found"
   exit 1
}

ISO_FILE=some.iso
#generating ISO:
genisoimage -r -J -o $ISO_FILE $SOURCE_FILES

MD5SUM=`md5sum $ISO_FILE`

##wodim --devices