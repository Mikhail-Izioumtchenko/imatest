#!/bin/sh
### interactively connect to instance using mysql
### 1: mandatory relative standard protocol port
### 2... are passed to client
forhelp="$1"
port="$1"
more=''
[ -z "$port" ] || shift
[ -z "$1" ] || {
  fil="$1"
  [ "$fil" = 'file' ] && {
    sor="${2:-need_file}"
    more="--execute 'source $sor' --force"
  } || more="$*"
}

. `pwd`/imavars.dot

[ -z "$forhelp" -o "$forhelp" = 'h' -o "$forhelp" = 'help' ] && {
  $ECHO "Usage: $0 relative_port [file file2sourceWforce|passed to mysql]..."
  $EXIT 1
}

base="$IMAPORTBASE"
taport="$(($port + $base))"
pass=`$CAT "$IMAPAS"`

com="$MYSQL --port=$taport --user=root --host 127.0.0.1 --password=$pass $more"
#echo "$com";exit
eval "$com"
