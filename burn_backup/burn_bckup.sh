#!/bin/bash -xv
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

# Function that should be used for DVD disks only.
# It give an information of starting sector of previous session and
# the starting sector number for current session. It is required by
# genisoimage.
# parameter - drive_name
function getSectorNumbers() {
      local drive_name=$1
      dvd+rw-mediainfo ${drive_name} | awk -F ':' 'BEGIN{\
	next_track=0;\
	first_sector_last_sess=0;\
	first_sector_new_sess=0;\
	end_search=0;\
	end_search2=0;\
      }\
      {\
	if ($1 ~ "\"Next\" Track")\
	{\
	    next_track=$2;\
	    sub(/ */,"",next_track);\
	}\
        regexp_string="READ TRACK INFORMATION\[#"(next_track-1)"\]";\
	if (match($0, regexp_string)==1){\
	    end_search=(NR + 5);\
	}\
	if (NR <= end_search){\
	    if($1 == " Track Start Address"){\
	    first_sector_last_sess=$2;\
	    sub(/ */,"",first_sector_last_sess);\
	}\
	}\
	regexp_string2="READ TRACK INFORMATION\[#"next_track"\]";\
	if (match($0, regexp_string2)==1){\
	    end_search2=(NR + 5);\
	}\
	if (NR <= end_search2){\
	if($1 == " Track Start Address"){\
	first_sector_new_sess=$2;\
	sub(/ */,"",first_sector_new_sess);\
	}\
	}\
      }\
    END{\
	sub(/\*2KB/,"",first_sector_last_sess);\
	sub(/\*2KB/,"",first_sector_new_sess);\
	print first_sector_last_sess","first_sector_new_sess;\
}'

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
# These two strings will hold a command to burn and finalize a disk (if necessary)
# At the end of the script they will be evaluated by checking if the variable is empty
# or not. If empty, that will mean this operation is not needed. However, bear in mind, that
# both variables may not be empty (It will be considered as an error). 
BURN_COMMAND=""      # command to burn a disk
CLOSING_COMMAND=""   # Command to finalize a disk

MULTI=0              # Value from settings-file. It defines if we should use multi session burning.

burning_needed=0
closing_needed=0

cur_size=0     # The size of existing files on the media.
sector_numbers=""  # This variable is needed for growisofs (using -C flag of genisoimage subprogram)
		   #to crate a proper image for multisession

MD5SUM=""            # Currently I don't know how to calculate md5 sum for multisession disks.
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
         "multi") MULTI=$parameter_val ;;
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
is_closed=0

hasMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{ if ($0 ~ "has media") { match($2,"[01] *\(*"); print substr($2,RSTART,1); }}'`
test $hasMedia -eq 1 ||
{
  ERR_MSG=$ERR_MSG`cutedate`"Error. Drive $DRIVE_NAME has no media.""\n"
  exit 1
}

# -- If the disk is closed, exit:
is_closed=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "^ *closed"){match ($2, "[01]"); print substr($2, RSTART, RLENGTH);}}'`
if [[ $is_closed -eq 1 ]];
then
    ERR_MSG=$ERR_MSG`cutedate`"Error. Can not write to the disk because the disk is finalized already.""\n"
    exit 1         
fi



#------- Determining how much of free space we have on the media based on    ---------
#-------    what type of disk we have:                                      ---------
nameMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "^ *media"){match($2,"[0-9a-zA-Z_.-]+"); print substr($2,RSTART,RLENGTH);}}'`
echo $nameMedia | grep -i "dvd" >/dev/null &&\
{  # --------- If we have a DVD -------------
  blankMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "blank"){match($2,"[01] *\(*"); print substr($2,RSTART,1);}}'`
  # As we don't want to spend much time determining exact max size, we will assume minimum 
  # for most dvd-r or dvd+r discs
  MAX_MEDIA_SIZE="4700372992"
  if [[ $blankMedia -eq 0 ]];
  then
       # --  Disc is not blank (we will try to append to the media). 
       # --  Calculate how much space left:
       cur_size=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "^ *size"){match($2,"[0-9]+"); print substr($2, RSTART, RLENGTH);}}'`
       MAX_MEDIA_SIZE=`echo "scale=0; $MAX_MEDIA_SIZE - $cur_size" | bc `
  fi
}

echo $nameMedia | grep -i "cd" >/dev/null &&\
{  # --------- If we have a CD -------------
  blankMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "blank"){match($2,"[01] *\(*"); print substr($2,RSTART,1);}}'`
  # As we don't want to spend much time determining exact max size, we will assume minimum 
  # for most cd-r disks
  MAX_MEDIA_SIZE="737280000"
  if [[ $blankMedia -eq 0 ]];
  then
       # --  Disc is not blank (we will try to append to the media).
       # --  Calculate how much space left:
       cur_size=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{if($0 ~ "^ *size"){match($2,"[0-9]+"); print substr($2, RSTART, RLENGTH);}}'`
       MAX_MEDIA_SIZE=`echo "scale=0; $MAX_MEDIA_SIZE - $cur_size" | bc `
  fi
}
 # --------------------------------------------

 # Get the name for ISO-FILE
test -f $ISO_DIR"$ISO_FILE_prefix""$ISO_FILE_suffix" &&\
{
       ERR_MSG=$ERR_MSG`cutedate`"Error. $ISO_DIR$ISO_FILE_prefix$ISO_FILE_suffix file exists.""\n"
       exit 1
} ||\
{
       ISO_FILE=$ISO_DIR"$ISO_FILE_prefix""$ISO_FILE_suffix"
}
 # --------------------------

# Get the size of the content of ISO_DIR, following all symbol links.
# ISO_DIR should contain only relevant files to burn and nothing more.
# SOURCE_FILES_DIR
  SOURCE_FILES_SIZE=`du -b -d0 -L $SOURCE_FILES_DIR | awk '{print $1;}'`

# Check if the size of our files is less that capacity of the optical disk.
# Actually, this should not happen because this script closes disk if it has no
# enough free space. But if, for some reason, disk is not closed and have no
# enough space, close it:
if [[ `echo "$SOURCE_FILES_SIZE >= $MAX_MEDIA_SIZE" | bc` -eq 1 ]];
then
    # No free space
    ERR_MSG=$ERR_MSG`cutedate`"Error. $nameMedia does not have enough free space."`echo "$SOURCE_FILES_SIZE / 1048576" | bc`" Megabytes is needed.""\n"
    burning_needed=0
    closing_needed=1
else
    # We have enough free space for the current backup burning.
    burning_needed=1
   #   Here we determine if we need to close the disk after appending current backup.
   #   let's consider that if after today's burning there is no free space for one more 
   #   backup (assuming its size is the same as today's), we have to close that disk.
   if [[ `echo "$SOURCE_FILES_SIZE*2 >= $MAX_MEDIA_SIZE" | bc` -eq 1 ]];
   then
       closing_needed=1
   else
       closing_needed=0
   fi 
fi

#   ------------  Preparing BURN_COMMAND and CLOSING_COMMAND for burning process:
test $closing_needed -eq 0 -a $burning_needed -eq 0 &&\
{
    ERR_MSG=$ERR_MSG`cutedate`"Error. Could not define burning command for the disk ${nameMedia}.""\n"
    exit 1
}

# --- For CD:
# Change speed to 0 if problems
# gracetime - timeout before start
echo $nameMedia | grep -i "cd" >/dev/null &&\
{
   if [[ $burning_needed -eq 1 && $closing_needed -eq 1 ]];
   then
       # This burning command will close the disk:
       BURN_COMMAND="wodim -s speed=2 gracetime=8  dev=$DRIVE_NAME -data $ISO_FILE"
       # No need for separate closing:
       CLOSING_COMMAND=""
   fi
   if [[ $burning_needed -eq 1 && $closing_needed -eq 0 ]];
   then
       if [[ ${MULTI} -eq 1 ]];
       then
           # This burning command will not close the disk:
           BURN_COMMAND="wodim -multi -s speed=2 gracetime=8  dev=$DRIVE_NAME -data $ISO_FILE"
           CLOSING_COMMAND=""
       else
           BURN_COMMAND="wodim -s speed=2 gracetime=8  dev=$DRIVE_NAME -data $ISO_FILE"
           CLOSING_COMMAND=""
       fi
   fi
   if [[ $burning_needed -eq 0 && $closing_needed -eq 1 ]];
   then
       # No burning is needed
       BURN_COMMAND=""
       # However, we have to close the disk (meaning we can't burn due to no free space, but
       #   we can't leave the disk uncloased. So close it).
       CLOSING_COMMAND="wodim -s speed=2 gracetime=8  dev=$DRIVE_NAME -data /dev/zero"
   fi
}

   # --- For DVD, except dvd_rw:
echo $nameMedia | grep -i "dvd" | grep -v 'dvd_rw'  >/dev/null &&\
{
   if [[ $burning_needed -eq 1 ]];
   then
       if [[ $blankMedia -eq 1 ]];
       then
           BURN_COMMAND="growisofs -speed=1 -Z $DRIVE_NAME=$ISO_FILE"
       else 
           if [[ ${MULTI} -eq 1 ]];
           then
               sector_numbers="-C `getSectorNumbers $DRIVE_NAME`"
               BURN_COMMAND="growisofs -speed=1 -M $DRIVE_NAME=$ISO_FILE"" -C `getSectorNumbers $DRIVE_NAME`"
           else
               BURN_COMMAND="growisofs -speed=1 -Z -dvd-compat $DRIVE_NAME=$ISO_FILE"
           fi
       fi
       CLOSING_COMMAND=""
   fi
   
   if [[ $closing_needed -eq 1 ]];
   then
        echo `cutedate`"After successful writing the disk will have no enough space and should be replaced." >>$LOG_F
   fi
}
# --- For DVD-RW:
echo $nameMedia | grep -i "dvd_rw" >/dev/null &&\
{
  if [[ ${MULTI} -eq 1 ]];
  then           # Multi session is set to ON - sequential mode    
      if [[ $burning_needed -eq 1 ]];
      then
	  if [[ $blankMedia -eq 1 ]];
	  then   # Disk is blank. 
		BURN_COMMAND="dvd+rw-format -blank=full $DRIVE_NAME && growisofs -speed=1 -Z $DRIVE_NAME=$ISO_FILE"
	  else   # Disk is not blank.
		BURN_COMMAND="growisofs -speed=1 -M $DRIVE_NAME=$ISO_FILE"" -C `getSectorNumbers $DRIVE_NAME`"
		sector_numbers=" -C `getSectorNumbers $DRIVE_NAME`"
	  fi
      fi 
      # Warn if this disk will be written last time:
      if [[ $closing_needed -eq 1 ]];
      then
           echo `cutedate`"After successful writing the disk will have no enough space and should be replaced." >>$LOG_F
      fi
  else  # Multi session is set to OFF - restricted overwrite       
      if [[ $burning_needed -eq 1 ]];
      then  # It needs to be burnt
	  if [[ $blankMedia -eq 1 ]];
	  then  # Disk is blank. 
                BURN_COMMAND="dvd+rw-format $DRIVE_NAME && growisofs -speed=1 -Z $DRIVE_NAME=$ISO_FILE"
                CLOSING_COMMAND=""
	  else # Disk is not blank. 
	        BURN_COMMAND="growisofs -speed=1 -M $DRIVE_NAME=$ISO_FILE"
		CLOSING_COMMAND=""
	  fi
      fi
      # Warn if this disk will be written last time:
      if [[ $closing_needed -eq 1 ]];
      then
           echo `cutedate`"After successful writing the disk will have no enough space and should be replaced." >>$LOG_F
      fi
  fi
}
#  -------------------------------------------------------------------------------
#  ------    generating ISO:
# sector_numbers holds either empty string or sector numbers in format 0,0.
# They are needed for generating ISO file that is suitable for multi sessions.
dir_name="backup_"`date +"%y%m%d_%H%M"`
genisoimage -f -r -J -root $dir_name -o $ISO_FILE "$SOURCE_FILES_DIR"
test $? -ne 0 &&\
{
       CREATED_FILES=$CREATED_FILES"$ISO_FILE "
       ERR_MSG=$ERR_MSG`cutedate`"Error during ISO creation. Aborting.""\n"
       exit 1
}
CREATED_FILES=$CREATED_FILES"$ISO_FILE "
# ----


# Calculate expected md5 sum of the disk after burning:
#if [[ $cur_size -eq 0 ]];
#then
#     MD5SUM=`md5sum $ISO_FILE | awk '{print $1;}'`
#else
#     MD5SUM=`{ dd if="$DRIVE_NAME" bs=1 count=$cur_size && cat $ISO_FILE ; } | md5sum | awk '{print $1;}'`
#fi
# -------

# Get the file size of the ISO image:
ISO_FILE_SIZE=`stat --format=%s $ISO_FILE`



# ---------------- burning part --------------------------
(\
echo `cutedate`" Burning is starting." >>$LOG_F
/usr/bin/eject -a off ${DRIVE_NAME}

if [[ ! -z $BURN_COMMAND ]];
then
    eval $BURN_COMMAND &&\
    echo `cutedate`" Burning completed." >>$LOG_F ||\
    {
       echo `cutedate`"Error. Burning has been failed. Iso image is kept for future use." >>$ERR_F
       /usr/bin/eject -s "$DRIVE_NAME"
       exit 1
    }
fi

if [[ ! -z $CLOSING_COMMAND ]];
then
    eval $CLOSING_COMMAND &&\
    echo `cutedate`"Disk has been finalized." >>$LOG_F ||\
    {
      echo `cutedate`"Error. Unable to finalize the disk. Iso image is kept for future use." >>$ERR_F
      /usr/bin/eject -s "$DRIVE_NAME"
      exit 1
    }
fi

# If disk is still inserted, calculate md5 sums and compare them.
#hasMedia=`udisks --show-info "$DRIVE_NAME" | awk -F ':' '{ if ($0 ~ "has media") { match($2,"[01] *\(*"); print substr($2,RSTART,1); }}'`
#if [[ $hasMedia -eq 1 ]];
#then
   # Checking md5 sum of first ISO_FILE_SIZE bytes on the disk:
   # bs - how many bytes at a time to read and write (block size)
   # count=xxxx - copy only xxxx input blocks
#   probable_total_size=`echo "$cur_size + $ISO_FILE_SIZE" | bc`
#   resulted_md5=`dd if=${DRIVE_NAME} bs=1 count=$probable_total_size | /usr/bin/md5sum | awk '{print $1;}'`
   
#   if [[ "$resulted_md5" != "$MD5SUM" ]];
#   then
#      echo `cutedate`" Disk has different md5 sum than the iso-file. Disk may have corrupted data. Iso image is kept for future use." >>$LOG_F
#   else  
#      rm $ISO_FILE >/dev/null 2>/dev/null
#   fi
#   /usr/bin/eject -s "$DRIVE_NAME"
#fi
rm $ISO_FILE >/dev/null 2>/dev/null
/usr/bin/eject -s "$DRIVE_NAME" >/dev/null 2>/dev/null)&
exit 0