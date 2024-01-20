#!/bin/sh
### create one sandbox, stop it
###   1: mandatory absolute port for standard protocol
###   2: mandatory absolute port for X protocol
port="$1"
portex="$2"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

pass=`$CAT "$IMAPAS"`

rc='0'
com="$ECHO $pass | $MYSQLSH --quiet-start=2 --passwords-from-stdin --execute \"dba.deploySandboxInstance($port, {'portX':$portex})\""
ima_say "$me : executing $com"
$EVAL $com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

com="$IMAINITONE $port"
ima_say "$me : executing $com"
$com
rc02="$?"
# we do not check rc all that much e.g. do not care if it failed on a ro instance
ima_say "$me : finished with exit code $rc02 executing $com"

com="$IMASTOPONE $port"
ima_say "$me : executing $com"
$com
rc02="$?"
ima_say "$me : finished with exit code $rc02 executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
