#!/bin/sh
### wait for all instances
### 1: optional report interval, default 0 means do not report
### 2: optional approximate timeout in seconds, default fairly large, see code;
###    this is per instance as opposed to cumulative
### 3: optional sleep time between checking, suitable to passing to sleep, defaulr fairly small, see code
### exit 0: no instance or it is over
### exit 1: timeout
rep="$1"
tout="$2"
slep="$3"

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $*"

portlist=`$IMASHOWALL | $AWK '{print \$12}' | $SED "s|$SANDBOXDIR/||" | $SED 's|/.*||'`
ima_say "$me : will wait for instances running on ports ' $portlist '"

rc='0'
for port in $portlist ; do
  com="$IMAWAITONE $port $rep $tout $slep"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
