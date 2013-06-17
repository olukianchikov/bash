#!/usr/local/bin/bash

if [ $# -lt 8  ];
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
sh_f=$8
rc_dir=$9

echo "#!$sh_f -

# PROVIDE: traffic
# REQUIRE: LOGIN cleanvar sshd cron
# KEYWORD: nojail shutdown

. /etc/rc.subr

name=traffic

rcvar=traffic_enable

load_rc_config \${name}
: \${traffic_enable:=no}

start_cmd=\"\${name}_start\"
stop_cmd=\"\${name}_stop\"

traffic_stop()
{
  $traffic_calculate -n $interface -i $g_i_b -o $g_o_b -m $m_f >$s_f
}

traffic_start()
{
  cat /dev/null >$m_f
  [ -s $s_f ] || \
  {  # it is emplty
    cat $t_f >$s_f || return 1
  }
}

run_rc_command \"\$1\"
exit 0" >$rc_dir'/traffic'
chmod 555 $rc_dir'/traffic'
