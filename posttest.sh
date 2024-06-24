#!/bin/sh
### 1: mandatory relative standard protocol port
### 2... schemas or all
port="$1"

. `pwd`/imavars.dot

[ -z "$2" -o -z "$1" -o "$1" = 'h' -o "$1" = 'help' ] && {
  $ECHO "Usage: $0 relative_port schemas...|all [,mchs for messages count check signals]"
  $EXIT 1
}

shift
schemas="$*"
l=''
for i in $*; do
  l="$i"
done
com=`$ECHO "$l" | $GREP -c ','`
dom='y'
doc='y'
doh='y'
dos='y'
[ "$com" != '0' ] && {
  [ `$ECHO "$l" | $GREP -c 'm'` = '0' ] && dom='n'
  [ `$ECHO "$l" | $GREP -c 'c'` = '0' ] && doc='n'
  [ `$ECHO "$l" | $GREP -c 'h'` = '0' ] && doh='n'
  [ `$ECHO "$l" | $GREP -c 's'` = '0' ] && dos='n'
  schemas=`$ECHO "$schemas" | $SED "s/ $l$//"`
}

base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`
lof="/tmp/`$BASENAME $0`.tmp"

./usems.sh "$port"

elog="/root/mysql-sandboxes/420$port/sandboxdata/error.log"
tomine="$elog /tmp/*out"
[ "$dom" = 'y' ] && $PERL logmine.pl $tomine 2>&1 | $TEE "$lof" | $LESS
[ "$doc" = 'y' -o "$doh" = 'y' ] && {
  ./startms.sh "$port"
  [ "$schemas" = 'all' ] && {
    com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --password=$pass --sql --log-sql=all"
    schemas=`$ECHO "SHOW SCHEMAS;" | $com 2>&1 | $GREP -v 'verbose:|Database|(information|performance)_schema|mysql|sys|imaschema'`
  }
}

$ECHO ""
./usems.sh "$port"
[ "$doc" = 'y' ] && ./count1sa.sh "$port" $schemas
$ECHO ""
./usems.sh "$port"
[ "$doc" = 'y' ] && ./checktables1sa.sh "$port" $schemas
$ECHO ""

./usems.sh "$port"
[ "$dos" = 'y' ] && {
  $ECHO -n "\nENTER before looking at signals: "
  $READ ans
  
  $ECHO ""
  $ECHO "signals and croaks START"
  hom=`$GREP -i 'ssertion|signal|croak' $tomine | $GREP -v '(hakill1sa.sh|checkms.sh : 0 signals or assertions)' | $WC -l`
  [ "$hom" -gt 10 ] && $GREP -i 'signal|croak' $tomine | $GREP -v hakill1sa.sh |  $GREP -v '(hakill1sa.sh|checkms.sh : 0 signals or assertions)' | $LESS || $GREP -i 'signal|croak' $tomine | $GREP -v '(hakill1sa.sh|checkms.sh : 0 signals or assertions)'
  $ECHO ""
  $ECHO "signals and croaks SHORT"
  $GREP -i 'ssertion|signal|croak' $tomine | $GREP -v '(hakill1sa.sh|checkms.sh : 0 signals or assertions)' | $GREP -v semi
  $ECHO "signals and croaks END with $hom signals and croaks including semicroaks"
  $ECHO ""
  $ECHO "JUST SIGNALS in $elog"
  $GREP -i 'ssertion|signal' $elog
  $ECHO "SIGNALS END"
  $ECHO ""
  $ECHO "See also $lof"
}

$ECHO ""
$LS -lt /tmp | $GREP -v '_thread|\.fin|\.out|\.tmp|\.sh\.sql'
$ECHO "and some '_thread|\.fin|\.out|\.tmp|\.sh\.sql'"
$DF -h /mnt/c
$ECHO ""

./usems.sh "$port"

$GREP main.*seed /tmp/i*out
$ECHO -n "Remove -rf /tmp/* ? "
$READ ans
[ "$ans" = 'y' ] && $RM -rfv /tmp/*
$ECHO -n "Remove $elog? "
$READ ans
[ "$ans" = 'y' ] && $RM -fv $elog
$DF -h /mnt/c

./usems.sh "$port"
$ECHO -n "stopms $port? "
$READ ans
[ "$ans" = 'y' ] && ./stopms.sh "$port" wait
$GREP main.*seed /tmp/i*out
