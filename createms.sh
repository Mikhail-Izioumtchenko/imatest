#!/bin/sh
### create multiple sandboxes
### 1: mandatory comma delimited list of relative ports or ranges
### 2: init|noinit, default init
### 3...: optional mysqldOptions list 
### port base is IMAPORTBASE
### x port base is IMAPORTMXBASE
forhelp="$1"
portst="$1"
doinit="${2:-init}"
more=''
[ "$#" -gt '2' ] && {
  shift 2
  more="$*"
}

. `pwd`/imavars.dot
me="`$BASENAME $0`"
base="$IMAPORTBASE"
baseex="$IMAPORTMXBASE"

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5 [init|noinit [mysqldOptions]...]"
  $ECHO "       Create multiple sandboxes. init is default."
  $ECHO "       Port base is $base, X port base is $baseex"
  $ECHO "If mysqldOptions are specified as right then the options in Example 1 below are used."
  $ECHO "Example 1: $0 4 noinit innodb_buffer_pool_size=16M disable_log_bin mysql_native_password=ON authentication_policy=mysql_native_password innodb_buffer_pool_dump_at_shutdown=OFF"
  $ECHO "Example 2: $0 4 init right"
  $EXIT 1
}

ima_say "$me : starting as $0 $@"

portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  portex="$(($port + $baseex))"
  com="$IMACREATEONE $taport $portex $doinit $more"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
