#!/bin/sh
### exectute imatest.pl after setting the environment appropriately
### see usage
filebase='imatest.pl'
envbase='imavars.dot'

function usage() {
  echo -e "$*\n"
  cat <<EOF
Usage: $0 [help | --help | [--env env_shell_script] [--test test_perl_script] [--log log_file_name] now [more...]]
  help, --help: to see this message
  env_shell_script: script to set the environment, default is cwd/$envbase,
    currently $vars
  test_perl_script: test script to run, default is cwd/$filebase,
    currently $fil
  log: log file pathname for STDOUT and STDERR of the perl script, default is IMATMPDIR/$filebase.out
  more...: passed as parameters to the test script
EOF
  exit 1
}

[ -z "$1" ] && usage "No options or parameters supplied"

opvars=''
opfil=''
oplof=''
while true ; do
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
  usage "Invalid options or parameters are supplied"
done


vars=${opvars:-`pwd`/$envbase}
[ ! -f "$vars" ] && usage "$vars is not set or not a regular file or inaccessible"

. "$vars"
[ -z "$IMASRCDIR" -o ! -d "$IMASRCDIR" ] && usage "IMASRCDIR=$IMASRCDIR is not set n '$vars' or not a directory or inaccessible"
fil=${opfil:-$IMASRCDIR/$filebase}
[ ! -f "$fil" ] && usage "$fil is not set or not a regular file or inaccessible"
lof=${oplof:-$IMATMPDIR/$filebase.out}
$ECHO "see also $lof"
$SLEEP 1
$EXEC $PERL "$fil" --see-also "$lof" $* 2>&1 | $TEE "$lof"
