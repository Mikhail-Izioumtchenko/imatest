#!/bin/sh
### list unused test parameters

. `pwd`/imavars.dot

tfile='imatest.yaml'
per='imatest.pl'

$CAT "$tfile" |
  $GREP -v '^#' |
    $SED 's/:.*//' |
      $SORT |
        $UNIQ -c |
          $GREP -v ' 1 ' |
  $CAT

for p in `$CAT "$tfile" |
  $GREP -v '^#' |
    $SED 's/:.*//' |
      $SORT |
  $CAT`; do
  $GREP "['\"]$p['\"]" "$per" >$DEVNULL || $ECHO "$p unused"
done

$ECHO "\nmay be used: virtual_expression_* server_terminate_*"
