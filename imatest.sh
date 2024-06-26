#!/bin/sh
### exectute imatest.pl after setting the environment appropriately
### see usage
filebase='imatest.pl'
envbase='imavars.dot'

function usage() {
  echo -e "$*\n"
  cat <<EOF
Usage: $0 help | --help | [--use 8.3] [--env env_shell_script] [--test test_perl_script] [--log log_file_name] now [more...]
  help, --help: to see this message
  use: 8.3 to pass an indicator to env_shell_script to use local mysqlsh 8.3 environment, default empty string
    to use standard installation of mysqlsh
    currently $opuse
  env_shell_script: script to set the environment, default is cwd/$envbase,
    currently $vars
  test_perl_script: test script to run, default is cwd/$filebase,
    currently $fil
  log: log file pathname for STDOUT and STDERR of the perl script, default is IMATMPDIR/$filebase.out,
    currently $lof
  more...: passed as parameters to the test script
Example: $0 now
EOF
  exit 1
}

[ -z "$1" ] && usage "No options or parameters supplied, try $0 --help for more details"

opvars=''
opfil=''
oplof=''
opuse=''
while true ; do
  [ "$1" = 'help' -o "$1" = '--help' ] && {
    break
  }
  [ "$1" = 'now' ] && {
    shift
    break
  }
  [ "$1" = '--env' ] && {
    opvars="$2"
    shift 2
    continue
  }
  [ "$1" = '--file' ] && {
    opfil="$2"
    shift 2
    continue
  }
  [ "$1" = '--log' ] && {
    oplof="$2"
    shift 2
    continue
  }
  [ "$1" = '--use' ] && {
    opuse="$2"
    shift 2
    continue
  }
  [ -z "$1" ] && break || usage "Invalid options or parameters are supplied: $1"
done

export _IMATEST_USE=''
[ "$opuse" = '8.3' ] && export _IMATEST_USE="$opuse" || {
  [ -z "$_IMATEST_USE" ] || usage "--use '$opuse' is not supported, the only supported value is 8.3"
}

vars=${opvars:-`pwd`/$envbase}
[ ! -f "$vars" ] && usage "$vars is not set or not a regular file or inaccessible"

. "$vars"

[ -z "$IMASRCDIR" -o ! -d "$IMASRCDIR" ] && usage "IMASRCDIR=$IMASRCDIR is not set in '$vars' or not a directory or inaccessible"

fil=${opfil:-$IMASRCDIR/$filebase}
lof=${oplof:-$IMATMPDIR/$filebase.out}

[ "$1" = 'help' -o "$1" = '--help' ] && usage "help requested"

[ ! -f "$fil" ] && usage "$fil is not set or not a regular file or inaccessible"

$ECHO "see also $lof"
$SLEEP 1
$EXEC $PERL "$fil" --see-also "$lof" $* 2>&1 | $TEE "$lof"
