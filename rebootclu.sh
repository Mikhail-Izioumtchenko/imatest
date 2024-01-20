#!/bin/sh
### cluster full reboot
### 1: mandatory comma delimited list of relative ports or ranges
### IMAPORTBASE: port base
portst="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"
portmas=`$ECHO "$portlist" | $SED 's/^ +/X/' | $SED 's/ .*//' | $SED 's/X//'`
portmas=$(($portmas + $base))
tfil="$IMATMPDIR/`$BASENAME $0 .sh`.js"

com="$IMASTARTMANY $portst"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

$CAT <<EOF >"$tfil"
  shell.connect('root@localhost:$portmas')
  dba.rebootClusterFromCompleteOutage()
EOF
ima_file "$me" "$tfil"

com="$MYSQLSH --quiet-start=2 --file $tfil"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
