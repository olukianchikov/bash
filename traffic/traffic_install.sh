#!/bin/bash -
# This script sets all neccessary variables for traffic.conf
# and copies all neccessary files for this script.

# ---- Functions:
function strip_trailing_slash() 
{
  echo $1 | awk '{if (substr($0, length($0),1) == "/") { print substr($0, 1, length($0)-1); } else {print $0;}}'
}

function give_os_name()
{
   echo `uname -s` || return 1
}

function give_interfaces() {
   local os=`uname -s`
   local list=""
   if [[ $os -eq "Linux" ]]; then
       list=`ifconfig | awk 'BEGIN{FS="\t";}{print $1; }' | awk 'BEGIN{FS="Link"; RS="\n\n"} {print $1;}'\
       | awk '{sm=match($1,"[a-z0-9A-Z]+"); print substr($1,RSTART,RLENGTH);}' | xargs echo`
   elif [[ $os -eq "FreeBSD" ]]; then
       list=`ifconfig -l`
   else
       list="unable_to_detect"
   fi
   echo $list
}

function check_interface() {
   local interface=$1
   local os=`uname -s`
   if [[ $os -eq "Linux" ]]; then
       ifconfig | awk '{print $1; }' | awk -F ':' '{print $1;}' | grep $interface >/dev/null &&\
       return 0
   elif [[ $os -eq "FreeBSD" ]]; then
       ifconfig -l | grep $interface >/dev/null && return 0
   else
       return 1
   fi
   return 1
}

function add_interface() {
  local config_f=$1
  local interface=$2
  echo "#  This is a configuration file for the traffic.sh" >>$config_f
  echo "#  Example of comments. This line is commented out." >>$config_f
  echo "interface=$interface" >>$config_f
  echo "" >>$config_f
}

function add_firstday() {
  local config_f=$1
  if [[ $2 -gt 31 || $2 -lt 1  ]];
  then
      echo "Error. $2 is wrong day of month."
      return 1
  fi
  
  echo "# a day of each month when all statistics should be set" >>$config_f
  echo "# to zero. New calculations and trackings start from that day." >>$config_f
  echo "firstday=$2" >>$config_f
  echo "" >>$config_f
}

function add_getfiles() {
  local config_f=$1
  if [[ ! -r $2 || -d $2 ]];
  then
     echo "Error. Can not read file $2"
     return 1
  fi
  echo "# a file with the list of resources on the Internet" >>$config_f
  echo "# to get them in order to increase download statistics" >>$config_f
  echo "getfiles=$2" >>$config_f
  echo "" >>$config_f
}

function add_outfile() {
  local config_f=$1
  if [[ ! -r $2 || -d $2 ]];
  then
     echo "Error. Can not read file $2"
     return 1
  fi
  echo "# a file for sending it out in order to increase outgoing traffic." >>$config_f
  echo "# Relative paths are relative to the path this configuration file resides in." >>$config_f
  echo "outfile=$2" >>$config_f
  echo "" >>$config_f
}

function add_logfile() {
  local config_f=$1
  if [[ $2 != "/var/log/traffic.log" ]];
  then
  test -s $2 && 
    {
     echo "File $2 is not empty."
     return 1
    }
  fi
  touch $2 2>/dev/null || return 1
  if [[ ! -w $2 || -d $2 ]];
  then
     echo "Error. Check file $2. It must be writable."
     return 1
  fi
  echo "# Log file." >>$config_f
  echo "# set to /dev/null if no logs required." >>$config_f
  echo "log_f=$2" >>$config_f
  echo "" >>$config_f

}

function add_statistics() {
  local config_f=$1
  test -s $2 && 
    {
     echo "File $2 is not empty."
     return 1
    }
  touch $2 2>/dev/null || return 1
  if [[ ! -w $2 || -d $2 ]];
  then
     echo "Error. Check file $2. It must be writable."
     return 1
  fi
  echo "# statistics - a file for tracking the values of netstat" >>$config_f
  echo "# before all counters are reset after restart" >>$config_f
  echo "" >>$config_f
  echo "statistics=$2" >>$config_f
  echo "" >>$config_f
}

function add_monthly () {
  local config_f=$1
    test -s $2 && 
    {
     echo "File $2 is not empty."
     return 1
    }
  touch $2 2>/dev/null || return 1
  if [[ ! -w $2 || -d $2 ]];
  then
     echo "Error. Check file $2. It must be writable."
     return 1
  fi
  echo "# monthly - a file for tracking the values of netstat " >>$config_f
  echo "# as of the first day of a new month" >>$config_f
  echo "monthly=$2" >>$config_f
  echo "" >>$config_f
}

function add_tmp_traffic() {
  local config_f=$1
    test -s $2 && 
    {
     echo "File $2 is not empty."
     return 1
    }
  touch $2 2>/dev/null || return 1
  if [[ ! -w $2 || -d $2 ]];
  then
     echo "Error. Check file $2. It must be writable."
     return 1
  fi
  echo "# Temporary script's file - a file for tracking the results of the script " >>$config_f
  echo "tmp=$2" >>$config_f
  echo "" >>$config_f
}

function add_get_inbound_bytes() {
  local config_f=$1
  if [[ ! -r $2 || -d $2 ]];
  then
     echo "Error. Can not read file $2."
     return 1
  fi
  echo "# path to the script that get the value of inbound bytes" >>$config_f
  echo "# through specified as a parameter interface" >>$config_f
  echo "get_inbound_bytes=$2" >>$config_f
  echo "" >>$config_f
}

function add_get_outbound_bytes() {
  local config_f=$1
  if [[ ! -r $2 || -d $2 ]];
  then
     echo "Error. Can not read file $2."
     return 1
  fi
  echo "# path to the script that get the value of outbound bytes" >>$config_f
  echo "# through specified as a parameter interface." >>$config_f
  echo "get_outbound_bytes=$2" >>$config_f
  echo "" >>$config_f  
}

function add_percentage_in {
  local config_f=$1
  local val=`echo "$2" | awk '{if (substr($0, length($0), 1)=="%") { print substr($0, 1, length($0)-1);} else { print $0; }}'`
  echo "# percentage_in - maximum allowed proportion of inbound traffic " >>$config_f
  echo "# It is percentage of inbound traffic to percentage of outgoing traffic." >>$config_f
  echo "# Example: limit_in=75%" >>$config_f
  echo "#          or" >>$config_f
  echo "#          limit_in=75" >>$config_f
  echo "percentage_in=$val" >>$config_f
  echo "" >>$config_f
}

function add_percentage_in_min {
  local config_f=$1
  local val=`echo "$2" | awk '{if (substr($0, length($0), 1)=="%") { print substr($0, 1, length($0)-1);} else { print $0; }}'`
  echo "# percentage_in_min - minimal allowed proportion of inbound traffic " >>$config_f
  echo "# The value is calculated as percentage of inbound traffic to " >>$config_f
  echo "# percentage of outgoing traffic." >>$config_f
  echo "# Set to 0 for no minimal allowed download limit" >>$config_f
  echo "percentage_in_min=$val" >>$config_f
  echo "" >>$config_f
}

function add_max_in {
  local config_f=$1
  echo "# max allowed input traffic for the system." >>$config_f
  echo "# Use 0 value if the max limit is not specified." >>$config_f
  echo "# Use K or M, or G to state the number in kilobytes or megabytes, or gigabytes." >>$config_f
  echo "# Use just number to state the number in bytes." >>$config_f
  echo "# Example: max_in=320M" >>$config_f
  echo "max_in=$2" >>$config_f
  echo "" >>$config_f
}

function add_max_out {
  local config_f=$1
  echo "# Max allowed outgoing traffic for the system." >>$config_f
  echo "# Use 0 value if the max limit is not specified." >>$config_f
  echo "# Use K or M, or G to state the number in kilobytes or megabytes, or gigabytes." >>$config_f
  echo "# Use just number to state the number in bytes." >>$config_f
  echo "# Example: max_out=320M" >>$config_f
  echo "max_out=$2" >>$config_f
  echo "" >>$config_f
}

function add_max_in_day {
  local config_f=$1
  echo "# Max allowed ingoing traffic per script execution." >>$config_f
  echo "# Use 0 value to let the script determine it." >>$config_f
  echo "# Use K,M or G to indicate kilobytes, megabytes or gigabytes" >>$config_f
  echo "# Note: be modest with this setting. If no month limit is" >>$config_f
  echo "#       specified, the script will download as many as this " >>$config_f
  echo "#       amount of data." >>$config_f
  echo "max_in_day=$2" >>$config_f
  echo "" >>$config_f
}

function add_max_out_day {
  local config_f=$1
  echo "# Max allowed outgoing traffic per script execution." >>$config_f
  echo "# Use 0 value to let the script determine it." >>$config_f
  echo "# Use K,M or G to indicate kilobytes, megabytes or gigabytes" >>$config_f
  echo "# Note: be modest with this setting. If no month limit is" >>$config_f
  echo "#       specified, the script will upload as many as this " >>$config_f
  echo "#       amount of data." >>$config_f
  echo "max_out_day=$2" >>$config_f
  echo "" >>$config_f
}

function add_download_f {
  local config_f=$1
  echo "#" >>$config_f
  echo "# This file is a script increasing incoming traffic. " >>$config_f
  echo "#" >>$config_f
  echo "download_f=$2" >>$config_f
  echo "" >>$config_f

}

function add_give_away_f {
  local config_f=$1
  echo "# " >>$config_f
  echo "# This file is a script increasing outgoing traffic." >>$config_f
  echo "# " >>$config_f
  echo "give_away_f=$2" >>$config_f
  echo "" >>$config_f

}


function clean_exit() {
  rm $LIST_FILES
}

# Trap handler
# It reads files and directories from input (use echo -e "Param1\\nParam2" | trap_handler
#                                                               without \\n it won't work).
# then it deletes files first. After deleting them it tries
# to delete directories. If they are not empty, it informs the user.
function trap_handler() {
   local del_later=""
   
   while read data
   do
   
       test -d $data && del_later="$del_later $data" ||\
            rm $data
   done
    
   local cur_d=""
   while [[ ! -z "$del_later" ]]
   do
      cur_d=`echo $del_later | awk 'END {print $NF; }'`
      rmdir $cur_d ||\
      {
        echo "Directory $cur_d will not be deleted. It has other files."
      }
      del_later=`echo $del_later | awk 'BEGIN {ORS=" ";} END{ for(i=1; i<NF; i++){ print $i; }}'`
   done
   exit $1
}
# ----- end of functions section
CONFIG_DIR=""
CONFIG_F=""
SHELL_F=""
BASH_F=""
RC_DIR=""
RC_SCRIPT="traffic"
# regarding src:
SRC_DIR=`echo $0 | awk -F '/' 'BEGIN{ ORS="/"} END { for (i=1; i<NF; i++) { print $i; }}'`"traffic_src"
GET_INBOUND_BYTES=".get_inbound_bytes"
GET_OUTBOUND_BYTES=".get_outbound_bytes"
DOWNLOAD_F=".download.sh"
GIVE_AWAY_F=".give_away.sh"
traffic_calc=$SRC_DIR"/.traffic_calculate"  # CHANGE TO ABSOLUTE PATH
TRAFFIC_F="traffic.sh"
getfiles="getfiles"
LIST_FILES=""
rm_rc=""    # Will store command for removing rc.d links if system is System V
# 

SHELL_F=`whereis -b sh | awk '{ if (match($0,"/[^ ]*bin[^ ]*sh")) { pattern=substr($0,RSTART,RLENGTH);} } END {print pattern;}'`
BASH_F=`whereis -b bash | awk '{ if (match($0,"/[^ ]*bin[^ ]*bash")) { pattern=substr($0,RSTART,RLENGTH);} } END {print pattern;}'`

#----------------------------------------------------------------------------------------------------------------------
#---------------------         START OF THE PROGRAM         -----------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------
echo "Traffic control scripts."
echo "You are about to set up parameters."
echo -n "       Continue? (y/n): "
read answer
if [[ "$answer" = "n" ]];
then
    exit 0
fi
os=`give_os_name`
echo -n "Opersting system detected as $os. Correct? (y/n) "
read answer
if [[ "$answer" = "n" ]];
then
    echo -n "Write the type of your operating system (e.g. Linux): "
    read os
fi

case "$os" in
          "Linux")   CONFIG_DIR="/usr/local/etc/traffic"
		     RC_DIR="/etc/init.d"
		     rm_rc="update-rc.d -f traffic remove >/dev/null"
          ;;
          "FreeBSD") CONFIG_DIR="/usr/local/etc/traffic"
                     RC_DIR="/usr/local/etc/rc.d"
                     rm_rc=":"
          ;;
esac

echo -n "Directory of user's startup scripts [press enter for $RC_DIR]:"
read -e answer
answer=`strip_trailing_slash $answer`
test -z $answer || RC_DIR=$answer

while [[ ! -d $RC_DIR || ! -w $RC_DIR ]];
do
   echo "... could not find proper directory for rc.d"
   echo "For example, in Linux it is /etc/init.d/ and /usr/local/etc/rc.d/ for FreeBSD"
   echo -n "Enter rc.d directory for user rc scripts (or write exit to quit): "
   read -e RC_DIR
   if [[ $RC_DIR = "exit" ]];
   then
      exit 1
   fi
   RC_DIR=`strip_trailing_slash $RC_DIR`
done

CONFIG_DIR=`strip_trailing_slash $CONFIG_DIR`
CONFIG_F=$CONFIG_DIR"/traffic.conf"
#while [[ ! `mkdir $CONFIG_DIR 2>/dev/null` ]];
while ! mkdir $CONFIG_DIR 2>/dev/null
do 
   #If CONFIG_DIR already exists
   test -e $CONFIG_F &&\
       echo " ..... Configuration file already exists in $CONFIG_DIR directory." ||\
       {
          if [[ -d $CONFIG_DIR ]];
          then
              break
          fi
       }
   echo -n "Enter directory for configuration file (or write exit to quit): "
   read -e CONFIG_DIR
   if [[ $CONFIG_DIR = "exit" ]];
   then
         exit 1
   fi
   CONFIG_DIR=`strip_trailing_slash $CONFIG_DIR`
   CONFIG_F=$CONFIG_DIR"/traffic.conf"
done


touch $CONFIG_F 2>/dev/null &&\
{
  echo "Configuration file is $CONFIG_F"
  LIST_FILES="$LIST_FILES ""$CONFIG_F" ; export LIST_FILES
} ||\
{
  echo "Unable to create configuration file."
  exit 1
}

echo -n "Interface ["`give_interfaces` "]: "
read interface
while ! check_interface $interface
do
    echo "Interface $interface not found."
    echo -n "Interface ["`give_interfaces` "]: "
    read interface
done

add_interface $CONFIG_F $interface

#             Creating program's directory   and  copying there every script file we will need:
echo -n "Directory where to store main script file: "
read -e traffic_d
traffic_d=`strip_trailing_slash $traffic_d`
while [[ ! -d $traffic_d || ! -w $traffic_d ]];
do
     if [[ ! -f $traffic_d ]];
     then
           mkdir $traffic_d 2>/dev/null && break\
           || echo "Error. Unable to create directory $traffic_d ."
     fi
     echo "Error. $traffic_d is not directory or permissions are incorrect."
     echo "Path where to store main script file (exit to quit): "
     read -e traffic_d
    if [[ $traffic_d = "exit" ]];
    then
       exit 1
    fi
    traffic_d=`strip_trailing_slash $traffic_d`
done
cp $SRC_DIR"/"$TRAFFIC_F $traffic_d"/"$TRAFFIC_F 2>/dev/null &&\
{
  TRAFFIC_F=$traffic_d"/"$TRAFFIC_F
  LIST_FILES="$LIST_FILES ""$TRAFFIC_F" ; export LIST_FILES
   sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$TRAFFIC_F >$TRAFFIC_F".tmp"
   cat $TRAFFIC_F".tmp" >$TRAFFIC_F
   rm $TRAFFIC_F".tmp"
  chmod 550 $TRAFFIC_F
} ||\
{
   echo "Unable to save in $traffic_d."
   exit 1
}

#   trap
trap "$rm_rc ; echo ; echo 'Script aborted. Deleting created files. '; clean_exit ; exit 1" 1 2 3 6 9
#

echo -n "First day of the period (when controlling should start again): "
read first_day
while ! add_firstday $CONFIG_F $first_day
do 
  echo -n "First day of the period (write exit to abort): "
  read first_day
  if [[ $first_day = "exit" ]];
  then
      exit 1
  fi
done

echo -n "Path to file that will be used to rise outbound traffic: "
read -e outfile
while ! add_outfile $CONFIG_F $outfile
do
  echo -n "Path to file that will be used to rise outbound traffic (write exit to quit): "
  read -e outfile
  if [[ $outfile = "exit" ]];
  then
      exit 1
  fi
done

cp $SRC_DIR"/"$getfiles $traffic_d"/"$getfiles 2>/dev/null &&\
{
  getfiles=$traffic_d"/"$getfiles
  LIST_FILES="$LIST_FILES ""$getfiles" ; export LIST_FILES
} ||\
{
  echo -n "File containing a list of urls for downloadable resources:"
  read -e getfiles
}
while ! add_getfiles $CONFIG_F $getfiles
do
  echo -n "File containing a list of urls for downloadable resources (write exit to abort): "
  read -e getfiles
  if [[ $getfiles = "exit" ]];
  then
      exit 1
  fi
done

#  copying .get_outbound_bytes
cp $SRC_DIR"/"$GET_OUTBOUND_BYTES $traffic_d"/"$GET_OUTBOUND_BYTES &&\
{
  GET_OUTBOUND_BYTES=$traffic_d"/"$GET_OUTBOUND_BYTES
  add_get_outbound_bytes $CONFIG_F $GET_OUTBOUND_BYTES
   sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$GET_OUTBOUND_BYTES >$GET_OUTBOUND_BYTES".tmp"
   cat $GET_OUTBOUND_BYTES".tmp" >$GET_OUTBOUND_BYTES
   rm $GET_OUTBOUND_BYTES".tmp"
  chmod 550 $GET_OUTBOUND_BYTES
  LIST_FILES="$LIST_FILES ""$GET_OUTBOUND_BYTES" ; export LIST_FILES
} ||\
{
   echo "Error. Unable to copy $GET_OUTBOUND_BYTES to $traffic_d ."
   exit 1
}

#  copying .get_inbound_bytes
cp $SRC_DIR"/"$GET_INBOUND_BYTES $traffic_d"/"$GET_INBOUND_BYTES &&\
{
  GET_INBOUND_BYTES=$traffic_d"/"$GET_INBOUND_BYTES
  add_get_inbound_bytes $CONFIG_F $GET_INBOUND_BYTES
   sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$GET_INBOUND_BYTES >$GET_INBOUND_BYTES".tmp"
   cat $GET_INBOUND_BYTES".tmp" >$GET_INBOUND_BYTES
   rm $GET_INBOUND_BYTES".tmp"
  chmod 550 $GET_INBOUND_BYTES
  LIST_FILES="$LIST_FILES ""$GET_INBOUND_BYTES" ; export LIST_FILES
} ||\
{
  echo "Error. Unable to copy $GET_OUTBOUND_BYTES to $traffic_d ."
  exit 1
}
#
# copying .download_f
cp $SRC_DIR"/"$DOWNLOAD_F $traffic_d"/"$DOWNLOAD_F &&\
{
  DOWNLOAD_F=$traffic_d"/"$DOWNLOAD_F
  add_download_f $CONFIG_F $DOWNLOAD_F
    sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$DOWNLOAD_F >$DOWNLOAD_F".tmp"
    cat $DOWNLOAD_F".tmp" >$DOWNLOAD_F
    rm $DOWNLOAD_F".tmp"
  chmod 550 $DOWNLOAD_F
  LIST_FILES="$LIST_FILES ""$DOWNLOAD_F" ; export LIST_FILES
} ||\
{
  echo "Error. Unable to copy $DOWNLOAD_F to $traffic_d ."
  exit 1
}
# copying give_away_f
cp $SRC_DIR"/"$GIVE_AWAY_F $traffic_d"/"$GIVE_AWAY_F &&\
{
  GIVE_AWAY_F=$traffic_d"/"$GIVE_AWAY_F
  add_give_away_f $CONFIG_F $GIVE_AWAY_F
    sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$GIVE_AWAY_F >$GIVE_AWAY_F".tmp"
    cat $GIVE_AWAY_F".tmp" >$GIVE_AWAY_F
    rm $GIVE_AWAY_F".tmp"
  chmod 550 $GIVE_AWAY_F
  LIST_FILES="$LIST_FILES ""$GIVE_AWAY_F" ; export LIST_FILES
} ||\
{
  echo "Error. Unable to copy $GIVE_AWAY_F to $traffic_d ."
  exit 1
}

log_f="/var/log/traffic.log"
echo -n "Log file [press enter for /var/log/traffic.log]: "
read -e answer
test -z $answer || log_f=$answer
while ! add_logfile $CONFIG_F $log_f
do
  echo -n "Log file (write exit to quit): "
  read -e log_f
  if [[ $log_f = "exit" ]];
  then
      exit 1
  fi
done
LIST_FILES="$LIST_FILES ""$log_f" ; export LIST_FILES

statistics=$traffic_d'/.traffic.stats'
while ! add_statistics $CONFIG_F $statistics
do
  echo -n "Path to file which will store netstat values when system reboots (write exit to abort): "
  read -e statistics
  if [[ $statistics = "exit" ]];
  then
      exit 1
  fi
done
LIST_FILES="$LIST_FILES ""$statistics" ; export LIST_FILES

monthly=$traffic_d'/.traffic.monthly'
while ! add_monthly $CONFIG_F $monthly
do
  echo -n "Path to file which will store netstat values of 1st day of month (write exit to abort): "
  read -e monthly
  if [[ $monthly = "exit" ]];
  then
      exit 1
  fi
done
LIST_FILES="$LIST_FILES ""$monthly" ; export LIST_FILES

tmp_f=$traffic_d'/.traffic.results'
while ! add_tmp_traffic $CONFIG_F $tmp_f
do
    echo -n "Path to file where results will be stored (write exit to abort): "
    read -e tmp_f
    if [[ $tmp_f = "exit" ]];
    then
       exit 1
    fi
done
LIST_FILES="$LIST_FILES ""$tmp_f" ; export LIST_FILES

cp $traffic_calc $traffic_d &&\
{
   traffic_calc=$traffic_d"/.traffic_calculate"
     sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$traffic_calc >$traffic_calc".tmp"
     cat $traffic_calc".tmp" >$traffic_calc
     rm $traffic_calc".tmp"
   chmod 550 $traffic_calc
   LIST_FILES="$LIST_FILES ""$traffic_calc" ; export LIST_FILES
} ||\
{
   echo "Error. Unable to copy $traffic_calc to $traffic_d ."
   exit 1
}

echo -n "MAXimum allowed inbound traffic (in percentage to outbound traffic, e.g. 80): "
read percentage_in
test -z "$percentage_in" && percentage_in="0"
add_percentage_in $CONFIG_F $percentage_in

echo -n "MINimum allowed inbound traffic (in percentage to outbound traffic, e.g. 0): "
read percentage_in_min
test -z "$percentage_in_min" && percentage_in_min="0"
add_percentage_in_min $CONFIG_F $percentage_in_min

echo -n "Monthly ABSOLUTE maximum allowed INbound traffic in bytes (use K/M/G for kilo/mega/giga bytes): "
read max_in
test -z "$max_in" && max_in="0"
add_max_in $CONFIG_F $max_in

echo -n "Monthly ABSOLUTE maximum allowed OUTbound traffic in bytes (use K/M/G for kilo/mega/giga bytes): "
read max_out
test -z "$max_out" && max_out="0"
add_max_out $CONFIG_F $max_out

echo -n "You can restrict how many bytes are allowed for INgoing traffic per day (0 if no restrictions, use K/M/G for kilo/mega/giga): "
read max_in_day
test -z "$max_in_day" && max_in_day="0"
add_max_in_day $CONFIG_F $max_in_day

echo -n "You can restrict how many bytes are allowed for OUTgoing traffic per day (0 if no restrictions): "
read max_out_day
test -z "$max_out_day" && max_out_day="0"
add_max_out_day $CONFIG_F $max_out_day


# Adding rc.d script file
if [ -f $SRC_DIR"/make_rc_"$os".sh" ];
then
     sed '1 s|\(#!\)\/.*|\1'"$BASH_F"'|' <$SRC_DIR"/make_rc_"$os".sh" >$SRC_DIR"/make_rc_"$os".sh.tmp"
     cat $SRC_DIR"/make_rc_"$os".sh.tmp" >$SRC_DIR"/make_rc_"$os".sh"
     rm $SRC_DIR"/make_rc_"$os".sh.tmp"
   command="$SRC_DIR/make_rc_"$os".sh $statistics $monthly $tmp_f $GET_INBOUND_BYTES $GET_OUTBOUND_BYTES $traffic_calc $interface $SHELL_F $RC_DIR"
   eval "$command" &&\
   echo "Startup script successfully added." ||\
   echo "Error. could not generate rc script for $os" >&2
fi

#
echo ""
echo "Use $TRAFFIC_F -c $CONFIG_F daily to control traffic."
echo "We recommend to launch it through cron at the end of every day."
echo "You can edit configuration file $CONFIG_F manually."
echo ""