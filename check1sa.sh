#!/bin/sh
### check one instance given absolute port
### 1: mandatory absolute port
### 2: optional, if wait, will wait unless the instance is at least readonly
### 3: wait timeout in seconds
### exit code 1: broken or timeout
### exit code 2: readwrite
### exit code 3: readonly
port="$1"
dowait="$2"
timeout="${3:-300}"

slep='1'
rep='5'

exitok='2'
exitro='3'
exitx='1'

. `pwd`/imavars.dot
me=`$BASENAME $0`
ima_say "$me : started as $0 $@"

me=`$BASENAME "$0"`
pass=`$CAT "$IMAPAS"`
fil="$IMATMPDIR/$me.sql"
outfil="$IMATMPDIR/$me.out"

$CAT >"$fil" <<EOF
DELETE FROM $IMABASCHEMA.$IMABATABLE;
SHOW WARNINGS;
SELECT * FROM $IMABASCHEMA.$IMABATABLE;
SHOW WARNINGS;
INSERT INTO $IMABASCHEMA.$IMABATABLE VALUES($IMABAVALUES);
SHOW WARNINGS;
SELECT * FROM $IMABASCHEMA.$IMABATABLE;
SHOW WARNINGS;
EOF
ima_file "$me" "$fil"

try=`$CAT <<EOF
Connecting to MySQL at: root@localhost:$port$
CONNECTED: localhost:$port$
DELETE FROM $IMABASCHEMA.$IMABATABLE$
SHOW WARNINGS$
SELECT . FROM $IMABASCHEMA.$IMABATABLE$
INSERT INTO $IMABASCHEMA.$IMABATABLE VALUES.$IMABAVALUES.$
^$IMABAVALUES$
ERROR
EOF
`

need=' 1 1 1 4 2 1 1 0'
needro=' 1 1 1 4 2 1 2 2'
strt=`$DATE +%s`
dorep="$strt"
while true; do
  $MYSQLSH --quiet-start=2 --user="$IMAUSER" --password="$pass" --sql --force --log-sql=all --verbose --port="$port" --file="$fil" \
    >"$outfil" 2>&1

  rc=`$ECHO "$try" | while $READ lin; do
    co=\`$GREP "$lin" "$outfil" | $WC -l\`
    found="$found $co"
    $ECHO "$found"
  done | $TAIL -1l`
  [ "$rc" = "$need" ] && {
    ima_say "$me : exiting with exit code $exitok"
    $EXIT "$exitok"
  }
  [ "$rc" = "$needro" ] && {
    ima_say "$me : exiting with exit code $exitro"
    $EXIT "$exitro"
  }
  [ "$dowait" = 'wait' ] || break
  now=`$DATE +%s`
  [ $(($now - $strt)) -ge "$timeout" ] && break
  [ $(($now - $dorep)) -ge "$rep" ] && {
    ima_say "$me : +$rc+, will wait, timeout=$timeout"
    dorep="$now"
  }
  $SLEEP "$slep"
done

ima_say "$me : exiting with exit code $exitx"
$EXIT "$exitx"
