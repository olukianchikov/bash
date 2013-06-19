#!/bin/bash -
# Burning script
# It creates iso file from given files and burn it to the disk

# give a nice date
function cutedate() {
  local cutedate=`date +'<%d.%m.%y>%H:%M:%S '`
  echo "$cutedate"
}

# function executed when exit command is run
function onexit() {
  local error_msg="$1"
  if [[ ! -z $error_msg  ]];
  then  # MAIL user with this message
      error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
      test -z "$USER_TO_MAIL" ||\
      echo -e "$error_msg" >>$ERR_F
      local i=`echo "$CREATED_FILES" | awk '{print NF; exit;}'`
      while [[ $i -gt 0 ]]
      do
          local cur_file=`echo "$CREATED_FILES" | awk '{print $"'$i'"; exit;}'`
          test -d $cur_file -a $cur_file != "/" &&\
          {
             rmdir "$cur_file" >/dev/null 2>/dev/null
          }
          i=` expr $i - 1 `
      done
  fi
}

CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`
SETTINGS_F=$CURPATH".settings"
ISO_FILE_prefix="Servers_backup_"
ISO_FILE_suffix=`date +"%d_%m_%Y.iso"`
# $TEMP_DIR"iso/"$R_HOST"_backup_"$TODAY_SUFFIX"$ending"
LOG_F="/dev/tty"
ERR_F="/dev/tty"
USER_TO_MAIL="oleg"
ERR_MSG=""
TEMP_DIR=""
MYNAME="server"
MD5SUM=""
MAX_MEDIA_SIZE="0"   # maximum size of disk in bytes
ISO_DIR=""
SOURCE_FILES_DIR=""
CREATED_FILES=""

while read line           
do
     line_edited=`echo $line | sed 's/ //g'`
     test "${line_edited}" == "" && continue
     fst_ltr_line_edited="${line_edited:0:1}"
     test "${fst_ltr_line_edited}" == "#" && continue
     parameter_name=`echo $line_edited | awk -F '=' '{print $1}'`
     parameter_val=`echo $line_edited | awk -F '=' '{print $2}'`
     
     case "$parameter_name"
     in
         "log_file") test -z "$parameter_val" || \
         {
             LOG_F="$parameter_val" 
             ERR_F="$parameter_val"
         } ;;
         "notifications_user") test -z "$parameter_val" || USER_TO_MAIL="$parameter_val" ;;
         "host_name") test -z "$parameter_val" || MYNAME="$parameter_val" ;;
         "temp_directory") TEMP_DIR=$parameter_val 
			   test ${TEMP_DIR:0-1} != "/" && TEMP_DIR=$TEMP_DIR"/";;
	 "iso_directory") ISO_DIR=$parameter_val
			test ${ISO_DIR:0-1} != "/" && ISO_DIR=$ISO_DIR"/";;
     esac
done <"${SETTINGS_F:?'Sorry no settings file was found. Aborting.'}"

trap "{ onexit \"\$ERR_MSG\"  ; }" EXIT
#trap "{ onerror \"\$ERR_MSG\" ; exit 1 ; }" ERR

# check supplied parameter
#if [[ $# -lt 1 ]];
#then
 #   ERR_MSG=$ERR_MSG`cutedate`"You forgot to supply directory where to find source file(s)?""\n"
 #   exit 1
#fi

# supplied parameter must be a directory where symlinks to backups are.
if [[ $# -eq 1 ]];
then
    if [[ -d $1 ]];
    then
       ISO_DIR="$1"
       test ${ISO_DIR:0-1} != "/" && ISO_DIR=$ISO_DIR"/"
    else
       ERR_MSG=$ERR_MSG`cutedate`"You have to supply the path to iso-directory where files or symlinks can be found. ""\n"
       exit 1
    fi
fi

test -d $TEMP_DIR || \
{  # not a directory
    ERR_MSG=$ERR_MSG`cutedate`"Error. $TEMP_DIR is not a directory.""\n"
    exit 1
}

test -w $TEMP_DIR || \
{ # Not writable
    ERR_MSG=$ERR_MSG`cutedate`"Error. $TEMP_DIR has no write permission.""\n"
    exit 1
}

test -d $ISO_DIR ||\
{
  mkdir $ISO_DIR >/dev/null 2>/dev/null
}
test -d $ISO_DIR ||\
{
    ERR_MSG=$ERR_MSG`cutedate`"Error. $ISO_DIR is not found and can not be created.""\n"
    exit 1
}


SOURCE_FILES_DIR=$TEMP_DIR"lastbackup/"
test -d $SOURCE_FILES_DIR || \
{  # not a directory or doesn't exist
    ERR_MSG=$ERR_MSG`cutedate`"Error. $SOURCE_FILES_DIR is not a directory.""\n"
    exit 1
}

# Check if we actually have something to burn in SOURCE_FILES_DIR:
source_files_dir_list=`ls -A $SOURCE_FILES_DIR 2>/dev/null`
test -z "$source_files_dir_list" &&\
{
     ERR_MSG=$ERR_MSG`cutedate`"$SOURCE_FILES_DIR contains no files.""\n"
     exit 1
}
unset source_files_dir_list


test -w $LOG_F || LOG_F=/dev/tty
test -f $LOG_F || LOG_F=/dev/tty
test -w $ERR_F || ERR_F=/dev/tty
test -f $ERR_F || ERR_F=/dev/tty


# check where our dvd rom:
DRIVE_NAME=`cat /proc/sys/dev/cdrom/info | grep "drive name" | awk -F ':' '{ match($2, "[a-z0-9]+"); print substr($2,RSTART,RLENGTH);  }'`
test -z "$DRIVE_NAME" || DRIVE_NAME="/dev/"$DRIVE_NAME

ls "$DRIVE_NAME" >/dev/null 2>/dev/null || \
{
   echo "Device not found"
   exit 1
}

# Check if drive has installed driver:
#wodim -checkdrive "$DRIVE_NAME" >/dev/null 2>/dev/null ||\
#{
#       ERR_MSG=$ERR_MSG`cutedate`"Error. $DRIVE_NAME has no relevant driver on this system.""\n"
#       exit 1
#}

# Check if the disk is actually inserted and appropriate:
hasMedia=0
nameMedia=""
blankMedia=""

hasMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{ if ($0 ~ "has media") { match($2,"[01] *\(*"); print substr($2,RSTART,1); }}'`
test $hasMedia -eq 1 ||
{
  ERR_MSG=$ERR_MSG`cutedate`"Error. Drive $DRIVE_NAME has no media.""\n"
  exit 1
}

nameMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "^ *media"){match($2,"[0-9a-zA-Z_.-]+"); print substr($2,RSTART,RLENGTH);}}'`
echo $nameMedia | grep -i "dvd" >/dev/null &&\
{  # If we have DVD
  blankMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "blank"){match($2,"[01] *\(*"); print substr($2,RSTART,1);}}'`
  if [[ $blankMedia -eq 0 ]];
  then
       ERR_MSG=$ERR_MSG`cutedate`"Error. $nameMedia is not blank.""\n"
       exit 1
  fi
  # As we don't want to spend much time determining exact max size, we will assume minimum 
  # for most dvd-r or dvd+r discs
  MAX_MEDIA_SIZE="4700372992"
}

echo $nameMedia | grep -i "cd" >/dev/null &&\
{  # If we have CD
  blankMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "blank"){match($2,"[01] *\(*"); print substr($2,RSTART,1);}}'`
  if [[ $blankMedia -eq 0 ]];
  then
       ERR_MSG=$ERR_MSG`cutedate`"Error. $nameMedia is not blank.""\n"
       exit 1
  fi
  # As we don't want to spend much time determining exact max size, we will assume minimum 
  # for most cd-r disks
  MAX_MEDIA_SIZE="737280000"
}

test -f $ISO_DIR"$ISO_FILE_prefix""$ISO_FILE_suffix" &&\
{
       ERR_MSG=$ERR_MSG`cutedate`"Error. $ISO_DIR$ISO_FILE_prefix$ISO_FILE_suffix file exists.""\n"
       exit 1
} ||\
{
       ISO_FILE=$ISO_DIR"$ISO_FILE_prefix""$ISO_FILE_suffix"
}


echo "$MAX_MEDIA_SIZE"

# Get the size of the content of ISO_DIR, following all symbol links.
# ISO_DIR should contain only relevant files to burn and nothing more.
  SOURCE_FILES_SIZE=`du -b -d0 -L $ISO_DIR | awk '{print $1;}'`

# Check if the size of our files is less that capacity of the optical disk:
if [[ `echo "$SOURCE_FILES_SIZE > $MAX_MEDIA_SIZE" | bc` -eq 1 ]];
then
    ERR_MSG=$ERR_MSG`cutedate`"Error. $nameMedia does not have enough free space."`echo "$SOURCE_FILES_SIZE / 1048576" | bc`" Megabytes is needed.""\n"
    exit 1
fi


#generating ISO:
genisoimage -f -r -J -o $ISO_FILE "$SOURCE_FILES_DIR"
CREATED_FILES=$CREATED_FILES"$ISO_FILE "

test $? -ne 0 &&\
{
       ERR_MSG=$ERR_MSG`cutedate`"Error during ISO creation. Aborting.""\n"
       exit 1
}

# get Md5 sum of iso image
MD5SUM=`md5sum $ISO_FILE`
ISO_FILE_SIZE=`stat --format=%s $ISO_FILE`

# burning:
# Change speed to 0 if problems
# gracetime - timeout before start
(\
echo `cutedate`" Burning started." >>$LOG_F
# Write wodim -dummy to just test but not write
wodim -s speed=2 gracetime=8  dev="$DRIVE_NAME" -data $ISO_FILE ||\
echo `cutedate`" Burning failed." >>$LOG_F
# Checking md5 sum of first ISO_FILE_SIZE bytes on the disk:
# bs - how many bytes at a time to read and write (block size)
# count=xxxx - copy only xxxx input blocks
resulted_md5=`dd if="$DRIVE_NAME" bs=1 count=$ISO_FILE_SIZE | md5sum`

if [[ `echo "$resulted_md5 != $MD5SUM" | bc` -eq 1  ]];
then
 echo `cutedate`" Disk has different md5 sum that the iso-file. Disk may have corrupted data. Iso image is kept for future use." >>$LOG_F
else
 echo `cutedate`" Burning completed successfully." >>$LOG_F
 rm $ISO_FILE >/dev/null 2>/dev/null
fi
/usr/bin/eject -s "$DRIVE_NAME"
)&
exit 0