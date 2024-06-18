#!/bin/sh
### 1: subdirectory in /hardtmp
sub="$1"
forhelp="$1"
basedir='/hardtmp'
port='4'
boxdir="/root/mysql-sandboxes/420$port"

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 subdir_in_hardtmp"
  $EXIT 1
}

dir="$basedir/$sub"
[ -e "$dir" ] && {
    $ECHO "$dir already exists"
    $EXIT 1
}

$CP -R /tmp "$dir"

$CP -v $boxdir/*.cnf $boxdir/*/*.cnf $boxdir/*/error.log "$dir"

$ECHO "\nSee also $dir"

$EXIT 0
