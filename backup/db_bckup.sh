#!/usr/local/bin/bash -
# This script reads file .settings from the same directory.
# According to set settings this script performs database dumping
# and saves global sql data of the cluster (roles and so on).
# It deletes old backups if amount of dump files is bigger than the value in
# .settings file. It also copies dump and global sql files to the directory
# specified in .settings file as "reserved". The script finds out how old the
#  last dump in "reserved" directory. The setting reserved_backup_frequency
# defines how many days should pass before this script copies newly made dump to
# "reserved" directory. It also deletes old copies if they exceed limits.
#

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

#
function cutedate() {
  local cutedate=`date +'<%d.%m.%y>%H:%M:%S '`
  echo "$cutedate"
}
     
function rotate_db_bckup() {
  local DIR=$1
  local LIMIT=$2
  local oldest_dump=""
  local oldest_global=""

  test ${DIR:0-1} != "/" && DIR=$DIR"/"

  while [[ `ls -l $DIR | awk '{if(NR>1){ if ($NF ~ ".*\\.dump\\."){ print $NF}}}' | wc -l` -gt $LIMIT ]]
  do  # We exceeded the limits. It's time to delete the most old one:
      oldest_dump=""
      oldest_global=""
      oldest_dump=`ls -ltr $DIR | awk '{if(NR>1){ if ($NF ~ ".*\\.dump\\."){ print $NF; exit }}}'`
      oldest_global=`ls -ltr $DIR | awk '{if(NR>1){ if ($NF ~ ".*\\.sql\\."){ print $NF; exit }}}'`
      test -z $oldest_dump || rm -f "$DIR"$oldest_dump
      test -z $oldest_global || rm -f "$DIR"$oldest_global
  done
  return 0
}


while getopts d: option
do
 case "${option}"
 in
                d) database_n=${OPTARG};;
 esac
done

# Setting variables up
NAME_DB=$database_n
NAME_DUMP=""
NAME_GLOBAL=""
USER_DB="pgsql"
CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`
SETTINGS_F=$CURPATH".settings"
LOG_F="/var/log/backup.log"
ERR_F="/var/log/backup.log"
USER_TO_MAIL="lon"
# hardcoded maximum of allowed dump files to store if all of them are made on the same day:
MAX_DUMPS_OF_THE_DAY=3

NAME_DUMP=""
NAME_GLOBAL=""

# ERR_MSG holds message to send to the user and to logs. All whitespaces 
# must be replaced by escape characters.
ERR_MSG="" 

# This name will be used in outgoing emails:
MYNAME="server"

M_BACKUP_DIR=""
DB_BACKUP_DIR=""
M_BACKUP_LIMIT=0
RES_M_BACKUP_DIR=""
RES_D_BACKUP_DIR=""
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
         "db_backup_dir") DB_BACKUP_DIR="$parameter_val" 
         test ${DB_BACKUP_DIR:0-1} != "/" && DB_BACKUP_DIR=$DB_BACKUP_DIR"/"
         ;;
         "main_backup_limit") M_BACKUP_LIMIT=$parameter_val ;;
         "reserved_main_backup_dir") RES_M_BACKUP_DIR="$parameter_val" 
         test ${RES_M_BACKUP_DIR:0-1} != "/" && RES_M_BACKUP_DIR=$RES_M_BACKUP_DIR"/"
         ;;
         "reserved_db_backup_dir") RES_D_BACKUP_DIR="$parameter_val" 
         test ${RES_D_BACKUP_DIR:0-1} != "/" && RES_D_BACKUP_DIR=$RES_D_BACKUP_DIR"/"
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
test -d $DB_BACKUP_DIR || REASONS="$REASONS $DB_BACKUP_DIR not found; "
test -w $DB_BACKUP_DIR || REASONS="$REASONS $DB_BACKUP_DIR is not writable; "

test -d $RES_M_BACKUP_DIR || REASONS="$REASONS $RES_M_BACKUP_DIR not found; "
test -w $RES_M_BACKUP_DIR || REASONS="$REASONS $RES_M_BACKUP_DIR is not writable; "

test -d $RES_D_BACKUP_DIR || REASONS="$REASONS $RES_D_BACKUP_DIR not found; "
test -w $RES_D_BACKUP_DIR || REASONS="$REASONS $RES_D_BACKUP_DIR is not writable; "

test $M_BACKUP_LIMIT -lt 1 && REASONS="$REASONS main backup limit is less than 1; "
test $M_BACKUP_LIMIT -gt 15 && REASONS="$REASONS main backup limit is too big; "

test $RES_BACKUP_LIMIT -lt 1 && REASONS="$REASONS reserved backup limit is less than 1; "
test $RES_BACKUP_LIMIT -gt 15 && REASONS="$REASONS reserved backup limit is too big; "

test $RES_BACKUP_FREQ -lt 1 && REASONS="$REASONS reserved backup frequency is less than 1; "
test $RES_BACKUP_FREQ -gt 28 && REASONS="$REASONS reserved backup frequency is bigger than 28; "

test ! -z "$REASONS" &&\
{
 ERR_MSG=$ERR_MSG`cutedate`"$REASONS""\n"
 #echo -e "$ERR_MSG" >>$ERR_F
 exit 1
}

test -w $LOG_F || LOG_F=/dev/tty
test -f $LOG_F || LOG_F=/dev/tty

test -w $ERR_F || ERR_F=/dev/tty
test -f $ERR_F || ERR_F=/dev/tty
# end of checking all parsed varibales

# Checking supplied database name:
if [[ -z "$database_n" ]];
then
    ERR_MSG=$ERR_MSG`cutedate`"You forgot to add: -d 'database name'""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    exit 1
else
# check that database exist
    test `psql -t -U $USER_DB --list | awk 'BEGIN{name="'$NAME_DB'"; count=0; }{ if($1==name){ count=count+1;}}END{print count;}'` -eq 1 &&\
    { # Db does exist. Modify our DB_BACKUP_DIR and RES_D_BACKUP_DIR by adding database name.
      DB_BACKUP_DIR=$DB_BACKUP_DIR"$NAME_DB""/"
      
      RES_D_BACKUP_DIR=$RES_D_BACKUP_DIR"$NAME_DB""/"
    } || \
    {
      ERR_MSG=$ERR_MSG`cutedate`"$NAME_DB is either doesn't exist or has multiple copies.""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1
    }
fi

#  Create directories for database dump if they don't exist yet
test ! -d $DB_BACKUP_DIR && \
{
    mkdir $DB_BACKUP_DIR 2>/dev/null || \
    { 
      ERR_MSG=$ERR_MSG`cutedate`"$DB_BACKUP_DIR can not be created""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1 
    }
}
test ! -d $RES_D_BACKUP_DIR && \
{
    mkdir $RES_D_BACKUP_DIR 2>/dev/null || \
    {
      ERR_MSG=$ERR_MSG`cutedate`"$RES_D_BACKUP_DIR can not be created""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1
    }
}


# The suffix for new database dump name
suffix=`date +"%y%m%d"`

if [[ `ls -tr $DB_BACKUP_DIR | grep ".dump."$suffix | wc -l` -lt $MAX_DUMPS_OF_THE_DAY ]];
then   # We can add proper number to suffix and then, get proper name for dump.
    i=0
    while [[ $i -lt $MAX_DUMPS_OF_THE_DAY ]];
    do
        test $i -eq 0 &&\
        {
         ls -ltr $DB_BACKUP_DIR"$NAME_DB"".dump.""$suffix" >/dev/null 2>&1 ||\
         NAME_DUMP="$NAME_DB"".dump.""$suffix"
         NAME_GLOBAL="$NAME_DB"".sql.""$suffix"
        } || \
        {
	 ls -ltr $DB_BACKUP_DIR"$NAME_DB"".dump.""$suffix""_$i" >/dev/null 2>&1 ||\
	 NAME_DUMP="$NAME_DB"".dump.""$suffix""_$i"
	 NAME_GLOBAL="$NAME_DB"".sql.""$suffix""_$i"
	}
	test -z $NAME_DUMP || break
	i=` expr $i + 1`
    done
    test -z $NAME_DUMP && \
    {
      ERR_MSG=$ERR_MSG`cutedate`"Error. Cant find the name for dump file.""\n"
      #echo -e "$ERR_MSG" >>$ERR_F
      exit 1
    }
else
  # There are too many dumps today. Don't do anything.
   ERR_MSG=$ERR_MSG`cutedate`"Error. Too many backups done today in $DB_BACKUP_DIR. Try tomorrow.""\n"
   #echo -e "$ERR_MSG" >>$ERR_F
   exit 1
fi


# We should now have "$NAME_DB"".dump.""$suffix""$i" in the NAME_DUMP
#    and config's $DB_BACKUP_DIR"$NAME_DB" as a DB_BACKUP_DIR.
#    And also config's $RES_D_BACKUP_DIR"$NAME_DB" as a $RES_D_BACKUP_DIR.

# Dumping database into custom format archive:
pg_dump -h 127.0.0.1 -U $USER_DB -Fc --compress=4 -f "$DB_BACKUP_DIR""$NAME_DUMP" $NAME_DB 2>>$ERR_F

if [ $? -eq 0 ];
then
    echo `cutedate`"Dumping $NAME_DB database completed." >>$LOG_F
else
    ERR_MSG=$ERR_MSG`cutedate`"Dumping $NAME_DB database failed.""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    exit 1
fi


pg_dumpall -h 127.0.0.1 -U pgsql -g -f "$DB_BACKUP_DIR""$NAME_GLOBAL" 2>>$ERR_F

if [ $? -eq 0 ];
then
    echo `cutedate`"Saving global sql data completed." >>$LOG_F
else
    ERR_MSG=$ERR_MSG`cutedate`"Saving global sql data failed.""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    exit 1
fi
# Rotate dump and global
rotate_db_bckup $DB_BACKUP_DIR $M_BACKUP_LIMIT || \
{
  ERR_MSG=$ERR_MSG`cutedate`"Error occurred while deleting excessive files in $DB_BACKUP_DIR""\n"
  #echo -e "$ERR_MSG" >>$ERR_F
  exit 1
}

# Check if today we need to copy our dump to reserved directory:
i=0
while [[ $i -lt $RES_BACKUP_FREQ ]];
do
   pattern=`date -v-"$i"d +"%y%m%d"`
   ls -l $RES_D_BACKUP_DIR | grep "$NAME_DB"".dump.""$pattern" >/dev/null 2>&1 && break
   ls -l $RES_D_BACKUP_DIR | grep "$NAME_DB"".sql.""$pattern" >/dev/null 2>&1 && break
   i=` expr $i + 1`
done   
test $i -ge $RES_BACKUP_FREQ &&\
{  # We haven't found any backups whithin $RES_BACKUP_FREQ number of days ago
   # this means we have to copy
   cp -n "$DB_BACKUP_DIR""$NAME_DUMP" $RES_D_BACKUP_DIR"$NAME_DUMP" ||\
   {
     ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save in $RES_D_BACKUP_DIR""\n"
     #echo -e "$ERR_MSG" >>$ERR_F
     exit 1
   }
   cp -n "$DB_BACKUP_DIR""$NAME_GLOBAL" $RES_D_BACKUP_DIR"$NAME_GLOBAL" ||\
   {
     ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save in $RES_D_BACKUP_DIR""\n"
     #echo -e "$ERR_MSG" >>$ERR_F
     exit 1
   }
   # Rotate reserved dump and reserved global
   rotate_db_bckup $RES_D_BACKUP_DIR $RES_BACKUP_LIMIT || \
   {
    ERR_MSG=$ERR_MSG`cutedate`"Error occurred while deleting excessive files in $RES_D_BACKUP_DIR""\n"
    #echo -e "$ERR_MSG" >>$ERR_F
    exit 1
   }
}
exit 0