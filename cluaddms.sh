#!/bin/sh
### add instances to InnoDB cluster, they are started if necessary and left running
### 1: mandatory comma delimited list of relative ports or ranges
###    first in this list should already be part of the cluster
### IMAPORTBASE: port base
portst="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"

fil="/tmp/`$BASENAME $0 .sh`.js"
portlist="`ima_tolist $portst`"
portmas=`$ECHO "$portlist" | $SED 's/^ +/X/' | $SED 's/ .*//' | $SED 's/X//'`
portmas=$(($portmas + $base))

starc='0'
com="$IMASTARTMANY $portst"
ima_say "$me : executing $com"
$EVAL $com
starc="$?"
ima_say "$me : finished with exit code $starc executing $com"

rc='0'
### one by one, workaround for https://bugs.mysql.com/?id=113410
for port in $portlist ; do
  $CAT <<EOF >"$fil"
  shell.connect('root@localhost:$portmas')
  cluster = dba.getCluster()
EOF

  taport="$(($port + $base))"
  [ "$taport" = "$portmas" ] && continue
  $ECHO "cluster.addInstance('root@localhost:$taport')" >>"$fil"
  ima_file "$me" "$fil"

  subrc='0'
  com="$ECHO \"\\n\" | $MYSQLSH --quiet-start=2 --file $fil"
  ima_say "$me : executing $com"
  $EVAL $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
