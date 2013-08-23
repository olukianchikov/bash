#!/usr/local/bin/bash

# The following variable contains the list of mount points that are filled more than for 80%
#   separated by colon.
#   Change varialbe max in awk to the maximum value without warning.

FILLED_MP=`df -h -t ufs | awk 'BEGIN {perc=0; max=75;} { if ($5 ~ /.*%/) { perc=substr($5,0,length($5)-1); perc=perc+0; }; if ( perc >= max) { printf "%s:", $6;} }'`

NUM_FILLED_MP=`echo $FILLED_MP | awk 'BEGIN { RS=":" } END { print NR;  }'`

df -h -t ufs | awk 'BEGIN {\
                            perc=0; max=75;} { if ($5 ~ /.*%/) { perc=substr($5,0,length($5)-1); perc=perc+0; }; \
                            if ( perc >= max) { \
                                               printf "%s:\t%s\tused out of %s\n", $6, $5, $2;\
                                               } \
                          }'

for i in `jot - 1 $NUM_FILLED_MP 1`
do

  MOUNT_POINT=`echo $FILLED_MP | awk -v ind="$i" 'BEGIN { FS=":"; } END { print $ind; }'`
  if [ "$MOUNT_POINT" != "" ];
  then
     echo && echo
     echo "Usage of $MOUNT_POINT:"
     du -h -d1 $MOUNT_POINT
     echo
  fi

done
