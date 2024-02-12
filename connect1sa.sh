#!/bin/sh
### interactively connect to instance using mysqlsh
### 1: mandatory relative standard protocol port
### 2... are passed to client
port="$1"
shift
more="$*"

. `pwd`/imavars.dot
base="$IMAPORTMXBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --host 127.0.0.1 --password=$pass --sqlx --mx $more"
$com
