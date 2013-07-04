#!/bin/bash -

#
#  Script that reads configuration file on the remote host
#   to define where backups stored and get that backups to save locally
# 

# give a nice date
function cutedate() {
  local cutedate=`date +'<%d.%m.%y>%H:%M:%S '`
  echo "$cutedate"
}

function show_help() {
  echo "Usage:"
  echo "       [ -a remote_address ] [ -c remote_config ] [ -u remote_user ] "
  return 0
}

# function executed when exit command is run
function onexit() {
  local error_msg="$1"
  if [[ ! -z $error_msg  ]];
  then  # MAIL user with this message
      error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
      test -z "$USER_TO_MAIL" ||\
      echo -e "$error_msg" >> $ERR_F
      local j=`echo "$CREATED_LINKS" | awk '{print NF; exit;}'`
    # Try to delete all created links:
      while [[ $j -gt 0 ]]
      do
	   local cur_link=`echo "$CREATED_LINKS" | awk '{print $"'$j'"; exit;}'`
	   unlink $cur_link
	   j=` expr $j - 1 `
      done
  # Try to delete created directories if they empty:
      local i=`echo "$CREATED_DIRS" | awk '{print NF; exit;}'`
      while [[ $i -gt 0 ]]
      do
          local cur_dir=`echo "$CREATED_DIRS" | awk '{print $"'$i'"; exit;}'`
          test -d $cur_dir -a $cur_dir != "/" &&\
          {
             rmdir "$cur_dir" >/dev/null 2>/dev/null
          }
          i=` expr $i - 1 `
      done
  fi
}

# function executed when errors occur
function onerror() {
  local error_msg="$1"
  error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
  test -z "$USER_TO_MAIL" ||\
  echo -e "Backup script has errors.\n""$error_msg" >> $ERR_F
}

function ontermination() {
  local error_msg="$1"
  error_msg=`echo -e "$error_msg" | awk '{if ($0 !~ "^$"){print $0;}}'`
  test -z "$USER_TO_MAIL" ||\
  echo -e "Backup script has been terminated.\n""$error_msg" >> $ERR_F
    local j=`echo "$CREATED_LINKS" | awk '{print NF; exit;}'`
    # Try to delete all created links:
      while [[ $j -gt 0 ]]
      do
	   local cur_link=`echo "$CREATED_LINKS" | awk '{print $"'$j'"; exit;}'`
	   unlink $cur_link
	   j=` expr $j - 1 `
      done
  # Try to delete created directories if they empty:
      local i=`echo "$CREATED_DIRS" | awk '{print NF; exit;}'`
      while [[ $i -gt 0 ]]
      do
          local cur_dir=`echo "$CREATED_DIRS" | awk '{print $"'$i'"; exit;}'`
          test -d $cur_dir -a $cur_dir != "/" &&\
          {
             rmdir "$cur_dir" >/dev/null 2>/dev/null
          }
          i=` expr $i - 1 `
      done
}

function save_local_content() {
  local local_dir=$1
  local today=$TODAY_SUFFIX
  test -d $local_dir || exit 1
  local local_size=`du -b -d0 -L $local_dir | awk '{print $1;}'`
  test $local_size -eq 0 && exit 1
  
  test -d $TEMP_DIR"local/" ||\
  {
    mkdir $TEMP_DIR"local/" >/dev/null 2>/dev/null
    test $? -ne 0 && exit 1
  }
  
  test -d $TEMP_DIR"local/""local_"$today || \
  {
   mkdir $TEMP_DIR"local/""local_"$today >/dev/null 2>/dev/null
   if [[ $? -ne 0 ]];
   then 
      exit 1
   fi
  }  
  cp -r $local_dir $TEMP_DIR"local/""local_"$today 2>>$ERR_F || exit 1
  if [[ ! -z `ls $TEMP_DIR"lastbackup" | grep "local"` ]];
  then
        while [[ 1 ]];
        do
            to_delete=`ls $TEMP_DIR"lastbackup" | grep "local" | awk '{ if(NR==1){print $0; exit}}'`
            test -z "$to_delete" && break
            test -L $TEMP_DIR"lastbackup/""$to_delete" -o -f $TEMP_DIR"lastbackup/""$to_delete" && rm $TEMP_DIR"lastbackup/"$to_delete
       done
   fi
   ln -s $TEMP_DIR"local/""local_"$today $TEMP_DIR"lastbackup/""local""_backup_"$today &&\
   return 0
}

# Variables
CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`
SETTINGS_F=$CURPATH".settings"
CREATED_DIRS=""
CREATED_LINKS=""
DIRECTORIES_TO_ISO="" # this variable will store directory names with saved files inside (dumps and backups).
# supplemential variables for remote control:
TODAY_SUFFIX=`date +'%y%m%d'`
R_CONFIG_TEXT=""   # text of .settings file on remote host
R_LS_M_DIR=""      # Result of ls command on main backup directory on remote host
R_LS_DB_DIR=""
R_M_NAME=""    # name of chosen main backup file on remote host
R_DB_NAME=""
R_DB_SQL_NAME=""
# defaults for settings parameters
LOG_F="/dev/tty"
ERR_F="/dev/tty"
USER_TO_MAIL="oleg"
ERR_MSG=""
MYNAME="server"
R_HOST=""
R_USER=""
R_CONFIG=""
TEMP_DIR=""
TEMP_DIR_LIMIT=1
BURN_PROG=""
BURN_PROG_ARGS=""
ISO_DIR=""
#Variables from remote config:
R_M_DIR=""
R_DB_DIR=""


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
         "remote_host") R_HOST="$parameter_val" ;;
         "remote_user") R_USER="$parameter_val" ;;
         "remote_config") test -z "$parameter_val" && R_CONFIG="~/remote_backup/.settings" ||\
			  R_CONFIG=$parameter_val ;;
         "temp_directory") TEMP_DIR=$parameter_val 
			   test ${TEMP_DIR:0-1} != "/" && TEMP_DIR=$TEMP_DIR"/";;
	 "temp_directory_limit") test $parameter_val -ge 1 && TEMP_DIR_LIMIT=$parameter_val ;;
     esac
done <"${SETTINGS_F:?'Sorry no settings file was found. Aborting.'}"
# end of parsing .settings file

while getopts a:h:u:c:l: option
do
 case "${option}"
 in
		c) R_CONFIG=${OPTARG} ;;
		a) R_HOST=${OPTARG} ;;
		u) R_USER=${OPTARG} ;;
		l) LOCAL_DIR=${OPTARG} ;;
                h) show_help >/dev/tty
                   exit 0           ;;
 esac
done


trap "{ onexit \"\$ERR_MSG\"  ; }" EXIT
#trap "{ onerror \"\$ERR_MSG\" ; exit 1 ; }" ERR
trap "{ ontermination \"\$ERR_MSG\"  ; }" TERM
trap "{ ontermination \"\$ERR_MSG\"  ; }" HUP

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

test -w $LOG_F || LOG_F=/dev/tty
test -f $LOG_F || LOG_F=/dev/tty
test -w $ERR_F || ERR_F=/dev/tty
test -f $ERR_F || ERR_F=/dev/tty

test -z "$LOCAL_DIR" || \
{
  save_local_content "$LOCAL_DIR"
  if [[ $? -eq 0 ]];
  then
        echo `cutedate`"Local content of directory $LOCAL_DIR saved successfully." >>$LOG_F
        exit 0
  else
        ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save local content from $LOCAL_DIR to $TEMP_DIR""\n"
        exit 1
  fi
}

test -z "$R_HOST" &&\
{  # not specified
   ERR_MSG=$ERR_MSG`cutedate`"Error. remote_host not set.""\n"
   exit 1
}

test -z "$R_USER" &&\
{ # not specified
    ERR_MSG=$ERR_MSG`cutedate`"Error. remote_user not set.""\n"
    exit 1
}

#  Check if remote_host is reachable:
ping -w 2 $R_HOST >/dev/null ||\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. $R_HOST host is unreachable now.""\n"
   exit 1
}

# Create subdirectory in TEMP_DIR to store downloaded backup there:
test -d $TEMP_DIR"$R_HOST" || \
{
   mkdir $TEMP_DIR"$R_HOST" >/dev/null 2>/dev/null
   if [[ $? -ne 0 ]];
   then 
      ERR_MSG=$ERR_MSG`cutedate`"Error. Can not create $TEMP_DIR"$R_HOST" directory.""\n"
      exit 1
   else
      CREATED_DIRS=$CREATED_DIRS$TEMP_DIR"$R_HOST"" "
   fi
}
# Create subdirectory in TEMP_DIR for symbolic links to the backup :
test -d $TEMP_DIR"lastbackup" || \
{
   mkdir $TEMP_DIR"lastbackup" >/dev/null 2>/dev/null
   if [[ $? -ne 0 ]];
   then 
      ERR_MSG=$ERR_MSG`cutedate`"Error. Can not create $TEMP_DIR'lastbackup' directory.""\n"
      exit 1
   else
      CREATED_DIRS=$CREATED_DIRS$TEMP_DIR"lastbackup"" "
   fi
}

# Deleting excessive backups in $TEMP_DIR"$R_HOST" :
cur_amount=`ls -ltr $TEMP_DIR"$R_HOST" | wc -l`
while [[ $cur_amount -ge $TEMP_DIR_LIMIT ]];
do
      to_delete_dir=`ls -ltr $TEMP_DIR"$R_HOST" | awk '{ if (NR>1){print $9; exit;}}'`
      test -z $to_delete_dir && break
      rm -R $TEMP_DIR"$R_HOST"${to_delete_dir} ||\
      {
         ERR_MSG=$ERR_MSG`cutedate`"Error. Can not delete ${to_delete_dir} directory.""\n"
         break
      }
      cur_amount=`ls -ltr $TEMP_DIR"$R_HOST" | wc -l`
      to_delete_dir=""
done



# Create one more subdirectory
c=0
while [[ $c -lt 9 ]]
do
  test $c -eq 0 && ending="" || ending="_$c"
  mkdir $TEMP_DIR"$R_HOST/""backup."$TODAY_SUFFIX"$ending" 2>/dev/null &&\
  { 
    # Before we create new link for the backup to this host, we have to delete the old one.
    # Delete all files in lastbackup directory for current REMOTE_HOST:
    if [[ ! -z `ls $TEMP_DIR"lastbackup" | grep $R_HOST` ]];
    then
#        amount_to_del=`ls $TEMP_DIR"lastbackup" | grep $R_HOST | wc -l`
#        num=1
#       while [[ $num -le $amount_to_del ]];
        while [[ 1 ]];
        do
            to_delete=`ls $TEMP_DIR"lastbackup" | grep $R_HOST | awk '{ if(NR==1){print $0; exit}}'`
            test -z "$to_delete" && break
            test -L $TEMP_DIR"lastbackup/""$to_delete" -o -f $TEMP_DIR"lastbackup/""$to_delete" && rm $TEMP_DIR"lastbackup/"$to_delete
#            num=` expr $num + 1 `
       done
    fi
    ln -s $TEMP_DIR"$R_HOST/""backup."$TODAY_SUFFIX"$ending" $TEMP_DIR"lastbackup/"$R_HOST"_backup_"$TODAY_SUFFIX"$ending"
    CREATED_LINKS=$CREATED_LINKS$TEMP_DIR"lastbackup/"$R_HOST"_backup_"$TODAY_SUFFIX"$ending"" "
    TEMP_DIR=$TEMP_DIR"$R_HOST/""backup."$TODAY_SUFFIX"$ending/"
    CREATED_DIRS=$CREATED_DIRS$TEMP_DIR" "
    DIRECTORIES_TO_ISO=$DIRECTORIES_TO_ISO" "$TEMP_DIR
    break
  } ||\
  {
    c=` expr $c + 1 `
  }
done
test $c -ge 9 &&\
{  
    ERR_MSG=$ERR_MSG`cutedate`"Error. Can not create a subdirectory in $TEMP_DIR$R_HOST/.""\n"
    exit 1
}
unset c
# Parsing remote_host configuration parameters
R_CONFIG_TEXT=`ssh $R_USER@$R_HOST "cat $R_CONFIG" | sed 's/ //g' | sed -e 's/#.*//' -e '/^$/ d'` ||\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. Can not read settings from remote_config file.""\n"
   exit 1
}
#echo "$R_CONFIG_TEXT" # << testing purpose

test -z "$R_CONFIG_TEXT" &&\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. Can not read remote config. Maybe authentication problems. ""\n"
   exit 1
}
#      ....    All   about    main     backup     from    remote    server   ....
R_M_DIR=`echo "$R_CONFIG_TEXT" | awk -F "=" '\
{if ($1=="main_backup_dir"){\
print $2;}\
}'`

test ${R_M_DIR:0-1} != "/" && R_M_DIR=$R_M_DIR"/"

test -z "$R_M_DIR" &&\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. The value of remote's main_backup_dir not found. ""\n"
   exit 1
}

# Get results of `ls` command from remote's server backup dirs:
R_LS_M_DIR=`ssh $R_USER@$R_HOST "ls -lht \"\$R_M_DIR\""`

# How many today's main backups remote server has:
r_m_name_wc=`echo "$R_LS_M_DIR" | grep $TODAY_SUFFIX | wc -l`

# Getting the last one (with $TODAY_SUFFIX_$i maximum value).
i=$r_m_name_wc
while [[ $i -ge 0 ]];
do
     R_M_NAME=""
     if [[ $i -eq 0 ]]; 
     then 
       R_M_NAME=`echo "$R_LS_M_DIR" | awk '{print $NF;}' | grep $TODAY_SUFFIX`
     fi
     if [[ $i -gt 0 ]];
     then
       R_M_NAME=`echo "$R_LS_M_DIR" | awk '{print $NF;}' | grep $TODAY_SUFFIX"_$i"`
     fi
     test -z $R_M_NAME || break
     i=` expr $i - 1 `
done

# We should get the name of last today's main backup on remote server. But if not:
test -z $R_M_NAME &&\
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. Can not find last today's main backup on remote server. ""\n"
   exit 1
}

# Get today's main backup from remote server
ssh $R_USER@$R_HOST "cat \"$R_M_DIR\"\"$R_M_NAME\"" | cat >$TEMP_DIR"$R_M_NAME" &&\
{
  echo `cutedate`"$TEMP_DIR$R_M_NAME successfully saved." >>$LOG_F
} || \
{
   ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save dump $R_M_NAME from $R_HOST to $TEMP_DIR""\n"
   exit 1
}



#      ....    All   about    database   backups    from    remote    server   ....

# About db_backup_dir:  There might be plenty of them.
R_DB_DIR_count=`echo "$R_CONFIG_TEXT" | awk -F '=' '\
{if ($1=="db_backup_dir"){\
print $2;}\
}' | wc -l`

#   For every db_backup_dir we are going to save it
j=1
while [[ $j -le $R_DB_DIR_count ]]
do
  R_DB_DIR=`echo "$R_CONFIG_TEXT" | awk -F '=' '\
  {if ($1=="db_backup_dir"){\
  print $2;}\
  }' | awk '{if (NR=="'$j'"){ print $0; }}'`
  
  test ${R_DB_DIR:0-1} != "/" && R_DB_DIR=$R_DB_DIR"/"
  
  test -z "$R_DB_DIR" &&\
  {
    ERR_MSG=$ERR_MSG`cutedate`"Error. The value of remote's db_backup_dir not found. ""\n"
    exit 1
  }
  
  # Get results of `ls` command from remote's server backup dirs:
  R_LS_DB_DIR=`ssh $R_USER@$R_HOST "ls -lht \"\$R_DB_DIR\""`
  
  # How many today's database dump backups remote server has:
  r_db_name_wc=`echo "$R_LS_DB_DIR" | grep ".dump."$TODAY_SUFFIX | wc -l`
  
  # Getting the last one (with $TODAY_SUFFIX_$i maximum value).
  i=$r_db_name_wc
  while [[ $i -ge 0 ]];
  do
      R_DB_NAME=""
      if [[ $i -eq 0 ]]; 
      then 
	R_DB_NAME=`echo "$R_LS_DB_DIR" | awk '{print $NF;}' | grep ".dump."$TODAY_SUFFIX`
      fi
      if [[ $i -gt 0 ]];
      then
	R_DB_NAME=`echo "$R_LS_DB_DIR" | awk '{print $NF;}' | grep ".dump."$TODAY_SUFFIX"_$i"`
      fi
      test -z $R_DB_NAME || break
      i=` expr $i - 1 `
  done
  
  # We should get the name of last today's database backup on remote server. But if not:
  test -z $R_DB_NAME &&\
  {
    ERR_MSG=$ERR_MSG`cutedate`"Error. Can not find last today's database dump on remote server. ""\n"
    exit 1
  }
  
  # How many today's database sql backups remote server has:
  r_db_sql_name_wc=`echo "$R_LS_DB_DIR" | grep ".sql."$TODAY_SUFFIX | wc -l`
  
  # Getting the last one (with $TODAY_SUFFIX_$i maximum value).
  i=$r_db_sql_name_wc
  while [[ $i -ge 0 ]];
  do
      R_DB_SQL_NAME=""
      if [[ $i -eq 0 ]]; 
      then 
	R_DB_SQL_NAME=`echo "$R_LS_DB_DIR" | awk '{print $NF;}' | grep ".sql."$TODAY_SUFFIX`
      fi
      if [[ $i -gt 0 ]];
      then
	R_DB_SQL_NAME=`echo "$R_LS_DB_DIR" | awk '{print $NF;}' | grep ".sql."$TODAY_SUFFIX"_$i"`
      fi
      test -z $R_DB_SQL_NAME || break
      i=` expr $i - 1 `
  done
  
  # We should get the name of last today's database sql backup on remote server. But if not:
  test -z $R_DB_SQL_NAME &&\
  {
    ERR_MSG=$ERR_MSG`cutedate`"Error. Can not find today's last database sql backup on remote server. ""\n"
    exit 1
  }

  # Get today's db dump from remote server
  ssh $R_USER@$R_HOST "cat \"$R_DB_DIR\"\"$R_DB_NAME\"" | cat >$TEMP_DIR"$R_DB_NAME" &&\
  {
    echo `cutedate`"$TEMP_DIR$R_DB_NAME dump successfully saved." >>$LOG_F
  } || \
  {
    ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save $R_DB_NAME from $R_HOST to $TEMP_DIR""\n"
    exit 1
  }
  
  # Get today's db sql backup from remote server
  ssh $R_USER@$R_HOST "cat \"$R_DB_DIR\"\"$R_DB_SQL_NAME\"" | cat >$TEMP_DIR"$R_DB_SQL_NAME" &&\
  {
    echo `cutedate`"$TEMP_DIR$R_DB_SQL_NAME global sql file successfully saved." >>$LOG_F
  } || \
  {
    ERR_MSG=$ERR_MSG`cutedate`"Error. Can not save global sql file $R_DB_SQL_NAME from $R_HOST to $TEMP_DIR""\n"
    exit 1
  }
  j=` expr $j + 1 `
done
  exit 0

