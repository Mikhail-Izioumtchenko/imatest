#!/bin/sh
### create InnoDB cluster set, the cluster must already be running
### 1: mandatory relative port to connect to
### IMAPORTBASE: port base
### IMACLUSTERSETNAME: cluster name
me="$0"
portmas="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
cluset="$IMACLUSETNAME"
pass=`$CAT "$IMAPAS"`
port=$(($portmas + $base))

fil="$IMATMPDIR/`$BASENAME $0 .sh`.js"

$CAT <<EOF >"$fil"
  clu=dba.getCluster()
  cluset=clu.createClusterSet('$IMACLUSETNAME')
EOF
ima_file "$fil"

com="$ECHO \"\\\\\n\" | $MYSQLSH --quiet-start=2 --port=$port --user=$IMAROOT --password=$pass --file $fil"
ima_say "$me : executing $com"
$EVAL $com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
