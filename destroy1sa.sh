#!/bin/sh
### destroy one sandbox
### 1: mandatory absolute port
port="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

com="$IMAKILLONE $port"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

com="$MYSQLSH --quiet-start=2 --execute \"dba.deleteSandboxInstance($port)\""
ima_say "$me : executing $com"
$com
subrc="$?"
[ "$rc" = '0' ] && rc="$subrc"
ima_say "$me : finished with exit code $subrc executing $com"

com="$RM -rf ${SANDBOXDIR:-need_set_SANDBOXDIR}/$port"
ima_say "$me : executing $com"
$com
subrc="$?"
ima_say "$me : finished with exit code $subrc executing $com"
[ "$rc" = '0' ] && rc="$subrc"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
