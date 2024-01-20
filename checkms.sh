#!/bin/sh
### check multiple instances
### 1: mandatory comma delimited list of relative ports or ranges
### 2: optional, if wait, we will wait untill at leas readonly
### 3: wait timeout in seconds
### IMAPORTBASE port number base
### exit code 2: all readwrite
### exit code 3: some readonly
### exit code 1 or anything else: some down
portst="$1"
dowait="$2"
timeout="$3"

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

exitok='2'
finec="$exitok"
exitro='3'
hasro=''
exitx='1'

hasx=''
cocod=''
cotext=''
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMACHECKONE $taport $dowait $timeout"
  ima_say "$me : executing $com"
  $com
  ec="$?"
  ima_say "$me : finished with exit code $ec executing $com"
  cocod="${cocod}$ec "
  [ "$ec" = "$exitok" ] && {
    ima_say "$me : instance $port is readwrite"
    cotext="${cotext}$port:rw "
    continue
  }
  [ "$ec" = "$exitro" ] && {
    ima_say "$me : instance $port is readonly"
    cotext="${cotext}$port:ro "
    hasro='1'
    continue
  } || {
    ima_say "$me : instance $port is broken"
    cotext="${cotext}$port:br "
    hasx='1'
  }
done

ima_say "$me : exit subcodes $cocod"
ima_say "$me : exit indicators $cotext"
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
