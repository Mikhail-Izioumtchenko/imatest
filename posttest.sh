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

tomine="/root/mysql-sandboxes/*/sandboxdata/error.log /tmp/*log /tmp/*out"
$PERL logmine.pl $tomine 2>&1 | $TEE "$lof" | $LESS
./startms.sh "$port"
$ECHO ""
./count1sa.sh "$port" $schemas
$ECHO ""
./checktables1sa.sh "$port" $schemas
$ECHO ""
./usems.sh "$port"

$ECHO ""
$ECHO "signals and croaks START"
hom=`$GREP -i 'signal|croak' $tomine | $GREP -v hakill1sa.sh | $WC -l`
[ "$hom" -gt 10 ] && $GREP -i 'signal|croak' $tomine | $GREP -v hakill1sa.sh | $LESS || $GREP -i 'signal|croak' $tomine | $GREP -v hakill1sa.sh
$ECHO ""
$ECHO "signals and croaks SHORT"
$GREP -i 'signal|croak' $tomine | $GREP -v hakill1sa.sh | $GREP -v semi
$ECHO "signals and croaks END"
$ECHO ""
$ECHO "See also $lof"
$ECHO ""
$LS -lt /tmp | $GREP -v '_thread|\.fin|\.out|\.tmp|\.sh\.sql'
$ECHO "and some '_thread|\.fin|\.out|\.tmp|\.sh\.sql'"
$DF -h /mnt/c
$ECHO ""
$ECHO -n "Remove -rf /tmp/* ? "
$READ ans
[ "$ans" = 'y' ] && $RM -rfv /tmp/*
$DF -h /mnt/c
