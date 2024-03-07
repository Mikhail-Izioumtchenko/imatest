#!/bin/sh
# search logs, report
# 1: absolute port
forhelp="$1"
port="$1"

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 absolute_port_as_4202"
  $EXIT 1
}


ignore="Error:? +(200[236]|2013|1146|10(48|54|62|90|91)|12(10|64|65|92)|13(64|65)|1406|3105)[ :]"

efiles="/tmp/imatest.pl.out /tmp/load_thread_*.* /tmp/master_thread.log /tmp/imatest.out"
myfiles="/root/mysql-sandboxes/$port/*/error.log"

refiles=''
for i in $efiles $myfiles; do
  [ -f "$i" ] && refiles="$refiles $i" || echo "$i is not a regular file, ignore"
done

$ECHO "\n=== signals and croaks ===\n"
#$GREP 'got signal' $refiles
#$GREP 'CROAK' $refiles
$ECHO "\n===\n"

function process_file() {
  fil="$1"
  $ECHO "=== $fil ==="
  $CAT "$fil" | $GREP 'ERROR|Error' | $GREP -iv "$ignore" | $AWK '{print substr($0,1,440)}' | $SORT | $UNIQ -c | $SORT -n
}

for fil in $refiles ; do
  process_file "$fil"
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

$ECHO "\n=== signals and croaks ===\n"
$GREP 'got signal' $refiles
$GREP 'CROAK' $refiles
$ECHO "\n===\n"
$ECHO looked at $efiles
$ECHO and looked at $myfiles
$ECHO "In fact looked at $refiles"
