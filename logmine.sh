#!/bin/sh
# search logs, report

. `pwd`/imavars.dot

efiles="/tmp/imatest.pl.out /tmp/1.tmp /tmp/client_thread_*.* /tmp/master_thread.log /tmp/co.tmp"
myfiles="/root/mysql-sandboxes/4202/*/error.log"

out=`$CAT $efiles $myfiles |
#  $GREP 'ERROR|Warning|System' |
  $GREP 'ERROR' |
    $SED 's/[^[]*\[/[/' |
      $SED 's/\[//' |
        $SED 's/\[/:/g' |
          $SED 's/\]/:/g' |
            $SED 's/: :/_/g' |
              $SED 's/ERROR: /ERROR-/g' |
                $SED "s/doesn't/doesnot/g" |
                  $SED "s/[cC]an't/cannot/g" |
                    $SED "s/'[^']+'/__squoted_name__/g" |
                      $SED 's/\`[^\`]+\`/__squoted_name__/g' |
                        $SED 's/ [0-9]+/ _NNN/g' |
                          $SED 's/[(][0-9]+[)]/_pNNNp_/g' |
                            $SED 's/:/ /g' |
                              $SORT |
                                $UNIQ -c |
                                  $SORT -n |
  $CAT`
$ECHO "$out"
$ECHO "\n===\n"
mor=`$ECHO "$out" |
  $AWK '{print $2}' |
    $SORT |
      $UNIQ -c |
  $CAT`
$ECHO "$mor"
$ECHO "\n===\n"
$ECHO "$mor" |
  $GREP -v ' 1 '

$ECHO "\n=== signals\n"
$GREP 'got signal' $efiles $myfiles
$ECHO "\n===\n"
$ECHO looked at $efiles
$ECHO and looked at $myfiles
