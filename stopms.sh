#!/bin/sh
### stop multiple instances
### 1: mandatory starting relative port
###    or comma delimited list of relative ports or ranges
### 2: if 'wait', will wait for the instances to stop with a reasonable report interval, see code
### 3: timeout on wait
### IMAPORTBASE port number base
portst="$1"
forhelp="$1"
dowait="$2"
timeout="$3"

rep='5'

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5 [wait [wait_timeout_seconds]]"
  $EXIT 1
}

me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMASTOPONE $taport"
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
$EXIT "$rc"
