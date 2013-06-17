#!/bin/bash -

#
#       Script to control traffic flow
#
# fetch -o /dev/null 
# http://images.fanpop.com/images/image_uploads/JAPAN-LANDSCAPE-japan-419407_1920_1440.jpg
# 
# /usr/bin/netstat -i -b -n -I $INTERFACE

function cute_date() {
  local cutedate=`date +'%d.%m.%y %H:%M:%S '`
  echo "$cutedate"
}


function show_help() {
echo "usage: traffic.sh [-c config_path]"
echo "       traffic.sh [-g]"
echo "       traffic.sh [-h]"
}

# This function if used to save scripts's results into 
# tmp file. It will be a backup file for statistics_f if
# something goes wrong.
function save_tmp() {
   echo "INTERFACE:$1" &&\
   echo "IN:$2" &&\
   echo "OUT:$3" &&\
   exit 0
}


# function that returns reasonable amount of data
# according to maximum allowed and current 
# downloaded or uploaded data
#    input: 1 - intended,   2 - current, 
#           3 - maximum,  4 - days remaining.
#    out:   number of bytes  or  exit 1.
function limit_if_too_much() {
  local intended=$1
  local current=$2
  local maximum=$3
  local remaining=$4
  local allowed_today=$intended
  
  # Since the current day is almost over, we have to exclude it:
    remaining=` expr $remaining - 1 `
  if [ $maximum -ne 0 ];
  then  #If monthly maximum is set, tailor allowed_today value:
       allowed_today=`echo "scale=2; ($maximum - $current) / $remaining" | bc`
  fi   
  
  # If monthly maximum is NOT set, intended is left as it is.  
  if [ `echo "$intended > $allowed_today" | bc` -ne 0 ];
  then
       intended=$allowed_today
  fi
  echo $intended
}

# function that returns how many days left in this period
# (including this current day but excluding the day of the
# new month).
# E.g. until the next new month.
#    input:  1 - number of days in month
#            2 - new_month_day from config
function days_remaining() {
  local days_in_month=$1
  local new_month_day=$2
  
  local today=`date +%0d`
  local remaining=0
  
  if [[ $today -gt $new_month_day ]];
  then
     remaining=`echo "($days_in_month - $today) + $new_month_day" | bc`
  elif [[ $today -eq $new_month_day ]];
  then
     remaining=0
  elif [[ $today -lt $new_month_day ]];
  then
     remaining=`echo "$new_month_day - $today" | bc`
  fi
  
  echo $remaining
}

# function to determine how many days in current month.
function days_in_month() {
  local month=`date +%m`
  local year=`date +%y`
  echo `cal $month $year | xargs echo | awk '{print $NF;}'`
}

# gets the number of bytes for inbound traffic from the statistics file
#    input: 1 - interface, 2 - statistics file.
#    out:   number of bytes  or  exit 1.
function get_saved_ibytes() {
local interface="$1"
local statistics_f="$2"
local saved_bytes=""
saved_bytes=`cat "$statistics_f" | awk -F":" 'BEGIN {ibytes=1; ifc="'$interface'"}\
{ ibytes=1; \
                      while(ibytes<=NF) {\
                          if ($ibytes == "IN") {\
                           ibytes++; print $ibytes; exit;\
                          }\
                          ibytes++;\
                       }\
}'`

  if [[ ! -n "$saved_bytes" ]];
  then
      exit 1
  else
      echo $saved_bytes
  fi
}

# gets the number of bytes for outbound traffic from the statistics file
#     input: 1 - interface, 2 - statistics file.
#     out:   number of bytes  or  exit 1.
function get_saved_obytes() {
local interface="$1"
local statistics_f="$2"
local saved_bytes=""
saved_bytes=`cat "$statistics_f" | awk -F":" 'BEGIN {obytes=1; ifc="'$interface'"}\
{ obytes=1; \
                      while(obytes<=NF) {\
                          if ($obytes == "OUT") {\
                           obytes++; print $obytes; exit;\
                          }\
                          obytes++;\
                       }\
}'`
  if [[ ! -n "$saved_bytes" ]];
  then
      exit 1
  else
      echo $saved_bytes
  fi
}

# gets the number of bytes for inbound traffic from the monthly file
#   input: 1 - interface, 2 - monthly file
#   out:   number of bytes from monthly file or exit 1
function get_monthly_ibytes() {
local interface="$1"
local monthly_f="$2"
local monthly_bytes=""
monthly_bytes=`cat "$monthly_f" | awk -F ':' '{if($1=="IN"){print $2;}}'`
  if [[ ! -n "$monthly_bytes" ]];
  then
      exit 1
  else
      echo $monthly_bytes
  fi
}

# gets the number of bytes for outbound traffic from the monthly file
#   input: 1 - interface, 2 - monthly file
#   out:   number of bytes from monthly file or exit 1
function get_monthly_obytes() {
local interface="$1"
local monthly_f="$2"
local monthly_bytes=""
monthly_bytes=`cat "$monthly_f" | awk -F ':' '{if($1=="OUT"){print $2;}}'`
  if [[ ! -n "$monthly_bytes" ]];
  then
      exit 1
  else
      echo $monthly_bytes
  fi
}


#
#   -------------- MAIN PART:   ------------------------------------------
#
while getopts c:hgz option
do
       case "${option}"
       in
               c) CONFIG_F="${OPTARG}"
               ;;
               h) show_help && exit
               ;;
               # z - clear monthly and statistics files
               z) ZERO=1 && \
               exit ;;
               *) show_help &&\
               exit
               ;;
       esac
done

# Declaring config variables
INTERFACE=""
GET_FILES_F=""
STATISTICS_F=""
PERC_IN=""
MAX_IN=0
MAX_OUT=0
OUT_F=""
FIRST_DAY=0
MONTHLY_F=""
TMP_F=""
LOG_F=""
MAX_IN_DAY=0
MAX_OUT_DAY=0

# Declaring script's variables
IN_RES=0   # -- resulting inbound traffic as of the time this script is being executed
OUT_RES=0  # -- resulting outbound traffic as of the time this script is being executed
PERC_CUR=0           # -- current proportion of input/output.
TRAFFIC_PER_PERC=0   # -- how much traffic is one percent.

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
	"interface") INTERFACE=$parameter_val;;
	"getfiles") GET_FILES_F=$parameter_val
		    if [ ! -f "$GET_FILES_F" ];
		    then
		      echo "Error: Can not read file $GET_FILES_F ." >&2
		      exit 1
		    fi
		    ;;
	"statistics") STATISTICS_F=$parameter_val
		    if [ ! -f "$STATISTICS_F" ];
		    then
		      echo "Error: file $STATISTICS_F not found." >&2
		      exit 1
		    fi
	            ;;
	"percentage_in") PERC_IN=`echo $parameter_val | sed "s/%//"`;;
	"percentage_in_min") PERC_IN_MIN=`echo $parameter_val | sed "s/%//"`
		    if [[ $PERC_IN_MIN -gt $PERC_IN ]];
		    then
		      echo "Error: percentage_in_min is greater than percentage_in." >&2
		      exit 1
		    fi
		    ;;
	"max_in") MAX_IN=`echo $parameter_val | awk 'BEGIN{var=0;}\
	        {\
	          var=substr($0,0,length($0));\
	          if ($0 ~ /.*[mM]/) {\
	                 var=var*1024*1024;\
	          } else if ($0 ~ /.*[kK]/) {\
	                 var=var*1024;\
	          } else if ($0 ~ /.*[gG]/) {\
			  var=var*1024*1024*1024;\
	          } else if ($0 ~ /[0-9]*/) {\
		          var=$0;\
	          }\
	         } END {print var;}'`;;
	"max_out") MAX_OUT=`echo $parameter_val | awk 'BEGIN{var=0;}\
	        {\
	          var=substr($0,0,length($0));\
	          if ($0 ~ /.*[mM]/) {\
	                 var=var*1024*1024;\
	          } else if ($0 ~ /.*[kK]/) {\
	                 var=var*1024;\
	          } else if ($0 ~ /.*[gG]/) {\
			  var=var*1024*1024*1024;\
	          } else if ($0 ~ /[0-9]*/) {\
		          var=$0;\
	          }\
	         } END {print var;}'`;;
	"outfile") OUT_F=$parameter_val
		    if [ ! -f "$OUT_F" ];
		    then
		      echo "Error: file $OUT_F not found." >&2
		      exit 1
		    fi
		    ;;
	"monthly")  MONTHLY_F=$parameter_val
		    if [ ! -f "$MONTHLY_F" ];
		    then
		      echo "Error: file $MONTHLY_F not found." >&2
		      exit 1
		    fi
		    ;;
	"tmp")      TMP_F=$parameter_val
	            if [ ! -f "$TMP_F" ];
		    then
		      echo "Error: file $TMP_F not found." >&2
		      exit 1
		    fi
		    ;;
	"firstday") FIRST_DAY=$parameter_val;;
	"get_inbound_bytes") GET_INBOUND_BYTES="$parameter_val";;
	"get_outbound_bytes") GET_OUTBOUND_BYTES="$parameter_val";;
	"download_f") DOWNLOAD_F="$parameter_val" 
		      if [ ! -f "$DOWNLOAD_F" ];
		      then
		        echo "Error: file $DOWNLOAD_F not found." >&2
			exit 1
		      elif [ ! -x "$DOWNLOAD_F" ];
		      then
		        echo "Error: file $DOWNLOAD_F not executable." >&2
			exit 1
		      fi
	;;
	"give_away_f") GIVE_AWAY_F="$parameter_val" 
		      if [ ! -f "$GIVE_AWAY_F" ];
		      then
		        echo "Error: file $GIVE_AWAY_F not found." >&2
			exit 1
		      elif [ ! -x "$GIVE_AWAY_F" ];
		      then
		        echo "Error: file $GIVE_AWAY_F not executable." >&2
			exit 1
		      fi
	;;
	"log_f") LOG_F="$parameter_val"
		 if [ ! -e "$LOG_F" ];
		    then
		      echo "Error: file $LOG_F not found." >&2
		      exit 1
		 fi
		 ;;
	"max_in_day") MAX_IN_DAY=`echo $parameter_val | awk 'BEGIN{var=0;}\
	        {\
	          var=substr($0,0,length($0));\
	          if ($0 ~ /.*[mM]/) {\
	                 var=var*1024*1024;\
	          } else if ($0 ~ /.*[kK]/) {\
	                 var=var*1024;\
	          } else if ($0 ~ /.*[gG]/) {\
			  var=var*1024*1024*1024;\
	          } else if ($0 ~ /[0-9]*/) {\
		          var=$0;\
	          }\
	         } END {print var;}'`;;
	"max_out_day") MAX_OUT_DAY=`echo $parameter_val | awk 'BEGIN{var=0;}\
	        {\
	          var=substr($0,0,length($0));\
	          if ($0 ~ /.*[mM]/) {\
	                 var=var*1024*1024;\
	          } else if ($0 ~ /.*[kK]/) {\
	                 var=var*1024;\
	          } else if ($0 ~ /.*[gG]/) {\
			  var=var*1024*1024*1024;\
	          } else if ($0 ~ /[0-9]*/) {\
		          var=$0;\
	          }\
	         } END {print var;}'`;;
     esac
done <"${CONFIG_F:?'Configuration file not set. Aborting.'}"

#   Saying hello
echo `cute_date`"Traffic control is starting." >>$LOG_F


#echo "            interface: $INTERFACE"
#echo "            getfiles: $GET_FILES_F"
#echo "            statistics: $STATISTICS_F"
#echo "            percentage_in: $PERC_IN"
#echo "            monthly: $MONTHLY_F"
#echo "            firstday: $FIRST_DAY"
#echo "        .........................     "

# Let's check INTERFACE exists
ifconfig | awk '{print $1;}' | grep "$INTERFACE" >/dev/null ||\
{
   echo `cute_date`" ERROR. Interface $INTERFACE does not exist." >>$LOG_F
   exit 3
}

# If the script were invoked with -z option, clear the monthly and stat files:
if [[ ! -z "$ZERO" ]];
then
  error=0
  cat /dev/null >"$STATISTICS_F" &&\
  cat /dev/null >"$MONTHLY_F" &&\
  {
    echo `cute_date`" All saved statistics reset." >>$LOG_F
    exit 0
  } ||\
  {
    echo `cute_date`" ERROR. Statistics file and monthly file can not be deleted." >>$LOG_F
    exit 8
  }
fi


# If it is the first day of the month:
CUR_DATE=`date +%-d`

if [[ $CUR_DATE -eq $FIRST_DAY ]];
then
    cat /dev/null >"$STATISTICS_F"
    INBOUND=`$GET_INBOUND_BYTES $INTERFACE`
    if [ $? != "0" ];
    then
	echo `cute_date`"ERROR. Unable to parse netstat statistics." >>$LOG_F
	exit 1
    fi
    OUTBOUND=`$GET_OUTBOUND_BYTES $INTERFACE`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Unable to parse netstat statistics." >>$LOG_F
	exit 1
    fi
    echo "`date +%d.%m.%y`" >"$MONTHLY_F" &&\
    echo "INTERFACE:$INTERFACE" >>"$MONTHLY_F" &&\
    echo "IN:$INBOUND" >>"$MONTHLY_F" &&\
    echo "OUT:$OUTBOUND" >>"$MONTHLY_F" &&\
    echo `cute_date`" Traffic control for new period begins." >>$LOG_F &&\
    exit 0
    
fi
# ----

# If traffic.stat is set:
if [ -s "$STATISTICS_F" ];
then
    # clear monthly file as we don't need it. 
    # Presence of traffic.stat meant computer restarted 
    # and all accountings were cleared.
    if [ -s "$MONTHLY_F" ];
    then
         cat /dev/null >"$MONTHLY_F"
    fi
    # we should use the value of STATISTICS_F to append to netstat result
    INBOUND=`$GET_INBOUND_BYTES $INTERFACE`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Unable to parse netstat statistics." >>$LOG_F
	exit 1
    fi
    OUTBOUND=`$GET_OUTBOUND_BYTES $INTERFACE`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Unable to parse netstat statistics." >>$LOG_F
	exit 1
    fi
    INBOUND_S=`get_saved_ibytes $INTERFACE "$STATISTICS_F"`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Unable to get statistics from statistics file." >>$LOG_F
	exit 1
    fi
    OUTBOUND_S=`get_saved_obytes $INTERFACE "$STATISTICS_F"`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Unable to get statistics from statistics file.">>$LOG_F
	exit 1
    fi
    IN_RES=` echo "$INBOUND_S + $INBOUND" | bc`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Calculations failed for incoming traffic result." >>$LOG_F
	exit 1
    fi
    OUT_RES=` echo "$OUTBOUND_S + $OUTBOUND" | bc`
    if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Calculations failed for outgoung traffic result." >>$LOG_F
	exit 1
    fi
    # DELETE IT AFTER TESTIng :
    echo `very_cute_date`"We detected that system has been rebooted." >>$LOG_F
    
fi
# ---

#if monthly is set:
if [ -s "$MONTHLY_F" ];
then
   if [ -s "$STATISTICS_F" ];
    then
         echo `cute_date`"ERROR. The script failed. Both monthly file and statistics file can not be set." >>$LOG_F
         exit 3
    fi
   # we should use the value of MONTHLY_F to subtract from netstat result
   INBOUND=`$GET_INBOUND_BYTES $INTERFACE`
   if [ "$?" != "0" ];
   then
	echo `cute_date`"ERROR. Unable to get statistics from netstat." >>$LOG_F
	exit 1
   fi
   OUTBOUND=`$GET_OUTBOUND_BYTES $INTERFACE`
   if [ "$?" != "0" ];
   then
	echo `cute_date`"ERROR. Unable to get statistics from netstat." >>$LOG_F
	exit 1
   fi
   INBOUND_M=`get_monthly_ibytes $INTERFACE "$MONTHLY_F"`
   if [ "$?" != "0" ];
   then
	echo `cute_date`"ERROR. Unable to get statistics from monthly file." >>$LOG_F
	exit 1
   fi
   OUTBOUND_M=`get_monthly_obytes $INTERFACE "$MONTHLY_F"`
   if [ "$?" != "0" ];
    then
	echo `cute_date`"ERROR. Unable to get statistics from monthly file." >>$LOG_F
	exit 1
   fi
   IN_RES=` echo "$INBOUND - $INBOUND_M" | bc`
   OUT_RES=` echo "$OUTBOUND - $OUTBOUND_M" | bc`
fi
# ---

# If we calculated traffic, it's time to get a proportion and do things
if [ $IN_RES != 0 ];
then
  #echo "Inbound bytes: "$IN_RES
  #echo "       kbytes: "`echo "scale=2; $IN_RES / 1024" | bc`
  #echo "       mbytes: "`echo "scale=2; $IN_RES / 1024 / 1024" | bc`
  #echo "Outbound bytes: "$OUT_RES
  #echo "        kbytes: "`echo "scale=2; $OUT_RES / 1024 " | bc`
  #echo "        mbytes: "`echo "scale=2; $OUT_RES / 1024 / 1024" | bc`
  
  PERC_CUR=` echo "scale=0; ($IN_RES*100)/$OUT_RES" | bc`
  echo `cute_date`"Current proportion: "$PERC_CUR"%" >>$LOG_F
  
  TRAFFIC_PER_PERC=`echo "scale=2; $OUT_RES / 100" | bc`
  #echo `cute_date`"One percent of outgoing traffic is $TRAFFIC_PER_PERC bytes." >>$LOG_F
  
  days=`days_in_month`
  days_left=`days_remaining $days $FIRST_DAY`
  if [ $PERC_CUR -gt $PERC_IN ]; 
  then  
##  ================>     We have more inbound traffic than we should.  <================================
    # REMOVE AFTER TESTINg:
    echo `cute_date`"current is greater" >>$LOG_F
      
    if [ "$MAX_OUT" -ne 0 ]; 
    then  # there is max limit for month outbound traffic
       if [[ "$MAX_OUT_DAY" -eq 0 ]]; 
       then    # But no limit for traffic per day
           MAX_OUT_DAY=`echo "scale=2; $MAX_OUT / $days" | bc` # how much is allowed for a day by default
       fi       
    else
       # there is no limit for monthly inbound traffic (equal to 0)
       if [[ `echo "$MAX_OUT_DAY == 0" | bc` -ne 0 ]]; 
       then  # and no limit for daily IN traffic:
            MAX_OUT_DAY=134217728   # 128 Mb  -- let it be a hardcoded limit
       fi 
    fi
    MAX_OUT_DAY=`limit_if_too_much $MAX_OUT_DAY $OUT_RES $MAX_OUT $days_left` # our value to upload
    # How much do we actually need:
    difference=`echo "scale=1; $PERC_CUR - $PERC_IN" | bc`
    difference=`echo "scale=0; $difference * $TRAFFIC_PER_PERC" | bc`
    if [[ `echo "$difference > $MAX_OUT_DAY" | bc` -ne 0 ]]; 
    then 
	difference=$MAX_OUT_DAY
    fi
    # ___ giving away ____
  
    nohup $GIVE_AWAY_F $INTERFACE $OUT_F $difference >>$LOG_F 2>>$LOG_F </dev/null &
    
    # ____________________
    # REMOVE AFTER TESTing: 
    echo `cute_date`" We have got to upload $difference bytes." >>$LOG_F
    echo `cute_date`" days left: $days_left" >>$LOG_F
    echo `cute_date`" Max out bytes: $MAX_OUT" >>$LOG_F
    echo `cute_date`" We uploaded already: $OUT_RES bytes" >>$LOG_F
  elif [ $PERC_CUR -lt $PERC_IN ]; 
  then
#   =============>    We have less inbound traffic than the maximum from config  <===========================
      if [ $PERC_CUR -lt $PERC_IN_MIN ]; 
      then   # And we have even less inbound traffic than minimal set percentage of from config
	## Outgoing traffic is just huge
	## So we need to Download
	echo `cute_date`"current is less" >>$LOG_F
    
	if [ "$MAX_IN" -ne 0 ]; then
	  # there is max limit for month inbound traffic
	   if [ "$MAX_IN_DAY" -eq 0 ];
	   then
	     MAX_IN_DAY=`echo "scale=2; $MAX_IN / $days" | bc`
	   fi
	else # there is no limit for inbound traffic
	    if [ `echo "$MAX_IN_DAY == 0" | bc` -ne 0 ]; then
	       MAX_IN_DAY=134217728   # 128 Mb
	    fi 
        fi
        MAX_IN_DAY=`limit_if_too_much $MAX_IN_DAY $IN_RES $MAX_IN $days_left` # our value to download
        # How much do we actually need:
	difference=`echo "scale=1; $PERC_IN_MIN - $PERC_CUR" | bc`
	difference=`echo "scale=0; $difference * $TRAFFIC_PER_PERC" | bc`
	if [[ `echo "$difference > $MAX_IN_DAY" | bc` -ne 0 ]]; 
	then 
	      difference=$MAX_IN_DAY
	fi
        # ___ downloading ____________________
        nohup $DOWNLOAD_F $INTERFACE $GET_FILES_F $difference >>$LOG_F 2>>$LOG_F </dev/null &
        # ____________________________________
        # REMOVE AFTER TESTing: 
            echo `cute_date`" We have got to download $difference bytes." >>$LOG_F
	    echo `cute_date`" days left: $days_left" >>$LOG_F
	    echo `cute_date`" Max in bytes: $MAX_IN" >>$LOG_F
	    echo `cute_date`" We downloaded already: $IN_RES bytes" >>$LOG_F
      fi
  fi
#   ============================================================================================================
  # Saving input and output statistics to file.
  # That file will be used only if STATISTICS_F wasn't properly saved.
  # Problem is that this values are valid only before any downloading / uploading.
  save_tmp $INTERFACE $IN_RES $OUT_RES >$TMP_F
  
else
  # The script runs for the first time
  cat /dev/null >"$STATISTICS_F"
  INBOUND=`$GET_INBOUND_BYTES $INTERFACE`
  if [ "$?" != "0" ];
  then
	echo `cute_date`"ERROR. Unable to parse netstat statistics." >>$LOG_F
	exit 1
  fi
  OUTBOUND=`$GET_OUTBOUND_BYTES $INTERFACE`
  if [ "$?" != "0" ];
  then
    echo `cute_date`"ERROR. Unable to parse netstat statistics." >>$LOG_F
    exit 1
  fi
  echo "`date +%d.%m.%y`" >"$MONTHLY_F" &&\
  echo "INTERFACE:$INTERFACE" >>"$MONTHLY_F" &&\
  echo "IN:$INBOUND" >>"$MONTHLY_F" &&\
  echo "OUT:$OUTBOUND" >>"$MONTHLY_F" &&\
  echo `cute_date`" Traffic control now begins." >>$LOG_F &&\
  exit 0 ||\
  {
    echo `cute_date`"ERROR. Unable to save neccessary statisitcs. Check monthly setting." >>$LOG_F
    exit 9
   }
fi
exit 0
#---