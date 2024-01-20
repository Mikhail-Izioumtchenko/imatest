#!/bin/sh
### kill all instances

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $*"

portlist=`$IMASHOWALL | $AWK '{print \$12}' | $SED "s|$SANDBOXDIR/||" | $SED 's|/.*||'`
ima_say "$me : will stop instances running on ports $portlist"

rc='0'

for port in $portlist ; do
  com="$IMAKILLONE $port"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
