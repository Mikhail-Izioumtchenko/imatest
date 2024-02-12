#!/bin/sh
### 1: mandatory relative standard protocol port
### 2... schemas
port="$1"
shift
schemas="$*"

. `pwd`/imavars.dot
base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

./logmine.sh "$taport" | $LESS
./startms.sh "$port"
./count1sa.sh "$port" $schemas
./checktables1sa.sh "$port" $schemas
./usems.sh "$port"
./logmine.sh "$taport" | grep 'ooked at'
