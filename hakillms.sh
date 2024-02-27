#!/bin/sh
### send signal to multiple instances
### 1: mandatory delimited list of relative ports or ranges
### 2: mandatory signal name or number
### 3: if 'wait', will wait for the instances to disappear with a reasonable report interval, see code
### 4: timeout on wait
### IMAPORTBASE port number base
forhelp="$1"
portst="$1"
sig="${2:-findme}"
dowait="$3"
timeout="$4"

rep='5'

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5 signal_as_KILL_or_9 [wait [wait_timeout_seconds]]"
  $EXIT 1
}

me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMAHAKILLONE $taport $sig"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

[ "$dowait" = "wait" ] && {
  com="$IMAWAITMANY $portst $rep $timeout"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
}

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
