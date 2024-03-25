#!/bin/sh
### 1: mandatory relative standard protocol port
### 2... schemas
port="$1"

. `pwd`/imavars.dot

[ -z "$2" -o -z "$1" -o "$1" = 'h' -o "$1" = 'help' ] && {
  $ECHO "Usage: $0 relative_port schemas..."
  $EXIT 1
}

shift
schemas="$*"

base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

./logmine.sh "$taport" 2>&1 | $LESS
./startms.sh "$port"
./count1sa.sh "$port" $schemas
./checktables1sa.sh "$port" $schemas
./usems.sh "$port"
./logmine.sh "$taport" | $GREP -i 'undefined|CROAK|oaks|oaked at|ignals|yntax'

$DF -h /mnt/c
$ECHO -n "Remove -rf /tmp/* ? "
$READ ans
[ "$ans" = 'y' ] && $RM -rfv /tmp/*
$DF -h /mnt/c
