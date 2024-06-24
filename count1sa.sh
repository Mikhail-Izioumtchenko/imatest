#!/bin/sh
### count(*) for all tables 
### 1: mandatory relative standard protocol port
### 2... schemas
port="$1"
forhelp="$2"
[ -z "$1" ] || shift
schemas="$*"

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_port schema..."
  $ECHO "  To count recors in all tables in the schemas"
  $ECHO "  Example: $0 2 gts1 gts2"
  $EXIT 1
}

base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

com="$MYSQLSH --quiet-start=2 --port=$taport --user=root --password=$pass --sql --log-sql=all $more"
echo "$com";exit
allcnt='0'
for sname in $schemas; do
  sccnt='0'
  tables=`$ECHO "use $sname;\nSHOW TABLES;" | $com 2>&1 | $GREP -v ^verbose: | $GREP -v ^Tables_in`
  for i in $tables; do
    cnt=`$ECHO "$sname.$i" | $AWK '{printf("SELECT COUNT(*) AS \`%s\` FROM %s;\n",$0,$0)}' | $com `
    tacnt=`$ECHO "$cnt" | $GREP '^[0-9]*$'`
    [ -z "$tacnt" ] && {
      $ECHO "No tables, maybe failed connection, going away"
      $EXIT 1
    }
    $ECHO -n "$sname.$i: $tacnt, "
    sccnt=$(($sccnt+$tacnt))
  done
  $ECHO "\n  schema $sname: $sccnt rows total"
  allcnt=$(($sccnt+$allcnt))
done
$ECHO "  all schemas $schemas: $allcnt rows total"
