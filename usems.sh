#!/bin/sh
### replace mysqld for multiple instances
### 1: mandatory starting relative port
###    or comma delimited list of relative ports or ranges
### 2: debug orig, if so, replace mysqld. If not supplied just show mysqld
### IMAPORTBASE port number base
portst="$1"
howd="$2"

. `pwd`/imavars.dot
me="`$BASENAME $0`"

base="$IMAPORTBASE"
portlist="`ima_tolist $portst`"

from=''
[ "$howd" = 'debug' ] && from="$MYSQLD_DEBUG"
[ "$howd" = 'orig' ] && from="$MYSQLD_ORIG"

for port in $portlist ; do
  taport="$(($port + $base))"
  myd="$SANDBOXDIR/$taport/bin/mysqld"
  som='unknown'
  $CMP "$MYSQLD_ORIG" "$myd" >$DEVNULL && som='nodebug'
  $CMP "$MYSQLD_DEBUG" "$myd" >$DEVNULL && som='debug'
  ima_say "$me : was for $port ($taport), $som: "`$LS -al $myd`
  [ -z "$from" ] || {
    $CP -f "$from" "$myd"
    som='unknown'
    $CMP "$MYSQLD_ORIG" "$myd" >$DEVNULL && som='nodebug'
    $CMP "$MYSQLD_DEBUG" "$myd" >$DEVNULL && som='debug'
    ima_say "$me : now for $port ($taport), $som: "`$LS -al $myd`
  }
done
