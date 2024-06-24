#!/bin/sh
### interactively connect to instance using mysqlsh
### 1: mandatory relative standard protocol port
### 2... are passed to client
forhelp="$1"
port="$1"
[ -z "$port" ] || shift
more="$*"

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_port [passed to mysqlsh]..."
  $EXIT 1
}

base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --host 127.0.0.1 --password=$pass --sql $more"
#echo "$com";exit
$com
