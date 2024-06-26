#!/bin/sh
### initialise multiple instances
### 1: mandatory comma delimited list of relative ports or ranges
portst="$1"
forhelp="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
base="$IMAPORTBASE"

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5"
  $ECHO "       To create initial data on relevant instances."
  $ECHO "       Port base is $base"
  $EXIT 1
}

ima_say "$me : starting as $0 $@"

portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMAINITONE $taport"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
