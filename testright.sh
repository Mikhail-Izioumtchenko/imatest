#!/bin/bash
ports="${1:-2}"
forhelp="$1"
verbose="${2:-0}"
seeds=""
[ -z "$3" ] || seeds="--seed $3"
echo "Usage: $0 [ports_rel [verbose_N [seed_N]]]"
echo "  so ports=$ports verbose=$verbose and seeds=$seeds"
[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = '-help' -o "$forhelp" = '-h' -o "$forhelp" = 'help' ] && exit 1
sleep 3
./hakillms.sh "$ports" 9 wait;\rm -r /root/mysql-sandboxes/*/sandboxdata/error.log /tmp/*;./startms.sh "$ports" wait;./imatest.sh now --test imatest.yaml --verbose "$verbose" --nodry-run $seeds 2>&1|tee /tmp/test.out; ./stopms.sh "$ports" wait
