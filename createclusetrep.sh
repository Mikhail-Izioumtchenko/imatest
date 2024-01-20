#!/bin/sh
### create a replica cluster for a clusterset and add instances to it, they must already exist,
### master cluster must already be running
### 1: mandatory comma delimited list of relative ports or ranges
###    first must be in the master cluster
### 2: optional cluster replica set name suffix
### IMAPORTBASE: port base
### IMACLUSETNAME: cluster set name
### IMACLUREPBASE: cluster replica name base
portst="$1"
clurep="$2"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
clurepname="${IMACLUREPBASE}$clurep"
pass=`$CAT "$IMAPAS"`

fil="$IMATMPDIR/`$BASENAME $0 .sh`.js"
portlist="`ima_tolist $portst`"
portmas=`$ECHO "$portlist" | $SED 's/^ +/X/' | $SED 's/ .*//' | $SED 's/X//'`
taportmas=$(($portmas + $base))

starc='0'
com="$IMASTARTMANY $portst"
ima_say "$me : executing $com"
$com
starc="$?"
ima_say "$me : finished with exit code $starc executing $com"

### workaround for https://bugs.mysql.com/bug.php?id=113410 : add instances in separate executions
rc='0'
hascre='0'
port1st=''
for port in $portlist ; do
  [ "$port" = "$portmas" ] && continue
  taport="$(($port + $base))"

  [ "$hascre" = '0' ] && {
    $CAT <<EOF >"$fil"
  cluset = dba.getClusterSet()
  clurep = cluset.createReplicaCluster("127.0.0.1:$taport", "$clurepname")
EOF
    hascre='1'
    port1st="$port"
    ima_file "$me" "$fil"

    com="$ECHO \"\\n\" | $MYSQLSH --quiet-start=2 --port=$taportmas --user=$IMAROOT --password=$pass --file $fil"
    ima_say "$me : executing $com"
    $EVAL $com
    rc="$?"
    ima_say "$me : finished with exit code $rc executing $com"

    continue
  }

  com="$IMACLUADDMANY $port1st,$port"
  ima_say "# $me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
