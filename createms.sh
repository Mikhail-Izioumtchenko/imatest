#!/bin/sh
### create multiple sandboxes
### 1: mandatory comma delimited list of relative ports or ranges
### port base is IMAPORTBASE
### x port base is IMAPORTBAXX
portst="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
baseex="$IMAPORTBAXX"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  portex="$(($port + $baseex))"
  com="$IMACREATEONE $taport $portex"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
