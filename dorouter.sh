#!/bin/sh
port="$1"

. `pwd`/imavars.dot
pass=`$CAT "$_MUD/paz.dot"`
[ -z "$port" ] && port=`$EXPR "$IMAPORTBASE" + 1`

$MYSQLROUTER --bootstrap root@localhost:"$port" -d /root/mysqlrouter --user root --force --password "$pass"
$STARTROUTER
