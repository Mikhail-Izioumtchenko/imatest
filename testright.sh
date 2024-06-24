#!/bin/bash
export _IMATEST_USE='8.3'
#export _IMATEST_USE=''
ports="${1:-4}"
forhelp="$1"
verbose="${2:-0}"
seeds=""
[ -z "$3" ] || seeds="--seed $3"
yaml=""
tperl='imatest.pl'

. `pwd`/imavars.dot

[ -z "$4" ] || {
  yaml="--testyaml $4"
  tperl="`$DIRNAME $4`/$tperl"
}
echo "Usage: $0 [ports_rel [verbose_N [seed_N [imatest.yaml]]]]"
echo "  so ports=$ports verbose=$verbose seeds=$seeds testyaml=$yaml _IMATEST_USE=$_IMATEST_USE"
[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = '-help' -o "$forhelp" = '-h' -o "$forhelp" = 'help' ] && exit 1
sleep 3
./stopms.sh "$ports" wait;
\rm -rf /root/mysql-sandboxes/420$ports/sandboxdata/error.log /tmp/* /tmp/.fin;
\cp ./imatest.pl ./imatest.yaml ./imatest_syntax.yaml /tmp
echo "$0 #debug MYSQLSH=$MYSQLSH _IMATEST_USE=$_IMATEST_USE"
./startms.sh "$ports" wait;
./imatest.sh --file "$tperl" --use 8.3 now --test imatest.yaml --verbose "$verbose" --nodry-run $seeds $yaml 2>&1|tee /tmp/test.out;
./stopms.sh "$ports" wait
cp -v /root/mysql-sandboxes/420$ports/sandboxdata/error.log /tmp
