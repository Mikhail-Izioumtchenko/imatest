#!/bin/sh
### 1: absolute directory like /tmp
dir="$1"
outf="$1/b.sql"
forhelp="$1"

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 dir_with_lo.sql_i.out"
  $EXIT 1
}

fos="$dir/lo*sql"
los=`$LS -al $fos | $WC -l`
[ "$los" != '1' ] && {
  $LS -al $fos
#  $ECHO "only a single file is supported"
#  $EXIT 1
}

ios=`$LS -al $dir/i*out | $WC -l`
[ "$ios" != '1' ] && {
  $LS -al $dir/i*out
  $ECHO "only a single file is supported"
  $EXIT 1
}

ofils=''
for fil in $fos; do
  ofil="$dir/b_`$BASENAME $fil`"
  ofils="$ofils $ofil"
  #$ECHO "$ofil"
  $CAT $dir/i*out | $GREP 'CREATE|DROP' | $SED 's/.*executing *//' | $SED 's/: .*//' | $SED 's/$/;/' | $CAT >"$ofil"
  $CAT $fil | $SED 's/;  *[0-9]* *:.*/;/' | $CAT >>"$ofil"
done

$LS -al $ofils
$WC -l $ofils
$ECHO "\nSee also $dir"

$EXIT 0
