#!/usr/local/bin/bash -
# This script reads file .settings from the same directory.
# Also this script reads list_file file that must be in the
# same directory. It packs every file listed there into new tar file.
# Then it uses gzip for archiving. 
# It deletes old backups if amount of backups is bigger than the allowed value in
# .settings file. 
# It also copies newle made backup file to the directory
# specified in .settings file as "reserved". The script finds out how old the
#  last saved backup in "reserved" directory. The setting reserved_backup_frequency
# defines how many days should pass before this script copies newly made backup to
# "reserved" directory. It also deletes old copies if they exceed limits (limits
# are also specified in .settings file).

# 
# If script can't write to log_file (defined in .settings), it will print all
# messages to /dev/tty
# 

# Upon any error the message is appended to $ERR_MSG. If exception is minor, 
# the script continues to run, otherwise it exits. 
# Whether EXIT or ERR occurs, script schecks if ERR_MSG has anything in it.
# If so, the script writes it to $ERR_F (error file) and sends the email to
# the user ($USER_TO_MAIL).
#


# function executed when exit command is run
function onexit() {
  local error_msg="$1"
  if [[ ! -z $error_msg  ]];
  then  # MAIL user with this message
      error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
      test -z "$USER_TO_MAIL" ||\
      echo -e "$error_msg" | tee -a $ERR_F | mail -s"$MYNAME:BACKUP WARNING" $USER_TO_MAIL
  fi
}

# function executed when errors occur
function onerror() {
  local error_msg="$1"
  error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
  test -z "$USER_TO_MAIL" ||\
  echo -e "Backup script has errors.\n""$error_msg" | tee -a $ERR_F | mail -s"$MYNAME:BACKUP ERRORS" $USER_TO_MAIL
}

function ontermination() {
  local error_msg="$1"
  error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
  test -z "$USER_TO_MAIL" ||\
  echo -e "Backup script has been terminated.\n""$error_msg" | tee -a $ERR_F | mail -s"$MYNAME:BACKUP ERRORS" $USER_TO_MAIL
}

# give a nice date
function cutedate() {
  local cutedate=`date +'<%d.%m.%y>%H:%M:%S '`
  echo "$cutedate"
}

# delete old backup files if amount of them is bigger that required
function rotate_bckup() {
  local DIR=$1
  local LIMIT=$2
  local oldest=""

  test ${DIR:0-1} != "/" && DIR=$DIR"/"

  while [[ `ls -l $DIR | awk '{if(NR>1){ if ($NF ~ "backup\.tar\.gz\."){ print $NF}}}' | wc -l` -gt $LIMIT ]]
  do  # We exceeded the limits. It's time to delete the oldest backup:
      oldest=""
      oldest=`ls -ltr $DIR | awk '{if(NR>1){ if ($NF ~ "backup\.tar\.gz\."){ print $NF; exit }}}'`   
      test -z $oldest || rm -f "$DIR"$oldest
  done
  return 0
}

# Function. accepts path to file as an argument to save there list of 
# installed packages. Each package in format "package_name:origin".
# One package in a line.
function save_packages() {
  local file_to_use=$1
  test -f $file_to_use || return 1
  test -w $file_to_use || return 1
  test -s $file_to_use && return 1
  pkg_info -a -o | awk '{if ($0~"Information for"){match($0," [a-zA-Z\\-0-9\.\,_]+:"); \
printf ("%s",substr($0, RSTART+1, RLENGTH-1));} else {if (($0 != "")&&($0 != "Origin:")){\
print $0;}}}' >$file_to_use
  test $? -eq 0 && return 0
}

# 

# Setting variables
CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`
SETTINGS_F=$CURPATH".settings"
LIST_F=$CURPATH"list_file"
LOG_F="/var/log/backup.log"
ERR_F="/var/log/backup.log"
USER_TO_MAIL="lon"
# hardcoded maximum of allowed backup files to store if all of them are made on the same day:
MAX_BACKUPS_OF_THE_DAY=3
NAME_BACKUP=""
# ERR_MSG holds message to send to the user and to logs. All whitespaces 
# must be replaced by escape characters.
ERR_MSG=""
# This name will be used in outgoing emails:
MYNAME="server"

M_BACKUP_DIR=""
M_BACKUP_LIMIT=0
RES_M_BACKUP_DIR=""
RES_BACKUP_LIMIT=0
RES_BACKUP_FREQ=0

#  Parsing .settings file:
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
         "main_backup_dir") M_BACKUP_DIR="$parameter_val" 
         test ${M_BACKUP_DIR:0-1} != "/" && M_BACKUP_DIR=$M_BACKUP_DIR"/" 
         ;;
         "main_backup_limit") M_BACKUP_LIMIT=$parameter_val ;;
         "reserved_main_backup_dir") RES_M_BACKUP_DIR="$parameter_val" 
         test ${RES_M_BACKUP_DIR:0-1} != "/" && RES_M_BACKUP_DIR=$RES_M_BACKUP_DIR"/"
         ;;
         "reserved_backup_limit") RES_BACKUP_LIMIT=$parameter_val ;;
         "reserved_backup_frequency") RES_BACKUP_FREQ=$parameter_val ;;
         "log_file") LOG_F=$parameter_val 
		     ERR_F=$parameter_val
         ;;
         "notifications_user") USER_TO_MAIL=$parameter_val ;;
         "host_name") MYNAME=$parameter_val ;;
     
     esac
done <"${SETTINGS_F:?'Sorry no settings file was found. Aborting.'}"
# end of parsing .settings file

trap "{ onexit \"\$ERR_MSG\"  ; }" EXIT
trap "{ onerror \"\$ERR_MSG\" ; }" ERR
trap "{ ontermination \"\$ERR_MSG\"  ; }" TERM
trap "{ ontermination \"\$ERR_MSG\"  ; }" HUP

REASONS=""
# Checking all parsed variables
test -d $M_BACKUP_DIR || REASONS="$REASONS $M_BACKUP_DIR not found; "
test -w $M_BACKUP_DIR || REASONS="$REASONS $M_BACKUP_DIR is not writable; "

test -d $RES_M_BACKUP_DIR || REASONS="$REASONS $RES_M_BACKUP_DIR not found; "
test -w $RES_M_BACKUP_DIR || REASONS="$REASONS $RES_M_BACKUP_DIR is not writable; "

test $M_BACKUP_LIMIT -lt 1 && REASONS="$REASONS main backup limit is less than 1; "
test $M_BACKUP_LIMIT -gt 15 && REASONS="$REASONS main backup limit is too big; "

test $RES_BACKUP_LIMIT -lt 1 && REASONS="$REASONS reserved backup limit is less than 1; "
test $RES_BACKUP_LIMIT -gt 15 && REASONS="$REASONS reserved backup limit is too big; "

test $RES_BACKUP_FREQ -lt 1 && REASONS="$REASONS reserved backup frequency is less than 1; "
test $RES_BACKUP_FREQ -gt 28 && REASONS="$REASONS reserved backup frequency is bigger than 28; "

test -w $LOG_F || LOG_F=/dev/tty
test -f $LOG_F || LOG_F=/dev/tty

test -w $ERR_F || ERR_F=/dev/tty
test -f $ERR_F || ERR_F=/dev/tty

test ! -z "$REASONS" &&\
{
 ERR_MSG=$ERR_MSG`cutedate`"$REASONS""\n"
 #echo -e "$ERR_MSG" >>$ERR_F
 exit 1
}
# end of checking all parsed varibales

# Check if the list file exists
test -f $LIST_F || \
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. $LIST_F is not proper file.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
   exit 1
}
test -r $LIST_F || \
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. $LIST_F read flag is not set.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
   exit 1
}
#

#  Create directories for backup if they don't exist yet
test ! -d $M_BACKUP_DIR && \
{
    mkdir $M_BACKUP_DIR 2>/dev/null || \
    { 
      ERR_MSG=$ERR_MSG`cutedate`"$M_BACKUP_DIR can not be created""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1 
    }
}
test ! -d $RES_M_BACKUP_DIR && \
{
    mkdir $RES_M_BACKUP_DIR 2>/dev/null || \
    {
      ERR_MSG=$ERR_MSG`cutedate`"$RES_M_BACKUP_DIR can not be created""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1
    }
}

# The suffix for new backup name
suffix=`date +"%y%m%d"`

# backup.tar.gz.130605
if [[ `ls -tr $M_BACKUP_DIR | grep ".tar.gz."$suffix | wc -l` -lt $MAX_BACKUPS_OF_THE_DAY ]];
then   # We can add proper number to suffix and then, get proper name for backup.

    i=0
    while [[ $i -lt $MAX_BACKUPS_OF_THE_DAY ]];
    do
        test $i -eq 0 &&\
        {
         ls -ltr $M_BACKUP_DIR"backup.tar.gz.""$suffix" >/dev/null 2>&1 ||\
         NAME_BACKUP="backup.tar.gz.""$suffix"
        } || \
        {
	 ls -ltr $M_BACKUP_DIR"backup.tar.gz.""$suffix""_$i" >/dev/null 2>&1 ||\
	 NAME_BACKUP="backup.tar.gz.""$suffix""_$i"
	}
	test -z $NAME_BACKUP || break
	i=` expr $i + 1`
    done
    test -z $NAME_BACKUP && \
    {
      ERR_MSG=$ERR_MSG`cutedate`"Error. Cant figure out the name for backup file.""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1
    }

else
  # There are too many dumps today. Don't do anything.
   ERR_MSG=$ERR_MSG`cutedate`"Error. Too many backups done today in $M_BACKUP_DIR. Try tomorrow.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
   exit 1
fi


# We should now have "backup.tar.gz.""$suffix""_$i" in the NAME_BACKUP
#    and config's $M_BACKUP_DIR as a M_BACKUP_DIR.
#    And also config's $RES_M_BACKUP_DIR as a $RES_M_BACKUP_DIR.


# Parsing list file and adding all the files to $NAME_BACKUP:
while read line           
do
  file_to_save=`echo $line`
  test "${file_to_save}" == "" && continue
  test -r $file_to_save || \
  {
    ERR_MSG=$ERR_MSG`cutedate`" $file_to_save was not saved. Proper file name?""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    continue
  }
  test -f $M_BACKUP_DIR"$NAME_BACKUP" && \
  { # If $NAME_BACKUP does exist, append to tar
    tar -rplLf $M_BACKUP_DIR"$NAME_BACKUP" $file_to_save >/dev/null 2>&1
    if [[ $? -ne 0 ]];
    then
        ERR_MSG=$ERR_MSG`cutedate`"$file_to_save probably was not added to backup.""\n"
	#echo -e "$ERR_MSG" >>$ERR_F
    fi
  } || \
  {  # $NAME_BACKUP does not exist, create tar.
    tar -cplLf $M_BACKUP_DIR"$NAME_BACKUP" $file_to_save >/dev/null 2>&1
    if [[ $? -ne 0 ]];
    then
        ERR_MSG=$ERR_MSG`cutedate`"$file_to_save probably was not added to backup.""\n"
        #echo -e "$ERR_MSG" >>$ERR_F
    fi
  }
done <"${LIST_F:?'Sorry no list file was found. Aborting.'}"

# Adding a file containing list of packages
touch $M_BACKUP_DIR"packages.tmp"
save_packages $M_BACKUP_DIR"packages.tmp" &&\
{
   tar -rplLf $M_BACKUP_DIR"$NAME_BACKUP" $M_BACKUP_DIR"packages.tmp" >/dev/null 2>&1
    if [[ $? -ne 0 ]];
    then
        ERR_MSG=$ERR_MSG`cutedate`"Error during adding $M_BACKUP_DIR packages.tmp to the backup.""\n"
	#echo -e "$ERR_MSG" >>$ERR_F
    fi
    rm -f $M_BACKUP_DIR"packages.tmp" >/dev/null 2>/dev/null
} || \
{
   ERR_MSG=$ERR_MSG`cutedate`"List of packages was not saved. Could not write to $M_BACKUP_DIR'packages.tmp'.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
}
# Gzipping $NAME_BACKUP:
gzip -5 $M_BACKUP_DIR"$NAME_BACKUP" ||\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. Can not compress backup using gzip.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
   exit 1
}
# Getting normal name back:
mv $M_BACKUP_DIR"$NAME_BACKUP"".gz" $M_BACKUP_DIR"$NAME_BACKUP" ||\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. Can not rename gzipped backup file.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
   exit 1
}
# Rotate backups in $M_BACKUP_DIR
rotate_bckup $M_BACKUP_DIR $M_BACKUP_LIMIT || \
   {
    ERR_MSG=$ERR_MSG`cutedate`"Error occurred while deleting excessive files in $M_BACKUP_DIR""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    exit 1
   }

# Check if today we need to copy our backup to reserved directory:
i=0
while [[ $i -lt $RES_BACKUP_FREQ ]];
do
   pattern=`date -v-"$i"d +"%y%m%d"`
   ls -l $RES_M_BACKUP_DIR | grep "backup.tar.gz.""$pattern" >/dev/null 2>&1 && break
   i=` expr $i + 1`
done

test $i -ge $RES_BACKUP_FREQ &&\
{  # We haven't found any backups whithin $RES_BACKUP_FREQ number of days ago
   # this means we have to copy
   cp -n "$M_BACKUP_DIR""$NAME_BACKUP" $RES_M_BACKUP_DIR"$NAME_BACKUP" ||\
   {
     ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save in $RES_M_BACKUP_DIR""\n"
     #echo -e "$ERR_MSG" >>$ERR_F
     exit 1
   }
   # Rotate reserved backups
   rotate_bckup $RES_M_BACKUP_DIR $RES_BACKUP_LIMIT || \
   {
    ERR_MSG=$ERR_MSG`cutedate`"Error occurred while deleting excessive files in $RES_M_BACKUP_DIR""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    exit 1
   }
}
echo `cutedate`" Backup completed." >>$LOG_F
exit 0