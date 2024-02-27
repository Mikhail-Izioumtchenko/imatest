#!/bin/sh
### start multiple instances
### stop sequence of instances
### 1: mandatory comma delimited list of relative ports or ranges
### 2: optional, if wait, will wait unless the instance is at least readonly
### 3: wait timeout in seconds
### IMAPORTBASE port number base
me="$0"
forhelp="$1"
portst="$1"
dowait="$2"
timeout="${3:-300}"

. `pwd`/imavars.dot
me=`$BASENAME $0`

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5 [wait [wait_timeout_seconds]]"
  $EXIT 1
}

ima_say "$me : started as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMASTARTONE $taport"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

[ "$dowait" = 'wait' ] && {
  com="$IMACHECKMANY $portst $dowait $timeout"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' -a "$subrc" != '2' ] && rc='1'
}

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
