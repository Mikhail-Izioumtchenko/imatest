#!/bin/sh
### wait for multiple instances
### 1: mandatory comma delimited list of relative ports or ranges
### 2: report interval, passed to wait1sa.sh, see that file
### 3: timeout, passed to wait1sa.sh, see that file
### 4: sleep interval, passed to wait1sa.sh, see that file
### IMAPORTBASE port number base
portst="$1"
rep="$2"
tout="$3"
slep="$4"

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $@"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

rc='0'
for port in $portlist ; do
  taport="$(($port + $base))"
  com="$IMAWAITONE $taport $rep $tout $slep"
  ima_say "$me : executing $com"
  $com
  subrc="$?"
  ima_say "$me : finished with exit code $subrc executing $com"
  [ "$rc" = '0' ] && rc="$subrc"
done

ima_say "$me : exiting with exit code $rc"
$EXIT "$rc"
