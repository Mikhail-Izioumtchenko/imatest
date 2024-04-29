#!/bin/bash
#seeds="--seed 7"
seeds=""
./stopms.sh 2,3 wait;\rm -r /root/mysql-sandboxes/*/sandboxdata/error.log /tmp/*;./startms.sh 2,3 wait;./imatest.sh now --test imatest.yaml --verbose 0 --nodry-run $seeds 2>&1|tee /tmp/imatest.out
