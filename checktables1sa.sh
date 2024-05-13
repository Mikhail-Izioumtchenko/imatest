#!/bin/sh
### count(*) for all tables 
### 1: mandatory relative standard protocol port
### 2... schemas
port="$1"
forhelp="$1"
[ -z "$1" ] || shift
schemas="$*"

. `pwd`/imavars.dot
base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_port schema..."
  $ECHO "  To check all tables in the schemas"
  $ECHO "  Example: $0 2 gts1 gts2"
  $EXIT 1
}

com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --password=$pass --sql --log-sql=all $more"
allok='0'
allbad='0'
for sname in $schemas; do
  sok='0'
  sbad='0'
  tables=`$ECHO "use $sname;\nSHOW TABLES;" | $com 2>&1 | $GREP -v ^verbose: | $GREP -v ^Tables_in`
  for i in $tables; do
    cnt=`$ECHO "$sname.$i" | $AWK '{printf("CHECK TABLE %s;\n",$0,$0)}' | $com `
    ok=`$ECHO "$cnt"| $GREP -v Msg_text | $SED 's/\s+check\s+status\s+/ /'`
    $ECHO -n "$ok, "
    tabok=`$ECHO "$cnt" | $GREP 'check.*status' | $AWK '{print $NF}'`
    [ "$tabok" = 'OK' ] && sok=$(($sok+1)) || sbad=$(($sbad+1))
  done
  $ECHO "\n  schema $sname: $sok OK, $sbad bad"
  allok=$(($sok+$allok))
  allbad=$(($sbad+$allbad))
done
$ECHO "  all schemas $schemas: $allok OK, $allbad bad"
