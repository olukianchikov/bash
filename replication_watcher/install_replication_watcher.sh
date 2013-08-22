#!/usr/local/bin/bash -
#Script to deploy replication_watcher on FreeBSD systems

function strip_trailing_slash() 
{
  echo $1 | awk '{if (substr($0, length($0),1) == "/") { print substr($0, 1, length($0)-1); } else {print $0;}}'
}

function clean_exit()
{
   local counter=1
   local max_files=`echo $CREATED_FILES | awk '{print NF;}'`
   while [[ $counter -le $max_files ]];
   do
       file_to_delete=`echo $CREATED_FILES | awk '{print $"'$counter'";}'`
       rm $file_to_delete &>/dev/null ||
	  echo "${file_to_delete} not deleted. Delete it manually."
       counter=` expr $counter + 1 `
   done
   
   local counter=1
   local max_dirs=`echo $CREATED_DIRS | awk '{print NF;}'`
   while [[ $counter -le $max_dirs ]];
   do
       dir_to_delete=`echo $CREATED_DIRS | awk '{print $"'$counter'";}'`
       rm -R $dir_to_delete &>/dev/null || rmdir $dir_to_delete &>/dev/null
       if [[ $? -ne 0 ]];
       then
           echo "${dir_to_delete} not deleted. Delete it manually."
       fi
       counter=` expr $counter + 1 `
   done
}

SRC_TAR=`echo $0 | awk -F '/' 'BEGIN{ ORS="/"} END { for (i=1; i<NF; i++) { print $i; }}'`"replication_watcher.tar"
CREATED_FILES=""
CREATED_DIRS=""
MASTER_ROLE=0
PID_DIR="/var/run/replication_watcher"
PID_F="replication_watcher.pid"

echo "This script is going to install replication_watcher."
echo "Please, make sure you run it by root."
echo "This will be done by specifying some parameters required for correct work of the script."
echo "Replication watcher is launched on system start and its main aim is to watch and detect replication proccess between two Postgresql servers."
echo "It will check the states of both Master and Standby servers and perform a failover if the Master doesn't respond."
echo "All it's operation will be logged into specified log location."
echo ""

#   trap
trap "echo 'Script aborted. Deleting created files. '; clean_exit ; exit 1" 1 2 3 6 9
#

succeed=0
while [[ $succeed -ne 1 ]]
do
  echo -n "Do you want to install replication_watcher? (y/n)"
  read answer
  if [[ "$answer" = "n" ]];
  then
      exit 0
  elif [[ "$answer" = "y" ]];
  then
      succeed=1
  fi
done

succeed=0
while [[ $succeed -ne 1 ]]
do
  root_username=`cat /etc/passwd | awk -F ':' '{if($3=="'$EUID'"){print $1; exit;}}'`
  echo -e "Is it correct OS username for root: ${root_username} (y/n): "
  read -e answer
  if [[ "$answer" = 'y' ]];
  then
      succeed=1
  elif [[ "$answer" = 'n' ]];
  then
      echo "This script must be run by root in order to copy all required files. Please, run it by root."
      exit 1
  else
      succeed=0
  fi
done


succeed=0
while [[ $succeed -ne 1 ]]
do
    echo -e "Postgresql OS username: "
    read PGUSER1
    test -f /etc/passwd &&
    {
     succeed=`cat /etc/passwd | awk -F ':' 'BEGIN{suc=0;}{if($1=="'$PGUSER1'"){suc=1;}}END{print suc;}'`
    } || { succeed=1 ; }
done

# Figuire out PGUSER1 group. It is used in chown command
PGUSER1_GROUP=`cat /etc/passwd | awk -F ':' '{if($1=="'$PGUSER1'"){print $4;}}'`
PGUSER1_GROUP=`cat /etc/passwd | awk -F ':' '{if($3=="'$PGUSER1_GROUP'"){print $1;}}'`

PGUSER1_DIR=`eval "echo ~$PGUSER1"`
PGUSER1_DIR=`strip_trailing_slash ${PGUSER1_DIR}`

# LOG_F:

    existed=1  # <- to determine if we need to delete LOG_F
    LOG_F=/var/log/replication.log
    test -f $LOG_F || existed=0
    touch ${LOG_F} &>/dev/null &&\
    {
      LOG_F=/var/log/replication.log
    } ||\
    {
      succeed=0
      while [[ $succeed -ne 1 ]]
      do
	  echo -e "Log file: "
          read -e LOG_F
          if [[ -f $LOG_F ]];
          then
	       existed=1
	  else
	       existed=0
          fi
          touch ${LOG_F} &>/dev/null &&\
          {
            chown ${PGUSER1}:${PGUSER1_GROUP} ${LOG_F} ;
            echo "Log file is: ${LOG_F}." ;
            succeed=1
          } ||\
          {
            echo "Can not create log file ${LOG_F}. Choose different path or abort the script and create it by yourself."
            succeed=0
          }
      done
    }
    
    if [[ $existed -eq 0 ]];
    then
        CREATED_FILES="$CREATED_FILES ${LOG_F}" ;
    fi

    chown ${PGUSER1}:${PGUSER1_GROUP} ${LOG_F}
    chmod 640 ${LOG_F}

# DATA_DIR:
succeed=0
while [[ $succeed -ne 1 ]]
do
    echo -e "Provide Data directory of Postgresql server: "
    read -e DATA_DIR
    ls ${DATA_DIR} &>/dev/null &&\
    {
       succeed=1
    } ||\
    {
       echo -e "Can not find it or permissions problem. Are you sure that ${DATA_DIR} is correct Data directory? (y/n) "
       read answer
       if [[ "$answer" = "y" ]];
       then
           succeed=1
       fi
    }
done
DATA_DIR=`strip_trailing_slash ${DATA_DIR}`

#check if there is recovery.conf in data_dir. If so, abort the script:
test -f ${DATA_DIR}"/recovery.conf" &&\
{
   echo "${DATA_DIR}/recovery.conf already exists. Check the file. Probably, your server is in recovery now. Aborting script."
   exit 1
}


# RC_DIR:
succeed=0
while [[ $succeed -ne 1 ]]
do
    test -d /usr/local/etc/rc.d &&\
    {
      RC_DIR=/usr/local/etc/rc.d
    } ||\
    {
      echo -e "Directory for rc startup scripts: "
      read -e RC_DIR
    }
    test -d ${RC_DIR} &&\
    {
      succeed=1
    } || \
    {
      echo "${RC_DIR} either doesn't exist or has restictive permissions."
      succeed=0
    }
done
RC_DIR=`strip_trailing_slash ${RC_DIR}`

#PID_DIR:
succeed=0
while [[ $succeed -ne 1 ]]
do
test -d ${PID_DIR} && \
{
   chown ${PGUSER1}:${PGUSER1_GROUP} ${PID_DIR} ;
   chmod 750 ${PID_DIR} ;
   PID_F=${PID_DIR}"/"${PID_F} ;
   if [[ $? -eq 0 ]];
   then
      CREATED_DIRS="$CREATED_DIRS ${PID_DIR}"
      succeed=1
   fi
} ||\
{
   mkdir ${PID_DIR} &>/dev/null
   if [[ $? -ne 0 ]];
   then
       echo "I can not create ${PID_DIR}."
       echo -e "Specify directory where pid file will be stored: "
       read -e PID_DIR
       PID_DIR=`strip_trailing_slash ${PID_DIR}`
   fi
}
done

# SCRIPT_DIR:
succeed=0
while [[ $succeed -ne 1 ]]
do
     test -d ${PGUSER1_DIR}"/.replication_watcher" &&\
     {
	SCRIPT_DIR=${PGUSER1_DIR}"/.replication_watcher"
     } ||\
     {
        echo -e "Specify directory where you would like to store the script. Remember, it should be secure: "
        read -e SCRIPT_DIR
     }
     test -d ${SCRIPT_DIR} &&\
     {
        owner=`ls -la ${SCRIPT_DIR} | grep '\.$' | grep -v '\.\.' | awk '{print $3}'`
        if [[ "$owner" != "${PGUSER1}" ]];
        then
            echo "Incorrect owner for $SCRIPT_DIR. Must be ${PGUSER1}"
            succeed=0
        else
            correct_permissions=`ls -la ${SCRIPT_DIR} | grep '\.$' | grep -v '\.\.' | awk '{print $1}' | awk 'BEGIN{succ=0;}{if ($succ ~ "dr.x\-\-\-\-\-\-"){succ=1;}}END{print succ;}'`
            if [[ $correct_permissions -eq 0 ]];
            then
                 echo "Incorrect permissions on $SCRIPT_DIR."
                 succeed=0
            else
                 succeed=1
            fi
        fi 
     } ||\
     {
       mkdir ${SCRIPT_DIR} &>/dev/null
       if [[ $? -ne 0 ]];
       then
            echo "Can not create $SCRIPT_DIR."
            succeed=0
       else
            CREATED_DIRS="$CREATED_DIRS ${SCRIPT_DIR}"
            chown ${PGUSER1}:${PGUSER1_GROUP} $SCRIPT_DIR
            chmod go-rwx ${SCRIPT_DIR}
            succeed=1
       fi
     }
done

SCRIPT_DIR=`strip_trailing_slash ${SCRIPT_DIR}`

# untaring supplements:
succeed=0
tar -xf ${SRC_TAR} -C ${SCRIPT_DIR}
if [[ $? -eq 0 ]];
then
   succeed=1
else
   succeed=0
fi

# Finding where bash and sh executables are stored:
BASH_F=`whereis bash | awk '{print $2;}'`
SH_F=`whereis sh | awk '{print $2;}'`

# Asking for Ip-addresses:
echo -e "What is IP-address of this server ("`ifconfig | awk 'BAGIN{ips=""}{ if(match($0,"inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){ ips=ips" "substr($0,RSTART+5,RLENGTH-5);}}END{print ips;}'`"): "
read OUR_IP

echo -e "Now, specify the IP-address of ANOTHER replication server: "
read SERVER1_IP

# Asking about timeout:
echo -e "Specify timeout in seconds meaning how big will be timeout between replication checks (e.g. 10): "
read TIMEOUT

#Asking about master_address_for_www file:
succeed=0
while [[ $succeed -ne 1 ]];
do
  echo -e "Give path to file containing the ip-address of current Master server (press n if you don't need it): "
  read -e answer
  if [[ "${answer}" = "n" ]];
  then
      master_address_for_www=""
      succeed=1
  else
      answer_tmp=`strip_trailing_slash ${answer}`
      answer_tmp=`echo $answer_tmp | awk -F '/' 'BEGIN{ORS="/"}END{var2=NF-1; for(var=1;var<=var2;var++){print $var}}'`
      test -d ${answer_tmp} &&\
      {
        master_address_for_www=${answer}
        touch ${master_address_for_www}
        if [[ $? -eq 0 ]];
        then
            succeed=1
            CREATED_FILES="$CREATED_FILES ${master_address_for_www}"
        fi
        chown ${PGUSER1}:${PGUSER1_GROUP} ${master_address_for_www}
        chmod 644 ${master_address_for_www}
      } || {
        echo "${answer_tmp} is not proper directory."
      }
  fi
done


# DB_REP_USER:
succeed=0
while [[ $succeed -ne 1 ]]
do
  echo -n "What is database username for replication (press enter for 'repuser'): "
  read answer
  if [[ -z "$answer" ]];
  then
      DB_REP_USER="repuser"
      succeed=1
  elif [[ ! -z "$answer" ]];
  then
      DB_REP_USER="$answer"
      succeed=1
  else
      succeed=0
  fi
done

# DB_REP_USER_PASSWORD:
succeed=0
while [[ $succeed -ne 1 ]]
do
  echo -n "Password for ${DB_REP_USER}:"
  read -s answer
  if [[ -z "$answer" ]];
  then
      succeed=0
  elif [[ ! -z "$answer" ]];
  then
      DB_REP_USER_PASSWORD="$answer"
      succeed=1
  else
      succeed=0
  fi
done


# CHANGING SOME VALUES IN RC AND MAIN SCRIPT FILES BASED ON PROVIDED INFO:
succeed=0
mv ${SCRIPT_DIR}"/rc/replication_watcher" ${RC_DIR}"/replication_watcher" &>/dev/null && \
    {  # Changes required for rc script.
     CREATED_FILES="$CREATED_FILES ${RC_DIR}/replication_watcher" ;
     sed '1 s|\(#!\)\/.*|\1'"${SH_F}"'| ; 10 s|\(r_w_script=\).*|\1'"${SCRIPT_DIR}/replication_watcher.sh"'| ; 11 s|\(pgsql_user=\).*|\1'"${PGUSER1}"'| ; 19 s|\(pidfile=\).*|\1'"${PID_F}"'|' <${RC_DIR}"/replication_watcher" >"/tmp/replication_watcher.tmp"
     cat "/tmp/replication_watcher.tmp" >${RC_DIR}"/replication_watcher"
     rm "/tmp/replication_watcher.tmp"
     rmdir ${SCRIPT_DIR}"/rc"
    } ||\
    {
     echo "Sorry, can not move ${SCRIPT_DIR}/rc/replication_watcher to ${RC_DIR}."
    }
    chown ${PGUSER1}:${PGUSER1_GROUP} ${RC_DIR}"/replication_watcher"
    chmod 550 ${RC_DIR}"/replication_watcher"
    
     # Changes required for main script:
    sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'| ; 7 s|\(OUR_IP=\).*|\1'"$OUR_IP"'| ; 8 s|\(SERVER1_IP=\).*|\1'"$SERVER1_IP"'| ; 11 s|\(DATA_DIR=\).*|\1'"$DATA_DIR"'| ; 12 s|\(LOG_F=\).*|\1'"$LOG_F"'| ; 14 s|\(PGUSER2=\).*|\1'"$PGUSER1"'| ; 24 s|\(TIMEOUT=\).*|\1'"$TIMEOUT"'| ; 35 s|\(pid_file=\).*|\1'"${PID_F}"'| ; 38 s|\(master_addr_for_www=\).*|\1"'"${master_address_for_www}"'"| ; 41 s|\(dummy_user=\).*|\1"'"$DB_REP_USER"'"| ; 42 s|\(dummy_user_pass=\).*|\1'"'$DB_REP_USER_PASSWORD'"'|' <${SCRIPT_DIR}"/replication_watcher.sh" >"/tmp/replication_watcher.sh.tmp"
    cat "/tmp/replication_watcher.sh.tmp" >${SCRIPT_DIR}"/replication_watcher.sh"
    rm "/tmp/replication_watcher.sh.tmp"
    if [[ $? -ne 0 ]];
    then
       echo "Sorry, can not make important changes to ${SCRIPT_DIR}/replication_watcher.sh."
    fi
    
    chown ${PGUSER1}:${PGUSER1_GROUP} ${SCRIPT_DIR}"/replication_watcher.sh"
    chmod 500 ${SCRIPT_DIR}"/replication_watcher.sh"

# Asking about the role of this server. It affects recovery.conf file name:
echo ""
succeed=0
while [[ $succeed -ne 1 ]]
do
  echo -n "Is this server Master? (y/n)"
  read answer
  if [[ "$answer" = "n" ]];
  then
      MASTER_ROLE=0
      succeed=1
  elif [[ "$answer" = "y" ]];
  then
      MASTER_ROLE=1
      succeed=1
  else
      succeed=0
  fi
done

# Preparing connection string for recovery.conf:
connection_string="host=${SERVER1_IP} user=${DB_REP_USER} password=${DB_REP_USER_PASSWORD}"
  
# Changes required to recovery.conf before moving it to Data directory:
test -f ${SCRIPT_DIR}"/recovery.conf" &&
{
   sed '2 s|\(primary_conninfo = \).*|\1'"'${connection_string}'"'| ;' <${SCRIPT_DIR}"/recovery.conf" >"/tmp/recovery.conf.tmp"
   cat "/tmp/recovery.conf.tmp" >${SCRIPT_DIR}"/recovery.conf"
   rm "/tmp/recovery.conf.tmp"
   success=1
} || \
{
  echo "No recovery.conf file found in ${SCRIPT_DIR}."
  success=0
}
# unsetting sensible data.
unset DB_REP_USER
unset DB_REP_USER_PASSWORD

# Deciding how to name recovery.conf based on the server's role.
if [[ ${MASTER_ROLE} -eq 1 ]];
then
    mv ${SCRIPT_DIR}"/recovery.conf" ${DATA_DIR}"/recovery.done" &&\
    CREATED_FILES="$CREATED_FILES ${DATA_DIR}/recovery.done"
    chown ${PGUSER1}:${PGUSER1_GROUP} ${DATA_DIR}"/recovery.done"
    chmod 600 ${DATA_DIR}"/recovery.done"
else
    mv ${SCRIPT_DIR}"/recovery.conf" ${DATA_DIR}"/recovery.conf" &&\
    CREATED_FILES="$CREATED_FILES ${DATA_DIR}/recovery.conf"
    chown ${PGUSER1}:${PGUSER1_GROUP} ${DATA_DIR}"/recovery.conf"
    chmod 600 ${DATA_DIR}"/recovery.conf"
fi

# Finish. Give some info if everything has been successfull:
test ${succeed} -eq 1 &&\
{   
    echo ""
    echo "Congratulations. The replication watcher has been installed."
    echo "It will be automatically launched upon system startup. Keep very restrictive file and directory permissions for it."
    echo "You can always check if replication_watcher is working by typing: ${RC_DIR}/replication_watcher status."
    echo "Don't forget to add replication_watcher_enable=\"YES\" to /etc/rc.conf."
    echo "If you want the script to perform an automatic failover, you should create an empty file ${PGUSER1_DIR}/allow_failover"
    exit 0
} ||\
{
    echo "The replication watcher could not be installed."
    echo "Make sure you execute this script with proper permissions."
    exit 1
}
