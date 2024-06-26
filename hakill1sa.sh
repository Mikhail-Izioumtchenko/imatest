#!/bin/sh
### send signal to one instance
### 1: mandatory absolute port number
### 2: mandatory signal name or number
port="${1:-findme}"
forhelp="$1"
sig="${2:-findme}"

. `pwd`/imavars.dot
me="`$BASENAME $0`"

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 absolute_port signal"
  $ECHO "  Example: $0 4202 9"
  $EXIT 1
}

ima_say "$me : starting as $0 $@"

found=`$PS -ef | $GREP "$MYSQLD" | $GREP -v "$GREP" | $GREP "/$port/" | $AWK '{print $2}'`
ima_say "$me : found instances on port $port: pid '$found' will send signal $sig"

com="$KILL -$sig $found"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
