#!/bin/sh
### start one instance given absolute port
### 1: port number
### 2: optional, if wait, will wait unless the instance is at least readonly
### 3: wait timeout in seconds
port="$1"
dowait="$2"
timeout="${3:-300}"

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $@"

com="$MYSQLSH --quiet-start=2 --execute dba.startSandboxInstance($port)"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

[ "$dowait" = 'wait' ] && {
  com="$IMACHECKONE $port $dowait $timeout"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' -a "$subrc" != '2' ] && rc='1'
}

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
