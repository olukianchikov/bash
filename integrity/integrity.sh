#!/usr/local/bin/bash -

CURPATH=`echo "$0" | awk -F/ 'BEGIN { OFS="/"  } { $NF = ""; print; }'`   # stores the path to directory where script lies
LOG="/var/log/monitoring/integrity.log"
FILE_TEMP="$CURPATH/.chktmp"
FILE_SOURCE="$CURPATH/.chkl"   # 
FILE_MAIL="$CURPATH/.chkm"
MAILTEXT=""
          
    # func that collects logs to send it by mail later on.
put () {
        read data
        echo "$data" >> $FILE_MAIL
}
                
                
cat /dev/null > $FILE_TEMP
cat /dev/null > $FILE_MAIL
                        
if [[ $EUID -ne 0 ]]; then
   echo "`date +\"%d-%m-%y %H:%M\"`> WARNING! Integrity check is being started by `whoami`. Terminating." | tee -a $LOG | put
   exit 1
fi
                        
while read line
do
        # Copy this line to target database
        echo "$line" >> $FILE_TEMP
                        
        # If line contains only filename
        fields=`echo $line | awk -F: '{ print NF }'`
        if [ $fields == '1' ]  ;
        then
                echo "`date +\"%d-%m-%y %H:%M\"`> New file [$line] has been added to check list. " | tee -a $LOG | put
                # replace line that has only filename with md5 sum, date and period of time
                line2="$line:`/sbin/md5 -q $line`:`date +"%d%m%y"`"
                #  - have to create safe variable for future using in sed:
                   safe_line=$(printf "%s\n" "$line" | sed 's/[][\.*^$/]/\\&/g')
                   safe_line2=$(printf "%s\n" "$line2" | sed 's/[][\.*^$/]/\\&/g')
                sed -i "-bkp" -e "s/$safe_line/$safe_line2/g" $FILE_TEMP
        else

                # Otherwise If line contains "filename:md5:modification_date:"
          if [ $fields  == '3' ] ;
          then
                FILESUM=`echo $line | awk -F: '{ print $2 }'`
                FILEN=`echo $line | awk -F: '{ print $1 }'`
                MODDATE=`echo $line | awk -F: '{ print $3 }'`
                CHECKSUM_NOW="`/sbin/md5 -q $FILEN`"
                OUT=$?      # If file can't be read, don't override checksum with emplty value
                if [ $OUT -eq 1 ];
                then
                        echo "`date +\"%d-%m-%y %H:%M\"`> Error! File [$FILEN] can't be inspected. Check its existence and your permissions."\
                         | tee -a $LOG | put
                        continue
                fi
# compare md5 sum
                if [ "$CHECKSUM_NOW" != "$FILESUM" ]  ;
                then
                        # checksum is incorrect
                        if [ "$FILESUM" != "" ] ;
                        then
                          echo "`date +\"%d-%m-%y %H:%M\"`> Warning! Content of file [$FILEN] has been modified since $MODDATE."\
                          | tee -a $LOG | put
                        fi
                        line2="$FILEN:`/sbin/md5 -q $FILEN`:`date +\"%d%m%y\"`"
                        #  - have to create safe variable for future using in sed:
                           safe_line=$(printf "%s\n" "$line" | sed 's/[][\.*^$/]/\\&/g')
                           safe_line2=$(printf "%s\n" "$line2" | sed 's/[][\.*^$/]/\\&/g')
                        sed -i "-bkp" -e "s/$safe_line/$safe_line2/g" $FILE_TEMP
                fi
          fi
        fi
done < $FILE_SOURCE
if [ -s $FILE_MAIL ] ;
then
        cat $FILE_MAIL | mail -s "WEB: Integrity" lon
fi
cat $FILE_TEMP > $FILE_SOURCE
cat /dev/null > $FILE_TEMP
cat /dev/null > $FILE_MAIL