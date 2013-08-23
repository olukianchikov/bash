#!/usr/local/bin/bash -
# This script checks if somebody was logged in our system within $INTERVAL minutes time from now. If so, send a warning email.
# You can specify up to three users that will be an exception for the check. If you need to specify less than three, write some fake
# names.
# Important: make sure the ${INTERVAL} variable is set to the amount of minutes between script's runs if it is used by cron.

CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`   # stores the path to directory where script resides
LOG="/var/log/monitoring/auth.log"
INTERVAL=5   # Amount of minutes between script invocations. It's required to /var/log/auth.log lookup.
FILE_MAIL="$CURPATH/.mail"

# Function that puts all the messages to $FILE_MAIL file
put () {
        read data
        if [ `echo $data | grep -E -o -i -c "[a-z]"` -gt 0 ]
        then
         echo "$data" >> $FILE_MAIL
        fi
}

USER1="lon"       #  that's the user who will skip the check if logged in from 9.45 to 19 o'clock (total<585 || total>1140)
USER2="alexander" #  that's the user who will skip the check if logged in from 9.45 to 19 o'clock (total<585 || total>1140)  - like the USER1
USER3="backup"    #  That's the user who will skip the check if logged in from 21 to 8 o'clock. It might be backup user.


if [[ $EUID -ne 0 ]]; then
   echo "`date +\"%d-%m-%y %H:%M\"`> WARNING! Aithentication check is being started by `whoami`. Terminating." | tee -a $LOG | put
   exit 1
fi

# Defining current time:
CURDAY=`date +"%d"`
CURMONTH=`date +"%m"`
CURHOUR=`date +"%H"`
CURMIN=`date +"%M"`

case $CURMONTH in
        1) LOGMONTH="Jan" ;;
        2) LOGMONTH="Feb" ;;
        3) LOGMONTH="Mar" ;;
        4) LOGMONTH="Apr" ;;
        5) LOGMONTH="May" ;;
        6) LOGMONTH="Jun" ;;
        7) LOGMONTH="Jul" ;;
        8) LOGMONTH="Aug" ;;
        9) LOGMONTH="Sep" ;;
        10) LOGMONTH="Oct" ;;
        11) LOGMONTH="Nov" ;;
        12) LOGMONTH="Dec" ;;
esac

STARTTIME=`date -v-"$INTERVAL"M +%H:%M | awk -F: '{ result=$2+(60*$1); print result }'`  # summa of minutes from start of the current day to (current time - interval)

# ---- it will print all accepted connections since last check (current_time - interval) for any user.
#      And lon's and alexander's connections are exempted from this check during work time.
tail -n 100 /var/log/auth.log | awk '{ print $0 }' | grep "$LOGMONTH" | awk \
                                                                       '{ if ($2 == '$CURDAY') \
                                                                          { \
                                                                             \
                                                                            min=substr($3,4,2); \
                                                                            hours=substr($3,1,2);\
                                                                            total=min+(60*hours);\
                                                                            if (total > '$STARTTIME')\
                                                                              { print $0 } \
                                                                          } \
                                                                        }' | awk \
                                                                        '{ \
                                                                           for(i=1;i<=NF;i++) \
                                                                           { \
                                                                            if (index($i, "Accept") > 0) { \
                                                                              if (   (index($0, "'${USER1}'") > 0) || (index($0, "'${USER2}'") > 0) )\
                                                                                { \
                                                                                 min=substr($3,4,2); \
                                                                                 hours=substr($3,1,2); \
                                                                                 total=min+(60*hours); \
                                                                                 if ((total<585) || (total>1140))\
                                                                                   { print $0 } \
                                                                                } \
                                                                               else if (index($0, "'${USER3}'") > 0) \
                                                                                { \
                                                                                 min=substr($3,4,2); \
                                                                                 hours=substr($3,1,2); \
                                                                                 total=min+(60*hours); \
                                                                                 if ((total>480) && (total<1260))\
                                                                                   { print $0 } \
                                                                                }\
                                                                              else print $0; \
                                                                            } \
                                                                           } \
                                                                         }' | tee -a $LOG | put

# ---
# Send an email message if we've got anything:
if [[ -s $FILE_MAIL ]]; 
then
        cat $FILE_MAIL | mail -s "WEB: Auth" lon &&\
        cat /dev/null > $FILE_MAIL
fi