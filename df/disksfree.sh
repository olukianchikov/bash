#!/usr/local/bin/bash

CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`
SCRIPT_NAME=".findfulldisks.sh"
TMPPATH="scripts/"
TMPFILE=".diskfree"

ERRCODE=0;
if [ ! -d "/tmp/""$TMPPATH" ];
then
  mkdir -m 550 "/tmp/""$TMPPATH"
  if [ -$? -ne 0 ];
  then
     ERRCODE=1
  fi
fi

if [ ! -f "$CURPATH""$SCRIPT_NAME" ];
then
  touch "/tmp/""$TMPPATH""$TMPFILE"
  if [ -$? -ne 0 ];
  then
     ERRCODE=1
  fi
fi

if [ $ERRCODE == 0 ];
then
  cat /dev/null > "/tmp/""$TMPPATH""$TMPFILE"
  "$CURPATH""$SCRIPT_NAME" > "/tmp/""$TMPPATH""$TMPFILE"
  if [ -s "/tmp/""$TMPPATH""$TMPFILE" ];
  then
       cat "/tmp/""$TMPPATH""$TMPFILE" | mail -s "WEB: disk space alert" lon
  fi
  cat /dev/null > "/tmp/""$TMPPATH""$TMPFILE"
else
  exit 1
fi
