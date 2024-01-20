#!/bin/sh
### show instance
### $1 is absolute port number
port="${1:-findme}"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

found=`$PS -ef | $GREP "$MYSQLD" | $GREP -v "$GREP" | $GREP "/$port/"`
ima_say "$me : $found"

ima_say "$me : exiting with exit code 0"
$EXIT 0
