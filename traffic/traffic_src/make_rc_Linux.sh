#!/bin/bash
if [ $# -lt 8 ];
then
    exit 1
fi

s_f=$1
m_f=$2
t_f=$3
g_i_b=$4
g_o_b=$5
traffic_calculate=$6
interface=$7
shell_path=$8
rc_dir=$9

shell_path="/bin/sh"
echo "#!$shell_path
### BEGIN INIT INFO
# Provides: traffic
# Required-Start:    \$all
# Required-Stop:     \$all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
### END INIT INFO

. /lib/init/vars.sh

. /lib/lsb/init-functions

do_start()
{
  cat /dev/null >$m_f
  [ -s $s_f ] || \
  {  # it is emplty
    cat $t_f >$s_f || return 1
  }
}

do_stop()
{
    $traffic_calculate -n $interface -i $g_i_b -o $g_o_b -m $m_f >$s_f
}

case \$1 in
     start)
           do_start
     ;;
     stop)
           do_stop
     ;;
     restart)
	   do_stop
     ;;
esac
:" >$rc_dir'/traffic'
chmod a+x $rc_dir'/traffic'
update-rc.d traffic defaults 99
