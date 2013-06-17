#!/bin/bash
# Gets three arguments:
# 1 - interface name
# 2 - file to give away
# 3 - number of bytes to give away
#  It will calculate how many attempts it should use
function cute_date() {
  local cutedate=`date +'%d.%m.%y %H:%M:%S  '`
  echo "$cutedate"
}

  INTERFACE=$1
  GIVE_AWAY_F=$2
  BYTES=$3
  
  #we want to check the file
  test -f $GIVE_AWAY_F -a -r $GIVE_AWAY_F || \
  {
   echo "Error $GIVE_AWAY_F is not a file or it has wrong permissions. "
   exit 1
  }
  
  # We find how many attempts we need to do. We do it by 
  #                       dividing BYTES on give_away_s.
  give_away_size=`ls -l $GIVE_AWAY_F | awk '{ if ($5 ~ /[0-9]+/){print $5;}}'`  
  ATTEMPTS=`echo "scale=0; $BYTES / $give_away_size" | bc`
  
  if [[ $ATTEMPTS -gt 999 ]];
  then
      ATTEMPTS=999
  fi
  
  ip_addr=`ifconfig $interface | grep 'inet' | awk '{if(match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){print substr($0,RSTART,RLENGTH); exit;}}'`

  first_ip=`host yandex.ru | awk '{if (match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){ print substr($0,RSTART,RLENGTH); exit;}}'`
  second_ip=`host lenta.ru | awk '{if (match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){ print substr($0,RSTART,RLENGTH); exit;}}'`
  third_ip=`host www.drive.ru | awk '{if (match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){ print substr($0,RSTART,RLENGTH); exit;}}'`
  fourth_ip=`host auto.mail.ru | awk '{if (match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){ print substr($0,RSTART,RLENGTH); exit;}}'`
  fifth_ip=`host www.1cbit.ru | awk '{if (match($0, "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")){ print substr($0,RSTART,RLENGTH); exit;}}'`
  
  i=0
  errors=0
  while [[ $i -lt $ATTEMPTS ]];
  do
    rand=$RANDOM
    rand_remainder=` expr $RANDOM % 5 `
    port=` expr $rand % 10000 + 32768 `
    
    case $rand_remainder in
      1 ) serv="$first_ip" ;;
      2 ) serv="$second_ip" ;;
      3 ) serv="$third_ip" ;;
      4 ) serv="$fourth_ip" ;;
      0 ) serv="$fifth_ip" ;;
    esac
    
    ( cat $GIVE_AWAY_F ) | nc -u -n -w 0 -s $ip_addr -p $port $serv $port &&\
    {
      i=` expr $i + 1 `
      #sleep 1
    } || \
    {
       errors=` expr $errors + 1 `
       if [[ $errors -gt 10 ]];
       then
         break  # something is really wrong
       fi
       sleep 4
    }
  done
  echo `cute_date``echo "scale=0; $give_away_size * $i " | bc`" bytes have been uploaded."
  exit 0

