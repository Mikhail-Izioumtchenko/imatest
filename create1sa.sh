#!/bin/sh
### create one sandbox, optionally create a small dataset, stop sandbox
###   1: mandatory absolute port for standard protocol
###   2: mandatory absolute port for X protocol
###   3: init|noinit
###   4...: optional mysqldOptions list 
forhelp="$1"
port="$1"
portex="$2"
doinit="$3"
mopt=''
[ "$#" -gt 3 ] && {
  shift 3
  mopt="$*"
}

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 absolute_port_std_protocol absolute_port_X_protocol init|noinit [mysqldOptions]..."
  $ECHO "       Create one sandbox, optionally create a small dataset, stop sandbox."
  $EXIT 1
}

me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

add=''
for i in $mopt; do
  add="$add,'$i'"
done
[ -z "$add" ] || {
  add=`$ECHO "$add" | $SED 's/^,//'`
  add=", 'mysqldOptions':[$add]"
}

pass=`$CAT "$IMAPAS"`

rc='0'
com="$ECHO $pass | $MYSQLSH --quiet-start=2 --passwords-from-stdin --execute \"dba.deploySandboxInstance($port, {'portX':$portex$add})\""
ima_say "$me : executing $com"
$EVAL $com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

com="$IMAINITONE $port"
[ "$doinit" = 'init' ] && {
  ima_say "$me : executing $com"
  $com
  rc02="$?"
# we do not check rc all that much e.g. do not care if it failed on a ro instance
  ima_say "$me : finished with exit code $rc02 executing $com"
} || {
  ima_say "$me : init is not 'init' but rather '$doinit' so NOT executing $com"
}

com="$IMASTOPONE $port"
ima_say "$me : executing $com"
$com
rc02="$?"
ima_say "$me : finished with exit code $rc02 executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
