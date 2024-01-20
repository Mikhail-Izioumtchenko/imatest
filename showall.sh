#!/bin/sh
### show all instances
portst="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

$PS -ef | $GREP "$MYSQLD" | $GREP -v "$GREP" | ima_report "$me"

ima_say "$me : exiting with exit code 0"
$EXIT 0
