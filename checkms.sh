#!/bin/sh
### check multiple instances
### 1: mandatory comma delimited list of relative ports or ranges
### 2: optional, if wait, we will wait until at least readonly
### 3: wait timeout in seconds
### IMAPORTBASE port number base
### exit code 2: all readwrite
### exit code 3: some readonly
### exit code 1: some down
### exit code 4: some aborted. Does not cover signal 9.
portst="$1"
dowait="$2"
timeout="$3"
forhelp="$1"

. `pwd`/imavars.dot
me=`$BASENAME $0`
exitok='2'
exitro='3'
exitx='1'
exitsig='4'

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_ports_as_1-3,5 [wait [wait_timeout_seconds]]"
  $ECHO "  to check instances state."
  $ECHO "Exit codes:"
  $ECHO "  $exitok: all instances are readwrite"
  $ECHO "  $exitro: some instances are readonly"
  $ECHO "  $exitx: some instances are broken"
  $ECHO "  $exitsig: some instances have failed. Done by log grepping only."
  $ECHO "If wait is specified we will wait until all instances are at least readonly."
  $EXIT 1
}

ima_say "$me : started as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

finec="$exitok"
hasro=''

hasx=''
cocod=''
cotext=''
hassig=''
toecnt='0'
for port in $portlist ; do
  tsig=''
  taport="$(($port + $base))"
  errorlog="$SANDBOXDIR/$taport/sandboxdata/error.log"
  ecnt=`$GREP 'mysqld got signal|Assertion failure' "$errorlog" | $WC -l`
  toecnt=$(($toecnt + $ecnt))
  [ "$ecnt" != '0' ] && {
      $GREP '$MySQL got signal|Assertion failure' $errorlog
      ima_say "$me: PROBLEM: $ecnt signals or assertions in $errorlog"
      hassig='1'
      tsig='SIG'
  }
  com="$IMACHECKONE $taport $dowait $timeout"
  ima_say "$me : executing $com"
  $com
  ec="$?"
  ima_say "$me : finished with exit code $ec executing $com"
  cocod="${cocod}$ec "
  [ "$ec" = "$exitok" ] && {
    ima_say "$me : instance $port is readwrite"
    cotext="${cotext}$port:rw$tsig "
    continue
  }
  [ "$ec" = "$exitro" ] && {
    ima_say "$me : instance $port is readonly"
    cotext="${cotext}$port:ro$tsig "
    hasro='1'
    continue
  } || {
    ima_say "$me : instance $port is broken"
    cotext="${cotext}$port:br$tsig "
    hasx='1'
  }
done

ima_say "$me : exit subcodes $cocod"
ima_say "$me : exit indicators $cotext"
ima_say "$me : $toecnt signals or assertions"
[ -z "$hassig" ] || {
  ima_say "$me : exiting with exit code $exitsig"
  $EXIT "$exitsig"
}
[ -z "$hasx" ] || {
  ima_say "$me : exiting with exit code $exitx"
  $EXIT "$exitx"
}
[ -z "$hasro" ] || {
  ima_say "$me : exiting with exit code $exitro"
  $EXIT "$exitro"
}
ima_say "$me : exiting with exit code $exitok"
$EXIT "$exitok"
