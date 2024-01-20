#!/bin/sh
### send signal to all instances
### 1: signal name or number
### 2: if 'wait', will wait for the instances to stop with a reasonable report interval, see code
sig="${1:-findme}"
dowait="$3"

rep='5'

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $@"

portlist=`$IMASHOWALL | $AWK '{print \$12}' | $SED "s|$SANDBOXDIR/||" | $SED 's|/.*||'`
ima_say "$me : found instances on ports ' $portlist '"

rc='0'
for port in $portlist ; do
  com="$IMAHAKILLONE $port $sig"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

[ "$dowait" = "wait" ] && $IMAWAITALL "$rep"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
