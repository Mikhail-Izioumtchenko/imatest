#!/bin/sh
### shutdown one instance
### 1: mandatory absolute standard protocol port
### 2: if 'wait', will wait for the instances to stop with a reasonable report interval, see code
port="$1"
dowait="$2"

rep='5'

. `pwd`/imavars.dot

me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

pass=`$CAT "$IMAPAS"`

com="$MYSQL --mx --port=$port --protocol=tcp --user=root --password=$pass --execute=shutdown"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

[ "$dowait" = "wait" ] && $IMAWAITMANY "$portst" "$rep"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
