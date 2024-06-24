#!/bin/sh
### set parm for one instance
### 1: port number, absolute
### 2: source regex
### 3: result line
port="$1"
forhelp="$1"
src="$2"
res="$3"

. `pwd`/imavars.dot
me=`$BASENAME $0`

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 absolute_port source_regex result"
  $ECHO "       To change my.cnf"
  $ECHO "  Example: $0 4204 innodb_force_recovery=. innodb_force_recovery=3"
  $EXIT 1
}

tf="/tmp/$me.tmp"
conf="$SANDBOXDIR/$port/my.cnf"
$ECHO "$conf before:"
$GREP "$src" "$conf"
$CAT "$conf" | $SED "s/$src/$res/" >"$tf"
$ECHO "$tf after:"
$GREP "$src" "$tf"
$CP -iv "$tf" "$conf"
$ECHO "$conf after:"
$GREP "$src" "$conf"

$EXIT 0
