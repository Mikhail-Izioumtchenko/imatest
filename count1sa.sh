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
allcnt='0'
for sname in $schemas; do
  sccnt='0'
  tables=`$ECHO "use $sname;\nSHOW TABLES;" | $com 2>&1 | $GREP -v ^verbose: | $GREP -v ^Tables_in`
  for i in $tables; do
    cnt=`$ECHO "$sname.$i" | $AWK '{printf("SELECT COUNT(*) AS \`%s\` FROM %s;\n",$0,$0)}' | $com `
    $ECHO "$cnt"
    tacnt=`$ECHO "$cnt" | $GREP '^[0-9]*$'`
    sccnt=$(($sccnt+$tacnt))
  done
  $ECHO "  schema $sname: $sccnt rows total"
  allcnt=$(($sccnt+$allcnt))
done
$ECHO "  all schemas $schemas: $sccnt rows total"
