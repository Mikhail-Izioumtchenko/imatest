#!/bin/sh
### show status of InnoDB cluster
### 1: mandatory relative port
### IMAPORTBASE: port base
portst="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"

fil="$IMATMPDIR/`$BASENAME $0 .sh`.js"
port=$(($portst + $base))

$CAT <<EOF >"$fil"
  shell.connect('root@localhost:$port')
  clu = dba.getCluster()
  clu.status()
EOF
ima_file "$me" "$fil"

com="$MYSQLSH --quiet-start=2 --interactive --file $fil"
ima_say "$me : executing $com"
rc='7'
{
  $com
  rc="$?"
} 2>&1 | ima_report "$me"
ima_say "$me : finished with exit code $rc executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
