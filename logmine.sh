#!/bin/sh
# search logs, report
# 1: absolute port

port="$1"

. `pwd`/imavars.dot

efiles="/tmp/imatest.pl.out /tmp/load_thread_*.* /tmp/master_thread.log /tmp/imatest.out"
myfiles="/root/mysql-sandboxes/$port/*/error.log"

refiles=''
for i in $efiles $myfiles; do
  [ -f "$i" ] && refiles="$refiles $i" || echo "$i is not a regular file, ignore"
done

out=`$CAT $refiles |
#  $GREP 'ERROR|Warning|System' |
  $GREP 'ERROR|Error' |
    $SED 's/[^[]*\[/[/' |
      $SED 's/\[//' |
        $SED 's/\[/:/g' |
          $SED 's/\]/:/g' |
            $SED 's/: :/_/g' |
              $SED 's/ERROR: /ERROR-/ig' |
                $SED "s/doesn't/doesnot/g" |
                  $SED "s/[cC]an't/cannot/g" |
                    $SED "s/'[^']+'/__squoted_name__/g" |
                      $SED 's/\`[^\`]+\`/__squoted_name__/g' |
                        $SED 's/ERROR +/Error-/ig' |
                        $SED 's/[ =][0-9]+/ N /g' |
                          $SED 's/[(][0-9]+[)]/_pNNNp_/g' |
                            $SED 's/:/ /g' |
                              $SORT |
                                $UNIQ -c |
                                  $SORT -n |
  $CAT`
$ECHO "\n=== next0 ===\n"
out=`$ECHO "$out" | $SED 's/ [0-9]+ / N /g' | $SED 's/ [0-9]+ / N /g' | $SED 's/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/D/' | $SORT | $UNIQ -c | $SORT -n`
echo "$out"
$ECHO "\n=== next1 ===\n"
mor=`$ECHO "$out" |
  $AWK '{print $12}' |
                        $SED 's/[ =][0-9]+/ M /g' |
    $SORT |
      $UNIQ -c |
  $CAT`
#$ECHO "$mor"
$ECHO "\n=== next2 ===\n"
#$ECHO "$mor" | $GREP -v ' 1 '

$ECHO "\n=== signals\n"
$GREP 'got signal' $refiles
$ECHO "\n===\n"
$ECHO looked at $efiles
$ECHO and looked at $myfiles
$ECHO "In fact looked at $refiles"
