#!/bin/sh
### initialize one instance given absolute port
###
port="$1"

. `pwd`/imavars.dot
me="`$BASENAME $0`"
ima_say "$me : starting as $0 $@"

pass=`$CAT "$IMAPAS"`
fil="/tmp/`$BASENAME $0 .sh`.sql"

$CAT >"$fil" <<EOF
CREATE SCHEMA $IMABASCHEMA;
CREATE TABLE $IMABASCHEMA.$IMABATABLE ($IMABASTRUCT);
INSERT INTO $IMABASCHEMA.$IMABATABLE VALUES ($IMABAVALUES);
EOF
ima_file "$me" "$fil"

com="$MYSQLSH --quiet-start=2 --user=$IMAUSER --password=$pass --sql --port=$port --file=$fil"
ima_say "$me : executing $com"
$com
rc="$?"
ima_say "$me : finished with exit code $rc executing $com"

ima_say "$me : exiting with exit code $rc"
$EXIT $rc
