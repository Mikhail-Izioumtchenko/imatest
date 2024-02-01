#!/bin/sh
### count(*) for all tables 
### 1: mandatory relative standard protocol port
### 2... schemas
port="$1"
shift
schemas="$*"

. `pwd`/imavars.dot
base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --password=$pass --sql --log-sql=all $more"
allok='0'
allbad='0'
for sname in $schemas; do
  sok='0'
  sbad='0'
  tables=`$ECHO "use $sname;\nSHOW TABLES;" | $com 2>&1 | $GREP -v ^verbose: | $GREP -v ^Tables_in`
  for i in $tables; do
    cnt=`$ECHO "$sname.$i" | $AWK '{printf("CHECK TABLE %s;\n",$0,$0)}' | $com `
    $ECHO "$cnt"
    tabok=`$ECHO "$cnt" | $GREP 'check.*status' | $AWK '{print $NF}'`
    [ "$tabok" = 'OK' ] && sok=$(($sok+1)) || sbad=$(($sbad+1))
  done
  $ECHO "  schema $sname: $sok OK, $sbad bad"
  allok=$(($sok+$allok))
  allbad=$(($sbad+$allbad))
done
$ECHO "  all schemas $schemas: $allok OK, $allbad bad"
