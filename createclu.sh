#!/bin/sh
### create InnoDB cluster, all instances must already exist
### 1: mandatory comma delimited list of relative ports or ranges
### IMAPORTBASE: port base
### IMACLUSTERNAME: cluster name
me="$0"
portst="${1}"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
clun="$IMACLUNAME"

fil="$IMATMPDIR/`$BASENAME $0 .sh`.js"
portlist="`ima_tolist $portst`"
portmas=`$ECHO "$portlist" | $SED 's/^ +/X/' | $SED 's/ .*//' | $SED 's/X//'`
portmabas=$(($portmas + $base))

### start first instance
com="$IMASTARTONE $portmabas"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

$CAT <<EOF >"$fil"
  shell.connect('root@localhost:$portmabas')
  cluster = dba.createCluster('$clun')
EOF
ima_file "$fil"

com="$ECHO \"\\\\\n\" | $MYSQLSH --quiet-start=2 --file $fil"
ima_say "# $me : executing $com"
$EVAL $com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

### add by one, workaround for bug https://bugs.mysql.com/bug.php?id=113410
for port in $portlist ; do
  [ "$port" = "$portmas" ] && continue
  com="$IMACLUADDMANY $portmas,$port"
  ima_say "# $me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
