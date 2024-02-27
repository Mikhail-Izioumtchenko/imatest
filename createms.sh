#!/bin/sh
### create multiple sandboxes
### 1: mandatory comma delimited list of relative ports or ranges
### 2...: optional mysqldOptions list 
### port base is IMAPORTBASE
### x port base is IMAPORTMXBASE
forhelp="$1"
portst="$1"
shift
more="$*"

. `pwd`/imavars.dot
me="`$BASENAME $0`"

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5 [mysqldOptions]..."
  $EXIT 1
}

ima_say "$me : starting as $0 $@"

base="$IMAPORTBASE"
baseex="$IMAPORTMXBASE"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  portex="$(($port + $baseex))"
  com="$IMACREATEONE $taport $portex $more"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
