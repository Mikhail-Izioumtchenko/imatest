#!/bin/sh
### add instances to InnoDB replica set, they are started if necessary and left running
### 1: mandatory comma delimited list of relative ports or ranges
###    first in this list should already be part of the replica set
### IMAPORTBASE: port base
portst="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"

fil="$IMATMPDIR/`$BASENAME $0 .sh`.js"
portlist="`ima_tolist $portst`"
portmas=`$ECHO "$portlist" | $SED 's/^ +/X/' | $SED 's/ .*//' | $SED 's/X//'`
portmas=$(($portmas + $base))

com="$IMASTARTMANY $portst"
ima_say "$me : executing $com"
$com
starc="$?"
ima_say "$me : finished with exit code $starc executing $com"

rc='0'
for port in $portlist ; do
  $CAT <<EOF >"$fil"
  shell.connect('root@localhost:$portmas')
  rs = dba.getReplicaSet()
EOF

  taport="$(($port + $base))"
  [ "$taport" = "$portmas" ] && continue

  $ECHO "rs.addInstance('$IMAUSER@localhost:$taport')" >>"$fil"
done
ima_file "$me" "$fil"

com="$ECHO \"\\n\" | $MYSQLSH --quiet-start=2 --file $fil"
ima_say "$me : executing $com"
$EVAL $com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
