#!/bin/bash
ports="${1:-2}"
forhelp="$1"
verbose="${2:-0}"
seeds=""
[ -z "$3" ] || seeds="--seed $3"
yaml=""
[ -z "$4" ] || yaml="--testyaml $4"
echo "Usage: $0 [ports_rel [verbose_N [seed_N [imatest.yaml]]]]"
echo "  so ports=$ports verbose=$verbose seeds=$seeds testyaml=$yaml"
[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = '-help' -o "$forhelp" = '-h' -o "$forhelp" = 'help' ] && exit 1
sleep 3
./hakillms.sh "$ports" 9 wait;
\rm -r /root/mysql-sandboxes/*/sandboxdata/error.log /tmp/* /tmp/.fin;
\cp ./imatest.pl ./imatest.yaml ./imatest_syntax.yaml /tmp
./startms.sh "$ports" wait;
./imatest.sh now --test imatest.yaml --verbose "$verbose" --nodry-run $seeds $yaml 2>&1|tee /tmp/test.out;
./stopms.sh "$ports" wait
