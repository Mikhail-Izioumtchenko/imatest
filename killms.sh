#!/bin/sh
### kill multiple instances
### 1: mandatory comma delimited list of relative ports or ranges
### 2: if 'wait', will wait for the instances to stop with a reasonable report interval, see code
### 3: timeout on wait
### IMAPORTBASE port number base
portst="$1"
dowait="$2"
timeout="$3"

rep='5'

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMAKILLONE $taport"
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
