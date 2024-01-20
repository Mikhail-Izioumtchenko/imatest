#!/bin/sh
### wait for one instance to disappear
### 1: is absolute port number
### 2: optional report interval, default 0 means do not report
### 3: optional approximate timeout in seconds, default fairly large, see code
### 4: optional sleep time between checking, suitable to passing to sleep, defaulr fairly small, see code
### exit 0: no instance or it is over
### exit 1: timeout
port="${1:-findme}"
rep="${2:-0}"
tout="${3:-300}"
slep="${4:-0.1}"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

prev="`$DATE +%s`"
strt="$prev"
first='1'
while true; do
  found=`$PS -ef | $GREP "$MYSQLD" | $GREP -v "$GREP" | $GREP "/$port/"`
  [ ! -z "$found" -a "$first" = '1' ] && {
    [ "$rep" != '0' ] && {
      ima_say "$me : $found"
    }
    first='0'
  }
  curt="`$DATE +%s`"
  passed="$(($curt - $strt))"
  [ -z "$found" ] && {
    rc='0'
    [ "$rep" != 0 ] && {
      ima_say "$me : instance on port $port is gone after about $passed seconds"
      ima_say "$me : exiting with exit code $rc"
    }
    $EXIT "$rc"
  }
  [ "$passed" -gt "$tout" ] && {
    rc='1'
    [ "$rep" != 0 ] && {
      ima_say "$me : timeout of $tout waiting for instance on port $port to disappear"
      ima_say "$me : exiting with exit code $rc"
    }
    $EXIT "$rc"
  }
  [ "$(($curt - $prev))" -ge "$rep" -a "$rep" != '0' ] && {
    ima_say "$me : $found"
    prev="$curt"
  }
  $SLEEP "$slep"
done
