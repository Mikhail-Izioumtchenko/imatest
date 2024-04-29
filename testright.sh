#!/bin/bash
#seeds="--seed 7"
verbose="${1:-0}"
seeds=""
[ -z "$2" ] || seeds="--seed $2"
echo "verbose=$verbose and seeds=$seeds", Usage: $0 [verbose_N [--seed N]]
sleep 3
./stopms.sh 2 wait;\rm -r /root/mysql-sandboxes/*/sandboxdata/error.log /tmp/*;./startms.sh 2 wait;./imatest.sh now --test imatest.yaml --verbose "$verbose" --nodry-run $seeds 2>&1|tee /tmp/imatest.out
