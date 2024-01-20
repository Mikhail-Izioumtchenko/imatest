#!/bin/sh
### interactively connect to instance using mysqlsh
### 1: mandatory relative standard protocol port
### 2: mandatory if mysql, use mysql client for connection
### 3... are passed to client
port="$1"
shift
mys="$2"
shift
more="$*"

. `pwd`/imavars.dot
base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --password=$pass --sql $more"
[ "$mys" = 'mysql' ] && com="$MYSQL --port=$taport --protocol=tcp --user=root --password=$pass $more"
$com
