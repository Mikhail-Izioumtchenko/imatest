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
lof="/tmp/`$BASENAME $0`.tmp"

$PERL logmine.pl /root/mysql-sandboxes/*/sandboxdata/error.log /tmp/*log /tmp/*out 2>&1 | $TEE "$lof" | $LESS
./startms.sh "$port"
./count1sa.sh "$port" $schemas
./checktables1sa.sh "$port" $schemas
./usems.sh "$port"

$ECHO "signals and croaks START"
$GREP -i 'signal|croak' "$lof"
$ECHO "signals and croaks SHORT"
$GREP -i 'signal|croak' "$lof" | $GREP -v semi
$ECHO "signals and croaks END"
$ECHO "See also $lof"
$LS -lt /tmp
$DF -h /mnt/c
$ECHO -n "Remove -rf /tmp/* ? "
$READ ans
[ "$ans" = 'y' ] && $RM -rfv /tmp/*
$DF -h /mnt/c
