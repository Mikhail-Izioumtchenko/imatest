#!/bin/sh
### kill single instance
### 1: mandatory absolute port
### 2: if 'wait', will wait for the instances to stop with a reasonable report interval, see code
port="$1"
dowait="$2"

rep='5'

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

com="$MYSQLSH --quiet-start=2 --execute dba.killSandboxInstance($port)"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

[ "$dowait" = "wait" ] && $IMAWAITONE "$portst" "$rep"

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
