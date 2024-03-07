use strict;
use warnings;
use English;

require 5.032;

# style: flexible, mostly per perldoc perlstyle
# M1. mandatory: no tabs, 4 blanks indentation
# M2. mandatory: no case statement, no camelCase
# 2. desirable: should look like C. Postfix if is OK and is preferred over postfix unless. 
# 3. so postfix if and unless are discouraged. If specified, should be on the same line as statement, if|unless (condition)
# 4. no postfix except for if and unless
# 5. blocks in {} even where a single statement after while or similar is allowed
# 6. desirable: single quotes unless string interpolation is used. So 'abc' not "abc".
# 7. comments start with single #, indent with code if on separate line
# 8. do avoid OO, do not use constant
# 9. 1+2 is OK, 1<2 is better written as 1 < 2
# 10. lowercase names except constants which should be all UPPERCASE
# 11. desirable: single return per sub but see value_generate_time() for treatment of unreachable code
# 12. use not and or for logical ops, instead of && etc.
# 13. longnamesnounderscores are fine, names_with are also OK
# 14. important: names of variables in the same scope should differ in at least two characters
# 15. important: array names start with l, hash names, with h. Globals start with g e.g. @glist
# 16. max source code line length is 143

# todo
# allow multiple destroyer threads
# REPLACE
# ANALYZE + histogram
# CHECKSUM
# OPTIMIZE
# FLUSH
# LOCK
# count distinct etc
# optional server shutdown in the end
# dry but less dry
# database discovery
# check 'x' for constants
# how group by
# more robust values esp. update 
# use $TRUE not $YES
# savepoints
# ddl
# set
# confuser syntax

use Carp qw(croak shortmess);
use Data::Dumper qw(Dumper);
use DateTime;
use Getopt::Long qw(GetOptions);
use IO::Handle;
use IPC::Open2 qw(open2);
use JSON qw(encode_json decode_json);
use List::Util qw(shuffle);
use POSIX qw(:sys_wait_h);
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);
use Time::HiRes qw(gettimeofday usleep);
use YAML qw(LoadFile);

STDOUT->autoflush();
STDERR->autoflush();

my $version = '2.58';

$Data::Dumper::Sortkeys = 1;

# constants. Do not use constant.
# UPPERCASE names
my $DRYRUN = 'dry-run';
my $HELP = 'help';
my $SEE_ALSO = 'see-also';
my $SEED = 'seed';
my $TESTYAML = 'testyaml';
my $VERBOSE = 'verbose';
my $VERBOSE_ANY = 0;
my $VERBOSE_SOME = 1;
my $VERBOSE_MORE = 2;
my $VERBOSE_DEV = 3;
my $VERBOSE_NEVER = 4;      # still can be passed
my $VERSION = 'version';

my $USAGE_ERROR_EC = 1;
# for internal subroutines
my $RC_ZERO = 0;
my $RC_OK = 1;      # not 0
my $RC_WARNING = 2;      # not 0
my $RC_ERROR = 3;      # not 0
my $RC_DIE = 4;
my %GHRC = (
    0 => 'RC_ZERO',
    1 => 'RC_OK',
    2 => 'RC_WARNING',
    3 => 'RC_ERROR',
    4 => 'RC_DIE',
           );
# for external commands
my $EC_OK = 0;
my $EC_ERROR = 1;

my $TRUE = 1;
my $FALSE = 0;

my $CHECKFILE = 'to_check_file';

my $FDEC = "%05d";

my $DEC_RANGE_MARKER = 'D';
my $INT_RANGE_MARKER = 'I';
my $NEG_MARKER = 'M';

my $ALTER = 'ALTER';
my $BEGIN = 'BEGIN';
my $CHARACTER_SET = 'character_set';
my $CHECK_SUBKEYS = '_2levelkeys';
my $CREATE_CREATE = 'create_create';
my $CREATE_DB = 'create_db';
my $DATETIME = 'DATETIME';
my $DATATYPE_LOB_KEY_LEN = 'datatype_lob_key_len';
my $DECIMAL = 'DECIMAL';
my $DEFAULT = 'default';
my $DEFAULTUC = 'DEFAULT';
my $DESTROY_DESTROY = 'destroy_destroy';
my $EIGHT = 8;
my $EMPTY = 'EMPTY';
my $END = 'END';
my $EXPRESSION_GROUP = 'expression_group';
my $INSERT = 'insert';
my $INTEGER = 'INTEGER';
my $JSON = 'JSON';
my $LOAD_THREAD_CLIENT_LOG = 'load_thread_client_log';
my $LOAD_THREAD_CLIENT_LOG_ENV = '_imatest_client_log';
my $LOB = 'LOB';
my $MYSQLSH_RUN_FILE = 'mysqlsh_run_file';
my $MYSQLSH_EXEC = 'mysqlsh_exec';
my $NEEDS_ON_TRUE = 'needs_on_true';
my $NO = 'No';
my $NUMBER_REVERSE_SIGN_LEGITIMATE_P = 'number_reverse_sign_legitimate_p';
my $NUMBER_REVERSE_SIGN_ILLEGITIMATE_P = 'number_reverse_sign_illegitimate_p';
my $ONLY_NAMES = 'only_names';
my $ONLY_NON_NEGATIVE_INTEGERS = 'only_non_negative_integers';
my $ONLY_POSITIVE_INTEGERS = 'only_positive_integers';
my $ONLY_VALUES_ALLOWED = 'only_values_allowed';
my $OPERATOR_LOGICAL = 'operator_logical';
my $PARENTHESIS = 'parenthesis';
my $RAND = 'rand';
my $RECREATE = 'create_server';
my $SERVER_START = 'server_start';
my $RSEED = 'rseed';
my $SELECT_COLUMN_P = 'select_column_p';
my $SERVER_TERMINATION_WAIT_TIMEOUT = 'server_termination_wait_timeout';
my $SHUTKILL = 'shutkill';
my $SIGSTOP = 'sigstop';
my $SPATIAL = 'SPATIAL';
my $STRANGE = 'STRANGE';
my $STRING_TRUE = 'True';
my $SUPPORTED = 'supported';
my $TEARDOWN = 'teardown';
my $TEST_DURATION = 'test_duration_seconds';
my $TO_BUILD = 'to_build';
my $UKIND = '_k_';
my $UPDATE = 'UPDATE';
my $UPDATELC = 'update';
my $UPDATE_COLUMN_P = 'update_column_p';
my $V3072 = 3072;
my $V4326 = 4326;
my $VALUE_POINT_X = 'value_point_x';
my $VALUE_POINT_Y = 'value_point_y';
my $VALUE_POLYGON_LEN = 'value_polygon_len';
my $VIRTUAL = 'virtual';
my $VKCHAR = 'value_kchar_length_adjust_p';
my $WHERE = 'where';
my $YES = 'Yes';

my @LOPT = ("$DRYRUN!", "$HELP!", "$TESTYAML=s", "$SEE_ALSO=s", "$SEED=i", "$VERBOSE=i", "$VERSION!");
my %HDEFOPT = ("$DRYRUN" => 0, $HELP => 0, $VERBOSE => 0, $VERSION => 0);      # option defaults

# globals of sorts
my $gstrj;
my $gdosayoff = 2;
my %ghasopt = ();      # resulting options values hash
my %ghver = ();      # syntax checker hash
my %ghtest = ();      # test script hash
my %ghreal = ();      # test script hash with Rseq and similar processed e.g. 1-7 becomes e.g. 4
my %ghdt2class = ();      # datatype => class
my $gntables = 0;         # number of tables successfully create or discovered in all schemas
my %ghsql2stats = ();      # INSERT => N
# start schema related
my @glstables = ();         # list of all schema.table USED generate DML
my %ghcreate_schemas = ();      # schema name => create test schema SQL, may contain DROP
my %ghs2ntables = ();      # schema name => number of tables
my %ghs2pltables = ();      # schema name => ref array table names
# end schema related
# start schema.table hashes
my %ghst2ncolspk = ();      # schema.table => number of pk cols NU
my %ghst2needvcols = ();      # schema.table => number of virtual cols needed NU
my %ghst2hasvcols = ();      # schema.table => number of virtual cols has NU
my %ghst2ncolsnp = ();      # schema.table => number of non pk cols NU
my %ghst2cols = ();      # schema.table => ref array column names # USED by ALTER and DML
my %ghst2createtable = ();      # schema.table => CREATE TABLE without CREATE TABEL name itself, USED by ALTER
my %ghst2nvcols = ();      # schema.table => ref array column names for non virtual columns USED DML
my %ghst2mayautoinc = ();      # schema.table => may have autoinc column NU
my %ghst2hasautoinc = ();      # schema.table => does have autoinc column NU
my %ghst2pkautoinc = ();      # schema.table => does have autoinc column and it is PK NU
my @ghstlist = (
\%ghst2createtable,
\%ghst2ncolspk,
\%ghst2needvcols,
\%ghst2hasvcols,
\%ghst2ncolsnp,
\%ghst2cols,
\%ghst2nvcols,
\%ghst2mayautoinc,
\%ghst2hasautoinc,
\%ghst2pkautoinc
               );
# end schema.table hashes
# start schema.table.column hashes
my %ghstc2class = ();      # schema.table.column => column datatype class USED todo
my %ghstc2dt = ();      # schema.table.column => column datatype, uniqueness etc NU
my %ghstc2just = ();      # schema.table.column => column datatype, just it USED
my %ghstc2srid = ();      # schema.table.column => SRID or 0 USED
my %ghstc2cannull = ();      # schema.table.column => column nullability USED
my %ghstc2canfull = ();      # schema.table.column => can be part of fulltext index USED todo
my %ghstc2len = ();      # schema.table.column => column length if specified USED
my %ghstc2virtual = ();      # schema.table.column => column is virtual USED
my %ghstc2unsigned = ();      # schema.table.column => column is unsigned USED
my %ghstc2isautoinc = ();      # schema.table.column => is autoinc USED
my %ghstc2candefault = ();      # schema.table => can have DEFAULT NU
my %ghstc2hasdefault = ();      # schema.table => has DEFAULT USED
my @ghstcolist = (
\%ghstc2hasdefault,
\%ghstc2class,
\%ghstc2dt,
\%ghstc2just,
\%ghstc2srid,
\%ghstc2cannull,
\%ghstc2canfull,
\%ghstc2len,
\%ghstc2virtual,
\%ghstc2unsigned,
\%ghstc2isautoinc,
\%ghstc2candefault,
                 );
# end schema.table.column hashes
my %ghmisc = ();         # e.g. mysqlsh_exec => invocation line prefix
my @glpids;      # process ids of load threads

# used to generate JSON values
my %gh2json = (
'a' => $gdosayoff ,
'b' => \%ghasopt ,
'c' => \%ghst2cols ,
#'e' => \%ghreal ,
#'q' => \%ghver ,
#'w' => \%ghtest ,
'r' => $gntables ,
't' => \@glstables ,
's' => \%ghcreate_schemas ,
'd' => \%ghs2ntables ,
'f' => \%ghst2ncolspk ,
'g' => \%ghst2needvcols ,
'z' => \%ghst2hasvcols ,
'x' => \%ghst2ncolsnp ,
'v' => \%ghst2nvcols ,
'p' => \%ghstc2class ,
#'o' => \%ghstc2dt ,
'7' => \%ghstc2just ,
'i' => \%ghstc2cannull ,
'u' => \%ghstc2canfull ,
'y' => \%ghstc2len ,
'l' => \%ghstc2virtual ,
'k' => \%ghstc2unsigned ,
'h' => \%ghst2mayautoinc ,
'm' => \%ghst2hasautoinc ,
'n' => \%ghst2pkautoinc ,
'1' => \%ghstc2isautoinc ,
'3' => \%ghs2pltables ,
#'4' => \%ghmisc ,
'6' => \@glpids,
$RAND => 0
);

$ghmisc{$VERSION} = $version;

# parameters: usage message, __LINE__
# exits with USAGE_ERROR_EC
sub usage {
    my $msg = $ARG[0];
    $msg = "line $ARG[1]: $msg" if (defined($ARG[1]));
    $msg .= "\nversion $ghmisc{$VERSION}" if (defined($ghasopt{$VERSION}) and $ghasopt{$VERSION});
    my $usage = <<EOF
  $msg
  Usage: $EXECUTABLE_NAME $PROGRAM_NAME option...
    --$HELP show this message and exit
    --[no]$DRYRUN optional, run no test if supplied, just check test file syntax
    --$TESTYAML test_script.yaml: mandatory
    --$SEED integer: optional random seed, passed to srand(), no default
    --$VERBOSE integer: optional verbosity level, 0 is default, reasonable messaging.
        1 means more verbose
        2 means quite verbose
        3 very verbose, mostly for internal development use
        4 or more extremely verbose
    --$SEE_ALSO string: optional, this string is output at the end of the run.
    --$VERSION: show script version and exit
EOF
    ;
    dosayif($VERBOSE_ANY, "%s", $usage);
    croak("usage() called. CROAK.");
}

# 1: file to unlink
sub safe_unlink {
    my @l2unlink = @ARG;
    return if ($ghasopt{$DRYRUN});
    foreach my $tounlink (@l2unlink) {
        if (-f $tounlink or -p $tounlink) {
            unlink($tounlink);
            dosayif($VERBOSE_ANY,"removed file $tounlink");
        } else {
            dosayif($VERBOSE_ANY,"cannot remove, not a regular file nor pipe or file does not exist: $tounlink");
        }
    }
}

# 1: sleep time in milliseconds
# returns: whatever usleep returns or sleep time if --dry-run
sub dosleepms {
    my $slep = $ARG[0];
    return $ghasopt{$DRYRUN}? $slep : usleep($slep*1000);
}

# 1: sleep time in seconds
# returns: whatever sleep returns or sleep time if --dry-run
sub dosleep {
    my $slep = $ARG[0];
    return $ghasopt{$DRYRUN}? $slep : sleep($slep);
}

# 1: text file pathname
# returns file contents
# dies on error
sub readfile {
    my $fn = $ARG[0];
    dosayif($VERBOSE_MORE," called with %s",$fn);
    open(my $fh, '<', $fn) or croak("failed to open $fn for reading. CROAK.");
    my $rc = '';
    while (my $lin = <$fh>) {
        $rc .= $lin;
    }
    return $rc;
}

# 1: string to eval
# 2: eval as list if TRUE
# 3: silent
# returns: eval result. Will not make sense on eval error.
# on eval error prints helpful message and returns undef
sub doeval {
    local $EVAL_ERROR;
    my $toeval = $ARG[0];
    croak("Trying to evaluate an undefined value. CROAK") if (not defined($toeval));
    my $aslist = defined($ARG[1])? $ARG[1] : $FALSE;
    my $howver = (defined($ARG[2]) and $ARG[2])? $VERBOSE_NEVER : $VERBOSE_ANY;
    dosayif($VERBOSE_MORE, "is called with %s",  $toeval);
    my $rc = undef;
    if ($aslist) {
        my @lirc = eval($toeval);
        $rc = \@lirc;
    } else {
        $rc = eval($toeval);
    }
    if ($EVAL_ERROR ne '') {
      dosayif($howver, " returning undef: error evaluating '%s' : %s",  $toeval, $EVAL_ERROR);
      return undef;
    }
    dosayif($VERBOSE_DEV,"of %s returning %s",  $toeval, Dumper($rc));
    return $rc;
}

# 1: shell command to execute
# returns (exit_code, ref array output)
sub readexec {
    my $com = $ARG[0];
    dosayif($VERBOSE_SOME," called with %s",$com);
    my $fdout;
    my $pid = eval('open2($fdout, my $fdin, $com)');
    my @lres = ();
    while (my $lin = <$fdout>) {
        push(@lres,$lin);
    }
    waitpid($pid,0);
    my $ec = $CHILD_ERROR >> $EIGHT;
    my $rc = $ec == $EC_OK? $RC_OK : $RC_ERROR;
    dosayif($VERBOSE_SOME," execution of %s exit code %s returning %s",$com,$ec,$rc);
    return ($ec, \@lres);
}

# 1: verbosity level, prints out stuff only if --verbose >= that
# 2: format
# 3... : arguments
# prints the message prepending by something helpful
# returns whatever printf returns
sub dosayif {
    my $howver = shift @ARG;
    return if defined($ghasopt{$VERBOSE}) and $ghasopt{$VERBOSE} < $howver;
    my ($format, @largs) = @ARG;
    my $res = shortmess();
    my @l = split(/\n/,$res);
    $res = defined($l[$gdosayoff])? $l[$gdosayoff] : 'main';
    $res =~ s/\(.*//;
    $res =~ s/.*://;
    $res = 'main' if ($res eq 'dosayif');
    my $doformat = "#P %s %s %s %s: $format\n";
    my $dt = DateTime->now(time_zone => 'UTC');
    my ($sec, $mks) = gettimeofday();
    my $dout = sprintf("%s %s.%06d %s", $dt->ymd(), $dt->hms(), $mks, $dt->time_zone_short_name());
    printf($doformat, $PID, $dout, $PROGRAM_NAME, $res, @largs);
}

# 1: range or value as ref array as 1I 2 0.1 1D 2 0.1 or 1 1.0. 3d element is ignored.
sub process_range {
    my $plval = $ARG[0];
    my $rc = '';
    dosayif($VERBOSE_DEV,"called with %s",Dumper($plval));
    if (scalar(@$plval) == 2) {
        # not a range, use this value
        $rc = $plval->[0];
        dosayif($VERBOSE_DEV,"not range, just use it: %s",  $rc);
    } else {
        # range
        my $valst = $plval->[0];
        my $valend = $plval->[1];
        my $irange = ($valst =~ /I$/) ? $INT_RANGE_MARKER : $DEC_RANGE_MARKER;
        $valst =~ s/.$//;
        if ($valend < $valst) {
            dosayif($VERBOSE_ANY, "WARNING: reversing range order to %s %s",$valend,$valst);
            my $x = $valend;
            $valend = $valst;
            $valst = $x;
        }
        my $lr = $valend-$valst+1;
        $irange eq $DEC_RANGE_MARKER and $lr = $valend - $valst;
        dosayif($VERBOSE_DEV,"we have %s range %s to %s, length %s for %s",  $irange, $valst,$valend,$lr,Dumper($plval));
        $rc = $irange eq $INT_RANGE_MARKER? $valst + int(rand($lr)) : $valst + rand($lr);
        dosayif($VERBOSE_DEV,"for this range we return %s",$rc);
    }
        
    dosayif($VERBOSE_MORE,"of '%s' returns %s","@$plval",$rc);
    return $rc;
}

# 1: key in test scripr hash
# 2: 1 or not defined: quiet, 0: report a little
# 3: 1: check, do not necessarily calculate the random outcome of Rseq
#    0 or not defined: just calculate, try to avoid checking toil
# side effect: sets part of ghreal unless check only
# be careful with rule numbering which is not sequential nor numeric
#    current last rule is 9
# on error calls usage
# on success returns the value chosen
# not perfect which is OK: some values are only checked when they are chosen
sub process_rseq {
# val is Rseq kind of value, $skey is top level hash key e.g. "schemas"
    my $skey = $ARG[0];
    croak("internal error: '$skey' is not an Rseq test parameter") if (not defined($ghreal{$skey}));
    my $silent = defined($ARG[1])? $ARG[1] : $TRUE;
    my $check = defined($ARG[2])? $ARG[2] : $FALSE;
    my $verbose = $silent? $VERBOSE_NEVER : $VERBOSE_DEV;
    my $val = $ghtest{$skey};
    my $phverk = $ghver{$skey};
    croak("$skey +$val+$skey+is not in test description file or not Rseq. CROAK.") if ($check and not defined($phverk));
    my $rc = $RC_OK;
    my ($only_positive_integers, $only_non_negative_integers, $only_names, $only_values_allowed) =
         $check ?
           ($phverk->{$ONLY_POSITIVE_INTEGERS}, $phverk->{$ONLY_NON_NEGATIVE_INTEGERS}, $phverk->{$ONLY_NAMES},
            $phverk->{$ONLY_VALUES_ALLOWED}) :
           ($FALSE, $FALSE, $FALSE, $phverk->{$ONLY_VALUES_ALLOWED});

    # proactive values check
    if ($check) {
        if (defined($only_values_allowed)) {
            # Rule9: value list
            my @lal = split(/,/,$only_values_allowed);
            my @lsup = defined($phverk->{$SUPPORTED})? split(/,/,$phverk->{$SUPPORTED}) : @lal;
            my $clval = $val;
            $clval =~ s/:[0-9.]*([,!])/$1/g;
            my @lhave = split(/[,!]/,$clval);
            foreach my $el (@lhave) {
                $el =~ s/\(@[A-Z@;(}]+\)/()/ if ($el =~ /\(@/);
                usage("$skey subvalue $el violates Rseq Rule9: with $ONLY_VALUES_ALLOWED value must be one of: @lal",__LINE__)
                  if (scalar(grep {$_ eq $el} @lal) == 0);
            }
            $clval =~ s/!.*//;
            my @lsohave = split(/,/,$clval);
            foreach my $el (@lsohave) {
                $el =~ s/\(@[A-Z@;(}]+\)/()/ if ($el =~ /\(@/);
                usage("$skey subvalue $el violates Rseq Rule10: with '$SUPPORTED' value must be one of: @lsup",__LINE__)
                  if (scalar(grep {$_ eq $el} @lsup) == 0);
            }
        }
    }
    # process cutoff
    if ($val =~ /!/) {
        # todo oversimiplified
        $val =~ s/:[.0-9]+!/!/;
        $val =~ s/!.*//;
        $ghtest{$skey} = $val;
    }
    my @lcommas = split(/,/, $val);
    my $n = 0;
    my %hcomma = ();
    my $hasprobs = 0;
    my $lastprob = 0;
    foreach my $lcom (@lcommas) {
        ++$n;
        my @lsem = split(/:+/, $lcom);
        # Rule1: not more than one probability per item
        usage("$skey value $val violates Rseq Rule1: not more than one probability per item",__LINE__) if ($check and scalar(@lsem) > 2);
        # Rule3: range nor probability can be empty
        usage("$skey value $val violates Rseq Rule3: no empty ranges or probabilities",__LINE__)
          if ($check and ($lsem[0] eq '' or (scalar(@lsem) == 2 and $lsem[1] eq '')));
        $hasprobs += (scalar(@lsem) - 1);
        $lastprob = scalar(@lsem) - 1;
        $lastprob == 0 and push(@lsem,1.0);
        my $ls1 = shift(@lsem);
        my @lrange = split(/\/+/, $ls1);
        if (scalar(@lrange) == 2) {
            # Rule7: wrong character in decimal range
            usage("$skey value $val violates Rseq Rule7: in decimal ranges are allowed only characters 0-9 / M .",__LINE__)
              if ($check and join('',@lrange) =~ /[^-\/0-9M.]/);
            # Rule7.1: no decimal ranges allowed for only_positive_integers
            usage("$skey value $val violates Rseq Rule7.1: $skey only supports integers",__LINE__)
              if ($only_positive_integers || $only_non_negative_integers);
            # Rule7.2: no decimal ranges allowed for only_names
            usage("$skey value $val violates Rseq Rule7.2: $skey only supports names",__LINE__)
              if ($only_names);
            $lrange[0] .= $DEC_RANGE_MARKER;
            unshift(@lsem, @lrange);
        } else {
            @lrange = split(/-+/, $ls1);
            if (scalar(@lrange) == 1) {
                # single value, number or string
                unshift(@lsem, @lrange);
            } elsif (scalar(@lrange) == 2) {
                # Rule5: empty subrange
                usage("$skey value $val violates Rseq Rule5: empty subranges are not allowed",__LINE__) if ($check and $lrange[0] eq '');
                # Rule6: wrong character
                usage("$skey value $val violates Rseq Rule6: in integer ranges are allowed only characters 0-9 - M ",__LINE__)
                  if ($check and join('',@lrange) =~ /[^-0-9M]/);
                usage("$skey value $val violates Rseq Rule6.1: $skey only supports positive integers",__LINE__)
                  if ($only_positive_integers && (join('',@lrange) =~ /M/ || $lrange[0] == 0));
                usage("$skey value $val violates Rseq Rule6.1: $skey only supports non negative integers",__LINE__)
                  if ($only_non_negative_integers && join('',@lrange) =~ /M/);
                # Rule7.2: no integer ranges allowed for only_names
                usage("$skey value $val violates Rseq Rule6.2: $skey only supports names",__LINE__)
                  if ($only_names);
                $lrange[0] .= $INT_RANGE_MARKER;
                unshift(@lsem, @lrange);
            } else {
                # Rule4: too many subranges
                usage("$skey value $val violates Rseq Rule4: only two subranges allowed",__LINE__);
            }
        }
        @lsem = map {s/^$NEG_MARKER/-/;$_} @lsem
          if (not defined($only_values_allowed));
        $hcomma{sprintf($FDEC,$n)} = \@lsem;
    }
    # Rule2: if there is a probability, all but the last one must have it
    dosayif($silent, "%s line+%s+to+%s+of+%s+to+%s+hasprobs+%s+lastprob+%s+\n",
       $val,"@lcommas", scalar(@lcommas), Dumper(\%hcomma),$hasprobs,$lastprob);
    usage("$skey value $val violates Rseq Rule2: either no probabilities or each element but last must have probability",__LINE__)
      if ($check and (($lastprob == 1 || $hasprobs != scalar(@lcommas) - 1) && $hasprobs != 0));

    dosayif($silent,"%s to process %s: %s, lcommas is %s, hasprobs=%s, hcommas is %s",
      $skey,$val,"@lcommas",$hasprobs,Dumper(\%hcomma));
    my $pltopr = [];
    if ($hasprobs == 0) {
        # list of equiprobable values or ranges
        my $nl = int(rand(scalar(@lcommas)));
        $pltopr = $hcomma{sprintf($FDEC,$nl+1)};
    } else {
        # we have probabilities, go through the hash to choose a random value
        foreach my $k (sort(keys(%hcomma))) {
            my $plval = $hcomma{$k};
            my $prob = $plval->[scalar(@$plval)-1];
            my $ran = rand();
            dosayif($silent,"rand is %s and prob is %s for %s",$ran,$prob,Dumper($plval));
            $ran < $prob or next;
            dosayif($silent,"for %s we choose %s",$skey,Dumper($plval));
            $pltopr = $plval;
            last;
        }
    }
    if (scalar(@$pltopr) == 2) {      # not range, single value and probability
        if ($only_names || $only_values_allowed) {
            # Rule8: string is in fact a name but also ()
            usage(
              "$skey value $val violates Rseq Rule8: for $ONLY_NAMES and $ONLY_VALUES_ALLOWED first character must be [a-zA-Z_]",__LINE__)
              if ($check and (not $pltopr->[0] =~ /^[a-zA-Z_(]/));
        }
        # Rule6: wrong character
        usage("$skey value $val violates Rseq Rule6.3: $skey only supports positive integers",__LINE__)
          if ($only_positive_integers && (join('',@$pltopr) =~ /M/ || $pltopr->[0] <= 0));
        usage("$skey value $val violates Rseq Rule6.4: $skey only supports non negative integers",__LINE__)
          if ($only_non_negative_integers && join('',@$pltopr) =~ /M/);
    }
    $ghreal{$skey} = process_range($pltopr);

    return $ghreal{$skey};
}

# 1: arrayref of text, newlines will be added
# 2: filename to open for writing including > or >>
# returns RC_OK
# dies on error
sub tlist2file {
    my ($pltext, $fil) = @ARG;
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY,"is invoked for %s",  $fil);
    dosayif($VERBOSE_MORE, "is invoked for %s to write %s",  $fil, Dumper($pltext));

    open(my $fh, $fil) or croak("failed to open $fil. CROAK.");
    foreach my $lin (@$pltext) {
        printf $fh "%s\n", $lin;
    }
    close($fh);

    dosayif($VERBOSE_ANY,"for %s returns %s",  $fil, $rc);
    return $rc;
}

# no args
# side effect: sets ghver
# on error calls usage
# on success returns RC_OK
sub checkscript {
    my $testyaml = $ghasopt{$TESTYAML};
    my $rc = $RC_OK;
    my $phv;
    if (defined($ghtest{$CHECKFILE})) {
        -f $ghtest{$CHECKFILE} or usage("$ghtest{$CHECKFILE}: file does not exist, or inaccessible, or not a regular file",__LINE__);
        $phv = doeval("LoadFile('$ghtest{$CHECKFILE}')") or die "bad yaml in file $ghtest{$CHECKFILE}";
    } else {
        usage("'$CHECKFILE' must be supplied",__LINE__);
    }
    %ghver = %$phv;
    dosayif($VERBOSE_DEV, "% start: %s\n%s end", $CHECKFILE, Dumper(\%ghver), $CHECKFILE);
    my $strict = $ghtest{'strict'};
    # check strict
    foreach my $skey (keys(%ghtest)) {
        if ($strict eq $STRING_TRUE and not defined($ghver{$skey})) {
            if ($skey =~ /$UKIND/) {
                my $suf = $skey;
                $suf =~ s/.*$UKIND//;
                my @lok = @{$ghtest{'strict_exceptions'}};
                usage("strict is specified in $TESTYAML but $skey is not described in $CHECKFILE '$ghtest{$CHECKFILE}' and $suf is not in strict_exceptions of '@lok'",
                  __LINE__)
                    if (scalar(grep {$_ eq $suf } @lok) == 0);
            } else {
                usage("strict is specified in $TESTYAML but $skey is not described in $CHECKFILE '$ghtest{$CHECKFILE}'",__LINE__);
            }
        }
    }
    # check subkeys
    if (defined($ghver{$CHECK_SUBKEYS})) {
        my %hcheck = ();
        foreach my $allowed (@{$ghver{$CHECK_SUBKEYS}}) {
            ++$hcheck{$allowed};
        }
        my %hsub = ();
        foreach my $key (keys(%ghver)) {
            next if ($key eq $CHECK_SUBKEYS);
            my $ph = $ghver{$key};
            foreach my $suk (keys(%$ph)) {
                ++$hsub{$suk};
            } 
        }
        foreach my $have (keys(%hsub)) {
            croak(
 "$CHECK_SUBKEYS='@{$ghver{$CHECK_SUBKEYS}}' is defined in $CHECKFILE '$ghtest{$CHECKFILE}' but '$have' is not there. CROAK.")
              if (not defined($hcheck{$have}));
        }
    }
    foreach my $skey (sort(keys(%ghver))) {
        next if ($skey eq $CHECK_SUBKEYS);
        my $phcheck = $ghver{$skey};
        if (not defined($ghtest{$skey})) {
            next if not defined($phcheck->{'mandatory'});;
            usage("$skey is mandatory but it is not defined in $testyaml",__LINE__);
        }
        my $val = $ghtest{$skey};
        dosayif($VERBOSE_DEV, " checking %s of '%s'",  $skey, $val);
        if ($val eq $STRING_TRUE and defined($phcheck->{$NEEDS_ON_TRUE})) {
            foreach my $scheck (@{$phcheck->{$NEEDS_ON_TRUE}}) {
                usage("$skey is $val and $NEEDS_ON_TRUE includes $scheck but $scheck is not defined in $testyaml",__LINE__)
                  if (not defined($ghtest{$scheck}));
            }
        }
        my $vcheck = $phcheck->{'allowed'};
        if (ref($vcheck) eq 'ARRAY') {
            scalar(grep{$val eq $_} @$vcheck) > 0 or usage("$skey cannot be $val but rather one of: @{$vcheck}",__LINE__);
            my $vsup = $phcheck->{$SUPPORTED};
            scalar(grep{$val eq $_} @$vsup) > 0 or usage("$skey of $val is not supported yet. Supported values are @{$vsup}",__LINE__);
            next;
        }
        if (defined($vcheck) and $vcheck eq 'doeval') {
            my $ev = doeval($ghtest{$skey});
            if (not defined($ev)) {
                croak("$skey of $ghtest{$skey} in $testyaml failed to evaluate. CROAK.");
            }
            $ghreal{$skey} = $ev;
            dosayif($VERBOSE_MORE, "by doeval set %s to '%s' of ref %s",$skey,$ev,ref($ev));
            next;
        }
        if (defined($vcheck) and $vcheck eq 'doeval_list') {
            my $ev = doeval($ghtest{$skey}, $TRUE);
            if (not defined($ev)) {
                croak("$skey of $ghtest{$skey} in $testyaml failed to evaluate. CROAK.");
            }
            $ghreal{$skey} = $ev;
            dosayif($VERBOSE_MORE, "by doeval_list set %s to '%s' of ref %s",$skey,$ev,ref($ev));
            next;
        }
        if (defined($vcheck) and $vcheck eq $ONLY_NON_NEGATIVE_INTEGERS) {
            usage("$skey of $val is wrong, must be a non negative integer",__LINE__)
              unless (looks_like_number($val) and $val >= 0 and int($val) == $val);
            next;
        }
        if (defined($vcheck) and $vcheck eq $ONLY_POSITIVE_INTEGERS) {
            usage("$skey of $val is wrong, must be a positive integer",__LINE__)
              unless (looks_like_number($val) and $val > 0 and int($val) == $val);
            next;
        }
        if (defined($vcheck) and $vcheck eq 'probability') {
            usage("$skey of $val is wrong, must be a probability value between 0.0 and 1.0 inclusive",__LINE__)
              unless (looks_like_number($val) and $val >= 0.0 and $val <= 1.0);
            next;
        }
        if (defined($vcheck) and $vcheck eq 'Rseq') {
            process_rseq($skey, $TRUE, $TRUE);      # quiet, just check
            next;
        }
    }

    dosayif($VERBOSE_ANY, "Test script %s is syntactically correct", $ghasopt{$TESTYAML});

    dosayif($VERBOSE_ANY, "returns %s",  $rc);
    return $rc;
}

sub buildmisc {
    my $password = readfile($ghreal{'passfile'});
    chop($password);
    my $port = $ghreal{'ports'} + $ghreal{'xportoffset'};
    my $myport = $ghreal{'ports'} + $ghreal{'mportoffset'};
    $ENV{'_imatest_port_rel'} = $ghreal{'ports'};
    # absolute old (not x) port number
    $ENV{'_imatest_port_abs'} = $ghreal{'ports'} + $ghreal{'mportoffset'};
    $ghmisc{'mysqlsh_base'} = sprintf(
"%s --host=%s --port=%s --user=%s --password=%s --sqlx --show-warnings=true --result-format=json --quiet-start=2 --log-sql=all --verbose=1",
                               $ghreal{'mysqlsh'},$ghreal{'hosts'},$port,$ghreal{'user'},$password);
    $ghmisc{'mysql_base'} = sprintf(
"%s --host=%s --port=%s --user=%s --password=%s --force --compression-algorithms=zstd --no-beep --unbuffered --quick  --batch --verbose",
                               $ghreal{'mysql'},$ghreal{'hosts'},$myport,$ghreal{'user'},$password);
    $ghmisc{$MYSQLSH_RUN_FILE} = "$ghmisc{'mysqlsh_base'} --force --log-file $ENV{$LOAD_THREAD_CLIENT_LOG_ENV} --file";
    $ghmisc{$MYSQLSH_EXEC} = "$ghmisc{'mysqlsh_base'} --log-file $ENV{$LOAD_THREAD_CLIENT_LOG_ENV} --execute";
    $ENV{'_imatest_mysql_static_cnf'} = join(' ',split("\n",$ghreal{'mysql_static_cnf'}));
    my @lcla = split(/,/,$ghreal{'datatype_class2dt'});
    foreach my $clas (@lcla) {
        my @l2 = split(/:/,$clas);
        my @ldt = split(/-/,$l2[1]);
        foreach my $dat (@ldt) {
            $ghdt2class{$dat} = $l2[0];
        }
    }
    return $RC_OK;
}

# no args
# rc RC_OK: recreated successfully ir recreate is false
#    RC_ERROR recreation failed
# may call usage() on some errors
sub process_recreate {
    my $recreate = $ghreal{$RECREATE};
    my $rc = $RC_OK;
    dosayif($VERBOSE_SOME,"invoked with $RECREATE %s",$recreate);
    if (not $recreate eq $STRING_TRUE) {
        $rc = $RC_ZERO;
        dosayif($VERBOSE_ANY,"%s is FALSE so doing nothing but return %s", $RECREATE, $rc);
        return $rc;
    }

    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY,"returning %s because of --%s", $rc, $DRYRUN);
        return $rc;
    }

    my $ec = doeval("system(\"$ghreal{$CREATE_CREATE}\")");
    dosayif($VERBOSE_ANY," execution of %s='%s' resulted in exit code %s",$CREATE_CREATE,$ghreal{$CREATE_CREATE},$ec);

    $rc = $ec == $EC_OK? $RC_OK : $RC_ERROR;
    dosayif($VERBOSE_ANY," returning %s",  $rc);
    return $rc;
}

# no args
# rc RC_ZERO: teardown is FALSE
#    RC_OK: teardown succeeded
#    RC_ERROR teardown failed
sub process_teardown {
    my $teardown = $ghreal{$TEARDOWN};
    my $rc = $RC_DIE;
    dosayif($VERBOSE_ANY,"invoked with %s=%s", $TEARDOWN, $teardown);
    if (not $teardown eq $STRING_TRUE) {
        $rc = $RC_ZERO;
        dosayif($VERBOSE_ANY," $TEARDOWN is FALSE so doing nothing but return %s",  $rc);
        return $rc;
    }
    usage("$TEARDOWN is TRUE but $DESTROY_DESTROY is not defined in $ghasopt{$TESTYAML}",__LINE__)
      if (not defined($ghreal{$DESTROY_DESTROY}));

    if ($ghasopt{$DRYRUN}) {
        $rc = $RC_OK;
        dosayif($VERBOSE_ANY," returning %s because of --$DRYRUN",  $rc);
        return $rc;
    }

    my $ec = doeval("system(\"$ghreal{$DESTROY_DESTROY}\")");
    dosayif($VERBOSE_ANY,"execution of %s of '%s' resulted in exit code %s",$DESTROY_DESTROY,$ghreal{$DESTROY_DESTROY},$ec);

    $rc = $ec == $EC_OK? $RC_OK : $RC_ERROR;
    dosayif($VERBOSE_ANY," returning %s",  $rc);
    return $rc;
}

sub db_discover {
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY,"%s: invoked");
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY," with %s=%s returning %s", $DRYRUN, $TRUE,  $rc);
        return $rc;
    }

    my $com = "$ghmisc{$MYSQLSH_EXEC} 'SHOW SCHEMAS'";
    my ($ec, $pljson) = readexec($com);
    if ($ec != $EC_OK) {
        dosayif($VERBOSE_ANY,"line %s cannot proceed: failed to retrieve schemas, ec %s, json %s",  __LINE__, $ec, Dumper($pljson));
        usage("cannot proceed: failed to retrieve schemas, exit code $ec", __LINE__);
        exit $EC_ERROR;
    }
    dosayif($VERBOSE_ANY,"exit code %s",$ec);
    dosayif($VERBOSE_DEV,"exit code %s json %s",$ec,Dumper($pljson));
    my @ldb = grep {$_ ne 'mysql' and $_ ne 'information_schema' and $_ ne 'performance_schema' and $_ ne 'sys'}
                map{chop; s/"//g; s/^.* //; $_}
                  grep {/"Database":/} @$pljson;
    foreach my $snam (sort(@ldb)) {
        $ghcreate_schemas{$snam} = "CREATE SCHEMA $snam";
        dosayif($VERBOSE_SOME,"discovered test schema %s",$snam);
    }

    dosayif($VERBOSE_ANY," returning %s",  $rc);
    return $rc;
}

# 1: kind: virtual default where update etc
# 2: schema.table.column of the column we are building
# returns: (value_generate_sub function_sub operator)
sub descrcol {
    my ($kind,$colnam) = @ARG;
    my $dtclass = $ghstc2class{$colnam}; #todo sub
    my $dt = $ghstc2just{$colnam};
    $dtclass = 'integer' if (not defined($dtclass)); # todo report some
    $dt = 'smallint' if (not defined($dt));
    $dtclass = lc($dtclass); #todo at origin
    $dt = lc($dt); #todo at origin
    my $subvaldt = "value_generate_$dt";
    my $subvaldtclass = "value_generate_$dtclass";
    my $subval = defined(&$subvaldt)? $subvaldt : $subvaldtclass;
    croak("$kind:$colnam:$dtclass:$dt sub '$subval' is not defined. CROAK.") if (not defined(&$subval));
    my $fundt = "function_${kind}_$dt";
    my $fundtclass = "function_${kind}_$dtclass";
    my $fun = defined($ghreal{$fundt})? $fundt : $fundtclass;
    my $haveop = defined($ghreal{"operator_$dt"})? "operator_$dt" : (defined($ghreal{"operator_$dtclass"})? "operator_$dtclass" : undef);
    return ($subval, $fun, $haveop);
}

# 1: operator parameter name, can be undef
# 2: term to operate on
# 3: item number in 1 to len
# returns operator wrapped term
sub dooper {
    my ($haveop,$termval,$item) = @_;
    my $rc = $termval;
    if (defined($haveop)) {
        my $op = process_rseq($haveop);
        $op =~ s/MINUS/-/g;
        $op =~ s/N=/!=/g;
        if ($op =~ /o\@p/) {
            $op =~ s/o\@p//;
            croak("Prefix operator '$op' is not + or - for $haveop") if ($op ne '+' and $op ne '-');
            $termval = "$op$termval";
            $op = process_rseq($haveop);
            $op =~ s/MINUS/-/g; # todo maybe parm to process
            $op =~ s/N=/!=/g;
        }
        $op =~ s/o\@p?//;
        if ($item > 1) {
            $rc = " $op $termval";
        } else {
            $rc = $termval;
        }
    } else {
        $rc = $termval;
    }
    croak("dooper() rc '$rc' wrong. CROAK.") if ($rc =~ /MINUS/ or $rc =~ /N=/);
    return $rc;
}

my %ghvgsub = (
'value_generate_bigint' => \&value_generate_bigint,
'value_generate_binary' => \&value_generate_binary,
'value_generate_bit' => \&value_generate_bit,
'value_generate_blob' => \&value_generate_blob,
'value_generate_char' => \&value_generate_char,
'value_generate_datetime' => \&value_generate_datetime,
'value_generate_date' => \&value_generate_date,
'value_generate_decimal' => \&value_generate_decimal,
'value_generate_double' => \&value_generate_double,
'value_generate_enum' => \&value_generate_enum,
'value_generate_float' => \&value_generate_float,
'value_generate_geomcollection' => \&value_generate_geomcollection,
'value_generate_geometrycollection' => \&value_generate_geometrycollection,
'value_generate_geometry' => \&value_generate_geometry,
'value_generate_int' => \&value_generate_int,
'value_generate_json' => \&value_generate_json,
'value_generate_linestring' => \&value_generate_linestring,
'value_generate_longblob' => \&value_generate_longblob,
'value_generate_longtext' => \&value_generate_longtext,
'value_generate_mediumblob' => \&value_generate_mediumblob,
'value_generate_mediumint' => \&value_generate_mediumint,
'value_generate_mediumtext' => \&value_generate_mediumtext,
'value_generate_multilinestring' => \&value_generate_multilinestring,
'value_generate_multipoint' => \&value_generate_multipoint,
'value_generate_multipolygon' => \&value_generate_multipolygon,
'value_generate_numeric' => \&value_generate_numeric,
'value_generate_point' => \&value_generate_point,
'value_generate_polygon' => \&value_generate_polygon,
'value_generate_set' => \&value_generate_set,
'value_generate_smallint' => \&value_generate_smallint,
'value_generate_text' => \&value_generate_text,
'value_generate_timestamp' => \&value_generate_timestamp,
'value_generate_time' => \&value_generate_time,
'value_generate_tinyblob' => \&value_generate_tinyblob,
'value_generate_tinyint' => \&value_generate_tinyint,
'value_generate_tinytext' => \&value_generate_tinytext,
'value_generate_varbinary' => \&value_generate_varbinary,
'value_generate_varchar' => \&value_generate_varchar,
'value_generate_year' => \&value_generate_year
);

# 1: schema.table
# 2: kind: virtual default where update etc
# 3: schema.table.column of the column we are building
sub build_expression {
    my ($tnam, $kind, $colnam) = @ARG;
    my ($schema,$table,$col) = split(/\./,$colnam);
    my $expr = '';
    my $cannull = $ghstc2cannull{$colnam};
    my ($subval,$fun,$haveop) = descrcol($kind,$colnam);
    
    my $dep = defined($haveop)? process_rseq("${kind}_expression_depth") : 1;

    my $hom = 0;
    my $add = '';
    for (my $level = 1; $level <= $dep; ++$level) {
        my $len = defined($haveop)? process_rseq("${kind}_expression_length") : 1;
        my $exlev = '';
        for my $item (1..$len) {
            my $termkind = process_rseq("${kind}_term_kind");
            my $termval = '';
            if ($termkind eq 'value') {
                croak("$subval() is not defined. CROAK.") if (not defined($ghvgsub{$subval})); # todo internalise
                $termval = $ghvgsub{$subval}->($colnam,$kind);
            } else {      # function
                $termval = defined($ghreal{$fun})? process_rseq($fun) : 'NULL';
                if ($kind eq $DEFAULT and $termval eq 'NULL' and not $cannull) {
                    # fallback to value
                    croak("$subval() is not defined. CROAK.") if (not defined($ghvgsub{$subval})); # todo internalise
                    $termval = $ghvgsub{$subval}->($colnam,$kind);
                }
                if ($termval =~ /\@F/) {
                    $termval =~ s/\@F//g;
                    $termval =~ s/[}]/)/g;
                }
                if ($termval =~ /\@COL/) {
                    my $plcols = $ghst2cols{$tnam};
                    my $slcols = scalar(@$plcols);
                    while ($termval =~ /\@COL/) {
                        my $rcol = $plcols->[int(rand()*$slcols)];
                        $termval =~ s/\@COL/$rcol/;
                    }
                }
                $termval =~ s/\@STSELF/$colnam/g;
                $termval =~ s/\@QSTSELF/"$colnam"/g;
                $termval =~ s/\@SELF/$col/g;
                $termval =~ s/;/,/g;
                if ($termval =~ /\@S\(/) {
                    $termval =~ s/\@S//g;
                    my $evexpr = doeval($termval,$FALSE,$TRUE);      # return scalar, silent
                    # todo maybe try to check to some degree in checkscript e.g. if undefined sub
                    # or search eval for undefined?
                    $termval = defined($evexpr)? $evexpr : 'NULL';
                    if ($kind eq $DEFAULT and $termval eq 'NULL' and not $cannull) {
                        croak("unrechable code for $kind:$colnam, NULL for NOT NULL. CROAK.");
                    }
                }
            }
            croak("Empty term for $kind:$colnam. CROAK.") if ($termval eq '');
            croak("Unexpected non empty exlev '$exlev' for $kind:$colnam:$item/$len undef op") if ($exlev ne '' and not defined($haveop));
            $exlev .= dooper($haveop,$termval,$item);
        }
        croak("Empty term for $kind:$colnam len $len. CROAK.") if ($exlev eq '');
        if ($dep > 1) {
            $exlev = "($exlev)";
        }
        croak("Unexpected non empty expr '$expr' for $kind:$colnam:$level/$dep undef op") if ($expr ne '' and not defined($haveop));
        $expr .= dooper($haveop,$exlev,$level);
    }

    # consider parentesis overall
    my $ppnam = "${kind}_parenthesis_p";
    if (defined($ghreal{$ppnam}) and rand() < $ghreal{$ppnam}) {
        $expr = "($expr)";
    }
    croak("expr '$expr' wrong. CROAK.") if ($expr =~ /N=/ or $expr eq '');
    return $expr;
}

# returns RC_OK if all SQL is executed successfully, othrwise RC_WARNING
sub db_create {
    my $rc = $RC_OK;
    # CREATE TABLE SQL for all tables
    my @lsql = ();
    my %hstcol2def = ();      # obscure pk related see code

    my $nschemas = $ghreal{'schemas'};
    dosayif($VERBOSE_ANY," will create %s schemas", $nschemas);
    foreach my $sn (1..$nschemas) {
        process_rseq('schema_name_format');
        my $nam = sprintf($ghreal{'schema_name_format'},$sn);
        my $drop = $ghreal{'schema_drop_first'} eq $YES? "DROP SCHEMA $nam; " : '';
        $ghcreate_schemas{$nam} = "${drop}CREATE SCHEMA $nam";
        $ghs2pltables{$nam} = [];
    }
    foreach my $snam (sort(keys(%ghcreate_schemas))) {
        my $com = "$ghmisc{$MYSQLSH_EXEC} '$ghcreate_schemas{$snam}' --force";
        dosayif($VERBOSE_ANY,"(--%s=%s) will execute %s",$DRYRUN,$ghasopt{$DRYRUN},$com);
        next if ($ghasopt{$DRYRUN});
        my ($ec, $pljson) = readexec($com);
        dosayif($VERBOSE_ANY,"exit code %s executing %s",$ec,$com);
        dosayif($VERBOSE_DEV,"exit code %s executing %s json %s",$ec,$com,Dumper($pljson));
        $rc = $RC_WARNING if ($rc == $RC_OK and $ec != $EC_OK);
    }

    foreach my $snam (keys(%ghcreate_schemas)) {
        $ghs2ntables{$snam} = process_rseq('tables_per_schema');
    }
    foreach my $snam (keys(%ghs2ntables)) {
        # for each table
        for my $ntab (1..$ghs2ntables{$snam}) {
            # table structure
            my $needind = process_rseq("indexes_per_table");
            my $frm = process_rseq("table_name_format");
            my $tnam = "$snam.".sprintf($frm,$ntab);
            push(@{$ghs2pltables{$snam}}, $tnam);
            $ghst2hasvcols{$tnam} = 0;
            $ghst2mayautoinc{$tnam} = $TRUE if (rand() < $ghreal{'table_has_autoinc_p'});
            push(@lsql, "DROP TABLE IF EXISTS $tnam; CREATE TABLE $tnam (");
            my $tail = ')';
            my $tas = process_rseq('table_autoextend_size');
            $tail .= " AUTOEXTEND_SIZE=$tas" if ($tas ne $EMPTY);
            $tas = process_rseq('table_autoinc');
            $tail .= " AUTO_INCREMENT=$tas" if ($tas ne $EMPTY);
            $tas = process_rseq('table_row_format');
            if ($tas ne $EMPTY) {
                if ($tas =~ /^COMPRESSED/) {
                    my $kbs = $tas;
                    $kbs =~ s/^COMPRESSED//;
                    $tail .= " ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=$kbs";
                } else {
                    my $toc = process_rseq('table_compression');
                    $tail .= " ROW_FORMAT=$tas";
                    $tail .= " COMPRESSION='$toc'" if ($toc ne $EMPTY);
                }
            }
            $tas = process_rseq('table_stats_auto_recalc');
            $tail .= " STATS_AUTO_RECALC=$tas" if ($tas ne $EMPTY);
            $tas = process_rseq('table_stats_persistent');
            $tail .= " STATS_PERSISTENT=$tas" if ($tas ne $EMPTY);
            $tas = process_rseq('table_stats_sample_pages');
            $tail .= " STATS_SAMPLE_PAGES=$tas" if ($tas ne $EMPTY);
            $tas = process_rseq($CHARACTER_SET);
            $tail .= " CHARACTER SET $tas" if ($tas ne $EMPTY);
            my $table_pk = '';
            $ghst2ncolspk{$tnam} = process_rseq('columns_pk');
            $ghst2ncolsnp{$tnam} = process_rseq('columns_non_pk');
            my @lcols = ();
            foreach my $ncol (1..$ghst2ncolspk{$tnam}) {
                $frm = process_rseq("column_pk_name_format");
                my $colsn = sprintf($frm,$ncol);
                my $colnam = "$tnam.$colsn";
                push(@lcols,$colsn);
                $hstcol2def{$colnam} = $TRUE;      # mark PK
            }
            foreach my $ncol (1..$ghst2ncolsnp{$tnam}) {
                $frm = process_rseq("column_non_pk_name_format");
                my $colsn = sprintf($frm,$ncol);
                my $colnam = "$tnam.$colsn";
                push(@lcols,$colsn);
                $hstcol2def{$colnam} = $FALSE;
            }
            $ghst2needvcols{$tnam} = process_rseq('virtual_columns_per_table');
            $ghst2needvcols{$tnam} = scalar(@lcols)-1 if ($ghst2needvcols{$tnam} >= scalar(@lcols));
            if (rand() < $ghreal{'pk_first_p'}) {
                dosayif($VERBOSE_MORE," table %s will have pk columns first",$tnam);
                $ghst2cols{$tnam} = \@lcols;
            } else {
                dosayif($VERBOSE_MORE,"table %s will NOT have pk columns first",$tnam);
                @lcols = shuffle(@lcols);
                $ghst2cols{$tnam} = \@lcols;
            }
            my $can_autoinc = $FALSE;
            my $indnum = 0;
            my %hcolcanind = ();
            my %hcolneedpref = ();
            my $srid = undef;
            my @lnvcols = ();
            my @ltabsql = ();      # SQL for this table
            foreach my $cnam (@lcols) {
                # each column in table
                my $colnam = "$tnam.$cnam";
                $ghstc2isautoinc{$colnam} = $FALSE;
                $ghstc2cannull{$colnam} = $TRUE;
                $ghstc2canfull{$colnam} = $FALSE;
                $ghstc2virtual{$colnam} = $FALSE;
                $ghstc2unsigned{$colnam} = $FALSE;
                $ghstc2len{$colnam} = -1;
                $ghstc2candefault{$colnam} = $TRUE;
                $ghstc2hasdefault{$colnam} = $FALSE;
                my $tclass = process_rseq('datatype_class');
                my $canpk = $hstcol2def{$colnam};      # can be part of PK unchanged e.g. CHAR but not TEXT
                my $keylen = undef;
                my $canunique = $canpk eq "$TRUE"? $FALSE : $TRUE;      # UNIQUE can be added to coldef
                # sink for PK
                if ($tclass eq $SPATIAL or $tclass eq $JSON) {
                    $tclass = $INTEGER if ($hstcol2def{$colnam});
                    $canunique = $FALSE;
                }
                if ($tclass eq $LOB and $hstcol2def{$colnam} and $ghst2ncolspk{$tnam} == 1) {
                    $tclass = $INTEGER;
                }
                # now we have final datatype class
                $ghstc2class{$colnam} = $tclass;
                if ($tclass ne $JSON) {
                    $hcolcanind{$cnam} = $TRUE;
                } else {
                    # https://bugs.mysql.com/bug.php?id=113860
                    $ghstc2candefault{$colnam} = $FALSE;
                }
                $hcolneedpref{$cnam} = $tclass eq $LOB? $TRUE : $FALSE;
                my $dt = $tclass;
                $ghstc2just{$colnam} = $dt;
                if ($tclass eq $INTEGER) {
                    $can_autoinc = $TRUE;
                    $dt = process_rseq('datatype_integer');
                    $ghstc2just{$colnam} = $dt;
                    if ($dt eq 'BIT') {
                        my $len = process_rseq('datatype_bit_len');
                        if ($len ne $EMPTY) {
                            $dt .= "($len)";
                            $ghstc2len{$colnam} = $len;
                        }
                    } else {
                        my $prob = rand();
                        if ($prob < $ghreal{'integer_unsigned_p'}) {
                            $dt .= " UNSIGNED";
                            $ghstc2unsigned{$colnam} = $TRUE;
                        }
                        if ($ghst2mayautoinc{$tnam} and not $ghst2hasautoinc{$tnam} and rand() < $ghreal{table_has_autoinc_p}) {
                            $ghst2hasautoinc{$tnam} = $TRUE;
                            $dt .= " AUTO_INCREMENT";
                            $ghstc2isautoinc{$colnam} = $TRUE;
                            $ghstc2candefault{$colnam} = $FALSE;
                            if (rand() < $ghreal{'pk_autoinc_p'}) {
                                $ghst2pkautoinc{$tnam} = $TRUE;
                                $dt .= " PRIMARY KEY";
                                $ghstc2cannull{$colnam} = $FALSE;
                            } else {
                                # todo consider edge case of missing in any subsequent index/ autoinc_unique_p ?
                                $dt .= " UNIQUE";
                            }
                        }
                    }
                } elsif ($tclass eq $DECIMAL) {
                    $dt = process_rseq('datatype_decimal');
                    $ghstc2just{$colnam} = $dt;
                    my $whole = process_rseq('decimal_whole');
                    if ($whole ne $EMPTY) {
                        $ghstc2len{$colnam} = $whole;
                        $dt .= "($whole";
                        my $part = process_rseq('decimal_part');
                        if ($part ne $EMPTY) {
                            $part = $whole if ($part > $whole);
                            $dt .= ",$part";
                            $ghstc2len{$colnam} = $whole - $part;      # digits BEFORE .
                        }
                        $dt .= ')';
                    }
                } elsif ($tclass eq 'FLOATING') {
                    $dt = process_rseq('datatype_floating');
                    $ghstc2just{$colnam} = $dt;
                } elsif ($tclass eq $DATETIME) {
                    $dt = process_rseq('datatype_datetime');
                    $ghstc2just{$colnam} = $dt;
                    if ($dt eq $DATETIME or $dt eq 'TIMESTAMP') {
                        my $frac = process_rseq('datetime_fractional');
                        $dt .= "($frac)" if ($frac ne $EMPTY);
                    }
                } elsif ($tclass eq 'CHARACTER') {
                    $ghstc2canfull{$colnam} = $TRUE;
                    $dt = process_rseq('datatype_character');
                    $ghstc2just{$colnam} = $dt;
                    my $len = $dt eq 'CHAR'? process_rseq('datatype_char_len') : process_rseq('datatype_varchar_len');
                    $len = $V3072 if ($canpk and $len > $V3072);
                    $dt .= "($len)";
                    $ghstc2len{$colnam} = $len;
                    my $cs = process_rseq($CHARACTER_SET);
                    $dt .= " CHARACTER SET $cs" if ($cs ne $EMPTY);
                } elsif ($tclass eq 'BINARY') {
                    $dt = process_rseq('datatype_binary');
                    $ghstc2just{$colnam} = $dt;
                    my $len = '';
                    if ($dt eq 'BINARY') {
                        $len = process_rseq('datatype_binary_len');
                        if ($canpk) {
                            $keylen = process_rseq($DATATYPE_LOB_KEY_LEN);
                            $keylen = $len if ($len ne $EMPTY and $keylen > $len);
                            $keylen = 1 if ($len eq $EMPTY);
                        }
                    } else {
                        $len = process_rseq('datatype_varbinary_len');
                    }
                    $len = $V3072 if ($canpk and $len ne $EMPTY and $len > $V3072);
                    if ($len ne $EMPTY) {
                        $dt .= "($len)";
                        $ghstc2len{$colnam} = $len;
                    } else {
                        $ghstc2len{$colnam} = 1;
                    }
                } elsif ($tclass eq $LOB) {
                    $canunique = $FALSE;
                    $dt = process_rseq('datatype_lob');
                    $ghstc2just{$colnam} = $dt;
                    $ghstc2canfull{$colnam} = $TRUE if ($dt =~ /TEXT/);
                    if ($canpk) {
                        $keylen = process_rseq($DATATYPE_LOB_KEY_LEN);
                    }
                } elsif ($tclass eq 'ENUMS') {
                    $dt = process_rseq('datatype_enums');
                    $ghstc2just{$colnam} = $dt;
                    my $len = $dt eq 'ENUM'? process_rseq('datatype_enum_len') : process_rseq('datatype_set_len');
                    $ghstc2len{$colnam} = $len;
                    my $vl = '';
                    for (my $n = 1; $n <= $len; ++$n) {
                        $vl .= ",'v$n'";
                    }
                    $vl =~ s/^.//;
                    $dt .= "($vl)";
                } elsif ($tclass eq $SPATIAL) {
                    $dt = process_rseq('datatype_spatial');
                    $ghstc2just{$colnam} = $dt;
                    $srid = process_rseq('spatial_srid');
                }
                my $virt = ($ghstc2isautoinc{$colnam} or $ghst2hasvcols{$tnam} >= $ghst2needvcols{$tnam})?
                             $EMPTY: process_rseq('column_virtuality');
                if ($virt ne $EMPTY) {
                    $virt = 'STORED' if ($canpk);
                    $dt .= " AS ($TO_BUILD) $virt";
                    ++$ghst2hasvcols{$tnam};
                    $ghstc2virtual{$colnam} = $TRUE;
                    $ghstc2candefault{$colnam} = $FALSE;
                } else {
                    push(@lnvcols,$cnam);
                }
                if (defined($srid)) {
                    if ($srid ne $EMPTY) {
                        $dt .= " SRID $srid";
                        $ghstc2srid{$colnam} = $srid;
                    } else {
                        $ghstc2srid{$colnam} = 0;
                    }
                    $srid = undef;
                }
                if ($canunique and $needind > 0 and rand() < $ghreal{'column_unique_p'}) {
                    $dt .= " UNIQUE";
                    --$needind;
                }
                my $vis = process_rseq('column_visibility');
                if ($canpk) {      # todo expr
                    $table_pk .= " , $cnam";
                    $table_pk .= "($keylen)" if (defined($keylen));
                    $ghstc2cannull{$colnam} = $FALSE;
                } else {
                    if ($canpk or $ghstc2isautoinc{$colnam} or $tclass eq $SPATIAL) {
                        $vis =  $EMPTY; # todo allow spatial null
                    } else {
                        $vis = process_rseq('column_null');
                        $ghstc2cannull{$colnam} = $vis eq 'NOT_NULL'? $FALSE : $TRUE;
                    }
                    $vis =~ s/_/ /;
                    $dt .= " $vis" if ($vis ne $EMPTY);
                }
                if ($ghstc2candefault{$colnam} and rand() < $ghreal{'column_default_p'}) {
                    my $expr = build_expression($tnam,$DEFAULT,$colnam);
                    $dt .= " DEFAULT $expr";
                    $ghstc2hasdefault{$colnam} = $TRUE;
                }
                my $coldef = "$cnam $dt";
                $ghstc2dt{$colnam} = $dt;
                # small chance there will be no keys after the last column
                $coldef .= ',' unless ($ghst2pkautoinc{$tnam} and $needind == 0 and $cnam eq $lcols[scalar(@lcols)-1]);
                push(@ltabsql, $coldef);
            }
            # now build virtual columns definition
            foreach my $col (@lcols) {
                my $colnam = "$tnam.$col";
                next if (not $ghstc2virtual{$colnam});
                my $expr = build_expression($tnam,$VIRTUAL,$colnam);
                foreach my $sql (@ltabsql) {
                    $sql =~ /$TO_BUILD/ or next;
                    $sql =~ s/$TO_BUILD/$expr/;
                    last;
                }
            }
            push(@lsql, @ltabsql);
            $ghst2nvcols{$tnam} = \@lnvcols;
            $table_pk =~ s/^ *,+/ PRIMARY KEY(/;
            my $table_indexes = '';
            push(@lsql, "$table_pk)")
              unless ($ghst2pkautoinc{$tnam});
            my @lindcols = keys(%hcolcanind);
            $needind = 0 if (scalar(@lindcols) == 0);
            foreach my $inum (1..$needind) {
                my $needcols = process_rseq('columns_per_index');
                if ($needcols eq 'ALL') {
                    $needcols = scalar(@lindcols) <= 16? scalar(@lindcols) : 16; #todo const
                }
                my $fulltext = rand() < $ghreal{'fulltext_index_p'}? 'FULLTEXT ' : '';
                my @lhavefull = shuffle(grep {$ghstc2canfull{"$tnam.$_"}} @lindcols);
                $fulltext = '' if (scalar(@lhavefull) == 0);
                my $uniq = ($fulltext eq '' and rand() < $ghreal{'index_unique_p'})? 'UNIQUE ' : '';
                my $iline = ", ${fulltext}${uniq}INDEX ind$inum (";
                ++$indnum;
                # pk may not be before
                $iline =~ s/,// if ($indnum == 1 and $ghst2pkautoinc{$tnam});
                my @lhavecols = $fulltext eq ''? shuffle(@lindcols) : shuffle(@lhavefull);
                for my $colnum (1..$needcols) {
                    last if ($colnum > scalar(@lhavecols));
                    my $thiscol = $lhavecols[$colnum-1];
                    my $coname = "$tnam.$thiscol";
                    if ($ghstc2class{$coname} eq $SPATIAL) {
                        if ($ghstc2cannull{"$tnam.$thiscol"} or $uniq ne '') {
                            next;
                        } else {
                            $iline = ", $thiscol";
                            last;
                        }
                    }
                    $iline .= ", $thiscol";
                    if ($hcolneedpref{$thiscol}) {
                        my $lenp = process_rseq('index_prefix_len');
                        $lenp = $ghstc2len{$coname}
                          if ($ghstc2len{$coname} > 0 and $lenp > $ghstc2len{$coname}
                              and rand() < process_rseq($VKCHAR));
                        $iline .= "($lenp)" if ($lenp ne $EMPTY);
                    }
                }
                $iline =~ s/\( *,/(/;
                $iline .= ")";
                if (not $iline =~ /\(\)/) {      # marginal case related to spatial todo figure out
                    push(@lsql,$iline);
                } else {
                    $lsql[scalar(@lsql)-1] =~ s/,$//;
                }
            }
            push(@lsql, "$tail;");
        }
    }

    my $fil = doeval($ghreal{'tables_create_sql'});
    my $subrc = tlist2file(\@lsql, ">$fil");
    dosayif($VERBOSE_ANY,"has written table creation SQL to %s with rc=%s %s",$fil,$rc,$GHRC{$rc});
    $rc = $subrc if ($subrc != $RC_OK);
    if ($rc == $RC_OK or $rc == $RC_WARNING) {
        my $com = "$ghmisc{$MYSQLSH_RUN_FILE} $fil";
        dosayif($VERBOSE_ANY,"(--%s=%s) will execute %s",$DRYRUN,$ghasopt{$DRYRUN},$com);
        if (not $ghasopt{$DRYRUN}) {
            my ($ec, $pljson) = readexec($com);
            dosayif($VERBOSE_ANY,"exit code %s executing %s",$ec,$com);
            dosayif($VERBOSE_DEV,"exit code %s executing %s json %s",$ec,$com,Dumper($pljson));
            $rc = $RC_WARNING if ($rc == $RC_OK and $ec != $EC_OK);
            # clean up records for tables that failed to create
            dosayif($VERBOSE_ANY,"remove records for tables that failed to create");
            my $badtables = 0;
            my %hblist = ();
            foreach my $tnam (keys(%ghst2cols)) {
                my $com = "$ghmisc{$MYSQLSH_EXEC} 'SHOW CREATE TABLE $tnam'";
                my ($ec, $pljson) = readexec($com);
                if ($ec != $EC_OK) {
                    ++$badtables;
                    dosayif($VERBOSE_SOME," table %s does not exist, forgetting it",$tnam);
                    ++$hblist{$tnam};
                    foreach my $pha (@ghstlist) {
                        foreach my $cnam (keys(%$pha)) {
                            delete($pha->{$cnam}) if ($cnam =~ /^$tnam\./);
                        }
                    }
                    foreach my $snam (keys(%ghs2pltables)) {
                        my @lgood = ();
                        foreach my $tnam (@{$ghs2pltables{$snam}}) {
                            push(@lgood,$tnam) unless (defined($hblist{"$snam.$tnam"}));
                        }
                        $ghs2pltables{$snam} = \@lgood;
                    }
                } else {
                    my $str = join('',@$pljson);
                    $str =~ s/\\n//gms;
                    my $psome = decode_json($str);
                    $str = $psome->{"Create Table"};
                    $str =~ s/^[^(]*\(/(/;
                    $ghst2createtable{$tnam} = $str;
                    ++$gntables;
                    push(@glstables,$tnam);
                }
            }
            dosayif($VERBOSE_ANY," we have %s good tables, forgot %s bad tables",$gntables,$badtables);
            croak("Cannot proceed, no good tables. CROAK.") if ($gntables == 0);
        }
    }
    dosayif($VERBOSE_ANY," returning %s",  $rc);
    return $rc;
}

# 1: string
# 2: kind
sub pnotnull {
    my ($lex,$kind) = @ARG;
    my $par = "${kind}_parenthesis_p";
    # consider wrap in parenthesis
    $lex = "($lex)" if (rand() < $ghreal{$par});
    # consider prefix with NOT
    if (rand() < $ghreal{'where_expression_not_p'}) {
        $lex = " NOT $lex";
        # and wrap that
        $lex = "($lex)" if (rand() < $ghreal{$par});
    }
    # consider IS [NOT] NULL again
    my $isnull = process_rseq('operator_null');
    if ($isnull ne $EMPTY) {
        $isnull =~ s/_/ /g;
        $lex = "$lex $isnull";
        # and wrap that
        $lex = "($lex)" if (rand() < $ghreal{$par});
    }
    return $lex;
}

# 1: schema.table
# 2: parameter name for no where
# returns WHERE clause with WHERE
sub build_where {
    my ($tnam,$parm) = @ARG;
    if (rand() < $ghreal{$parm}) {
        my $rc = rand() < $ghreal{'where_all_by_no_where_p'}? '' : 'WHERE (1 = 1)';
        return $rc
    }

    my $expr = '';
    my $dep = process_rseq('where_logical_depth');
    # columns we will use
    my @lcols = grep {rand() < $ghreal{'where_column_p'}} @{$ghst2cols{$tnam}};
    @lcols = scalar(@lcols) == 0? shuffle(@{$ghst2cols{$tnam}}) : shuffle(@lcols);
    my $havecols = scalar(@lcols);
    for (my $level = 1; $level <= $dep; ++$level) {
        my $add = '';
        my $len = process_rseq('where_logical_length');
        for (my $enum = 1; $enum <= $len; ++$enum) {
            # choose column to build expression on
            my $colnam = "$tnam.$lcols[int(rand()*$havecols)]";
            my $dtclass = $ghstc2class{$colnam}; #todo sub
            my $dt = $ghstc2just{$colnam};
            #croak("$tnam:where:$colnam: no datatype or datatype class for $colnam. CROAK.") if (not defined($dt) or not defined($dtclass));
            $dtclass = 'x' if (not defined($dtclass));
            $dt = 'x' if (not defined($dt));
            $dtclass = lc($dtclass); #todo at origin
            $dt = lc($dt); #todo at origin
            my $haveop = defined($ghreal{"operator_logical_$dt"})?
                           "operator_logical_$dt" :
                           (defined($ghreal{"operator_logical_$dtclass"})? "operator_logical_$dtclass" : undef);
            my $lex = build_expression($tnam,'where',$colnam);
            # consider IS [NOT] NULL
            my $isnull = process_rseq('operator_null');
            if ($isnull ne $EMPTY) {
                $isnull =~ s/_/ /g;
                $lex = "$lex $isnull";
            } elsif (defined($haveop)) {
                my $op = process_rseq($haveop);
                $op =~ s/o\@//;
                $op =~ s/MINUS/-/; # todo do move to process
                $op =~ s/N=/!=/; # todo do move to process
                my $lex02 = build_expression($tnam,'where',$colnam); # todo different compatible column
                $lex = "$lex $op $lex02";
            }
            $lex = pnotnull($lex,'where');
            $add .= $lex;
            $add = pnotnull($add,'where');
            # add logical operator
            if ($enum != $len) {
                my $op = process_rseq('operator_logical');
                $add .= " $op ";
            }
        }
        $expr .= $add;
        $expr = pnotnull($expr,'where');
        # add logical operator
        if ($level != $dep) {
            my $op = process_rseq('operator_logical');
            $expr .= " $op ";
        }
    }

    $expr = pnotnull($expr,'where'); #todo different parameters
    $expr = "WHERE $expr";
    return $expr;
}

# 1: schema.table
# 2: test parameter to use for selection
# 3: kind: if not 'SELECT', do not use virtual columns
#          if UPDATE, return ref array
sub table_columns_subset {
    my ($tnam, $parm, $kind) = @ARG;
    my @lcall = $kind eq 'SELECT'? shuffle(@{$ghst2cols{$tnam}}) : shuffle(@{$ghst2nvcols{$tnam}});
    @lcall = shuffle(@{$ghst2cols{$tnam}}) if (scalar(@lcall) == 0);
    my @lc = grep {rand() < $ghreal{$parm}} @lcall;
    push(@lc,$lcall[0]) if (scalar(@lc) == 0);
    my $rc = $kind eq $UPDATE? \@lc : join(',',@lc);
    return $rc;
}

# returns statement
sub stmt_select_generate {
    my $stmt = 'SELECT';
    # determine schema.table
    my $tnam = $glstables[int(rand()*$gntables)];
    my $tosel = rand() < process_rseq('select_star_p')? '*' : table_columns_subset($tnam,$SELECT_COLUMN_P,'SELECT');
    $stmt .= " $tosel FROM $tnam";
    my $wher = build_where($tnam,'select_where_all_p');
    $stmt .= " $wher";
    return $stmt;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_decimal {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $bas = process_rseq('decimal_value');
    my $mas = defined($ghstc2len{$col})? $ghstc2len{$col} : $bas;
    $bas = $mas if ($bas > $mas and rand() < process_rseq($VKCHAR));
    my $value = rand()*(10.0**$bas);
    $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_numeric {
    return value_generate_decimal(@ARG);
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_int {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_int');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_tinyint {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_tinyint');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_bigint {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_bigint');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_bit {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_bit');
    my $valmax = defined($ghstc2len{$col})? 2**$ghstc2len{$col}-1 : $value;
    $value = $valmax if ($value > $valmax and rand() < process_rseq($VKCHAR));
    $value = abs($value); #todo workaround need bugfix
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_smallint {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_smallint');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_mediumint {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_mediumint');
    if (not defined($ghstc2unsigned{$col}) or $ghstc2unsigned{$col} == $TRUE) { #todo consider
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_float {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $exp = process_rseq('float_value_exp');
    my $value = $exp eq $EMPTY? value_generate_decimal($col,$kind) : sprintf("%sE%s",rand(),$exp);
    $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_double {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $exp = process_rseq('double_value_exp');
    my $value = $exp eq $EMPTY? value_generate_decimal($col,$kind) : sprintf("%sE%s",rand(),$exp);
    $value = -$value if (rand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_char {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_char_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = 'c' x $valen;
    $value = "'$value'";
    dosayif($VERBOSE_NEVER,"for %s(%s) returning: %s",$col,$len,$value);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_varbinary {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_varbinary_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('x',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_binary {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_binary_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('y',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_tinyblob {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_tinylob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('t',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_longblob {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_longlob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('l',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_datetime {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my ($year,$month,$day) = value_generate_date($col,$kind,$FALSE);
    my ($hour,$minute,$sec,$micr) = value_generate_time($col,$kind,$TRUE);
    my $value = sprintf("%04s-%02s-%02s %02s:%02s:%02s",$year,$month,$day,$hour,$minute,$sec);
    $value .= sprintf(".%06s",$micr) if ($micr ne $EMPTY);
    $value = "'$value'";
    dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: return list
# returns: value as string suitable to add to VALUES, if 2 is TRUE, returns list of h,m,s,ms as strings, including EMPTY for ms
sub value_generate_time {
    my $col = $ARG[0];
    my $kind = $ARG[1];
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $retlist = (defined($ARG[2]) and $ARG[2] == $TRUE)? $TRUE : $FALSE;
    my $hor = $retlist? process_rseq('datetime_hour_value') :  process_rseq('time_hour_value');
    my $mit = process_rseq('datetime_minute_value');
    my $sec = process_rseq('datetime_second_value');
    my $micr = process_rseq('datetime_microsecond_value');
    if ($retlist) {
        my @lval = ($hor,$mit,$sec,$micr);
        dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,"@lval");
        return @lval;
    } else {
        my $value = "$hor:$mit:$sec";
        $value .= ".$micr" if ($micr ne $EMPTY);
        $value = "'$value'";
        dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,$value);
        return $value;
    }
    croak('internal error: reached unreachable code. CROAK.');
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: true if timestamp wanted, false if datetime, undef if date
# returns: value as string suitable to add to VALUES, or if defined 2, list of year month day:w
sub value_generate_date {
    my $col = $ARG[0];
    my $kind = $ARG[1];
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $ists = defined($ARG[2])? $ARG[2] : undef;
    my $month = process_rseq('datetime_month_value');
    my $day = process_rseq('datetime_day_value');
    my $year = $ists? process_rseq('timestamp_year_value') : process_rseq('datetime_year_value');
    if (defined($ists)) {
        my @lval = ($year,$month,$day);
        dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,"@lval");
        return @lval;
    } else {
        my $value = sprintf("'%04d-%02d-%02d'",$year,$month,$day);
        dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,$value);
        return $value;
    }
    croak('internal error: reached unreachable code. CROAK.');
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_timestamp {
    my ($col,$kind) = @ARG;
    my ($year,$month,$day) = value_generate_date($col,$kind,$TRUE);
    my ($hour,$minute,$sec,$micr) = value_generate_time($col,$kind,$TRUE);
    my $value = sprintf("%04s-%02s-%02s %02s:%02s:%02s",$year,$month,$day,$hour,$minute,$sec);
    $value .= sprintf(".%06s",$micr) if ($micr ne $EMPTY);
    $value = "'$value'";
    dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_multipolygon {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multipolygon_len');
    for my $n (1..$len) {
        $value .= ','.value_generate_polygon($col,$kind,$TRUE);
    }
    $value =~ s/^,//;
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = sprintf("ST_MPolyFromText('MULTIPOLYGON(%s)',%s)",$value,$srid);
    $value = "($value)" if ($kind eq $DEFAULT); #todo prob
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_multipoint {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multipoint_len');
    for my $n (1..$len) {
        $value .= sprintf(", %s %s",process_rseq($VALUE_POINT_X),process_rseq($VALUE_POINT_Y));
    }
    $value =~ s/^,//;
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = sprintf("ST_MPointFromText('MULTIPOINT(%s)',%s)",$value,$srid);
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: if TRUE return raw data
sub value_generate_polygon {
    my ($col,$inkind) = ($ARG[0],$ARG[1]);
    croak("inkind is not defined. CROAK.") if (not defined($inkind));
    my $raw = (defined($ARG[2]) and $ARG[2]);
    my $value = '';
    my $dep = process_rseq('value_polygon_size');
    my $kind = $dep == 1? '' : process_rseq('value_polygon_kind');
    my @lp1 = ();
    my $len = process_rseq($VALUE_POLYGON_LEN);
    my $p1;
    for my $n (1..$len) {
        my $xx = process_rseq($VALUE_POINT_X);
        my $yy = process_rseq($VALUE_POINT_Y);
        my $point .= sprintf(", %s %s",$xx,$yy);
        push(@lp1,[$xx,$yy]);
        $p1 = $point if ($n == 1);
        $value .= $point;
    }
    push(@lp1,$lp1[0]);
    $value .= $p1;
    $value =~ s/^,//;
    $value = "($value)";
    foreach my $np (2..$dep) {
        my @lpnext = @lp1;
        my $subp = '';
        my $sublen = process_rseq($VALUE_POLYGON_LEN);
        if ($kind eq $STRANGE) {
            @lpnext = ();
        } else {
            $sublen = $len if ($sublen > $len);
        }
        foreach my $vn (0..$sublen-1) {
            if ($kind eq $STRANGE) {
                push(@lpnext,[process_rseq($VALUE_POINT_X),process_rseq($VALUE_POINT_Y)]);
            } elsif ($kind eq 'RIGHT') {
                $lpnext[$vn]->[0] /= "$np.0";
                $lpnext[$vn]->[1] /= "$np.0";
            } elsif ($kind eq 'MIRROR') {
                $lpnext[$vn]->[0] *= -1;
                $lpnext[$vn]->[1] *= -1;
            }
            $subp .= sprintf(", %s %s",$lpnext[$vn]->[0],$lpnext[$vn]->[1]);
        }
        $subp .= sprintf(", %s %s",$lpnext[0]->[0],$lpnext[0]->[1]);
        $subp =~ s/^,//;
        $value .= ", ($subp)";
    }
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = $raw? "($value)" : sprintf("ST_PolyFromText('POLYGON(%s)',%s)",$value,$srid);
    $value = "($value)" if ($inkind eq $DEFAULT and not $raw);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_multilinestring {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multilinestring_len');
    for my $n (1..$len) {
        $value .= ','.value_generate_linestring($col,$kind,$TRUE);
    }
    $value =~ s/^,//;
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = sprintf("ST_MLineFromText('MULTILINESTRING(%s)',%s)",$value,$srid);
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: if TRUE return raw data like (1 2, 3 4)
sub value_generate_linestring {
    my $col = $ARG[0];
    my $kind = $ARG[1];
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $raw = defined($ARG[2])? $ARG[2] : $FALSE;
    my $value = '';
    my $len = process_rseq('value_linestring_len');
    for my $n (1..$len) {
        $value .= sprintf(", %s %s",process_rseq($VALUE_POINT_X),process_rseq($VALUE_POINT_Y));
    }
    $value =~ s/^,//;
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = $raw? "($value)" : sprintf("ST_LineFromText('LINESTRING(%s)',%s)",$value,$srid);
    $value = "($value)" if ($kind eq $DEFAULT and not $raw);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: if TRUE, return raw data
sub value_generate_point {
    my $col = $ARG[0];
    my $kind = $ARG[1];
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $raw = (defined($ARG[2]) and $ARG[2]);
    my $value = sprintf("%s %s",process_rseq($VALUE_POINT_X),process_rseq($VALUE_POINT_Y));
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = $raw? "($value)" : sprintf("ST_PointFromText('POINT (%s)',%s)",$value,$srid);
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_geometrycollection {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multigeometry_len');
    for my $n (1..$len) {
        my $subkind = process_rseq('multigeometry_kind');
        my $subval = "value_generate_".lc($subkind);
        croak("value_generate_$subval() is not defined. CROAK.") if (not defined($ghvgsub{$subval}));
        my $termval = $ghvgsub{$subval}->($col,$kind,$TRUE);
        $value .= ", $kind$termval";
    }
    $value =~ s/^,//;
    my $srid = defined($ghstc2srid{$col})? $ghstc2srid{$col} : $V4326;
    $value = sprintf("ST_GeomCollFromText('GEOMETRYCOLLECTION(%s)',%s)",$value,$srid);
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

sub value_generate_geomcollection {
    return value_generate_geometrycollection(@ARG);
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_geometry {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $subkind = 'value_generate_'.lc(process_rseq('geometry_kind'));
    croak("$subkind() is not defined. CROAK.") if (not defined($ghvgsub{$subkind}));
    my $value = $ghvgsub{$subkind}->($col,$kind);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_json {
    my ($col,$inkind) = @ARG;
    croak("inkind is not defined. CROAK.") if (not defined($inkind));
    my $value = "{}";
    my $kind = process_rseq('value_json_kind');
    if ($kind eq 'SIMPLEML') {
        # multilevel to be developed further todo
        my $pha = {'a' => '1a', 'b' => '2b', 'c' => ['l1','l2',3], 'd' => {'x' => 1}};
        $value = encode_json($pha);
    } elsif ($kind eq 'FROMSCRIPT') {
        # local from script
        $gh2json{$RAND} = rand();
        $value = encode_json(\%gh2json); #todo parameter and shorter
    } elsif ($kind eq 'REFARRAY') {
        # local ref array
        my @l = ();
        my $len = process_rseq('value_json_len');
        foreach my $i (1..$len) {
            push(@l,rand()*$i);
        }
        $value = encode_json(\@l);
    } elsif ($kind eq 'SCALAR') { 
        # local scalar
        $value = encode_json('j'.process_rseq('value_json_len'));
    } elsif ($kind eq 'REFHASH') { 
        # local ref hash
        my %hl = ();
        my $len = process_rseq('value_json_small_len');
        foreach my $i (1..$len) {
            $hl{$i} = 'abc' x $i;
        }
        $value = encode_json(\%hl);
    }
    $value =~ s/'/\\'/g;
    $value = "'$value'";
    dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_year {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('year_value');
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_set {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $len = process_rseq('datatype_set_value_len');
    $len = $ghstc2len{$col} if (defined($ghstc2len{$col}) and $len > $ghstc2len{$col} and rand() < process_rseq($VKCHAR));
    my $value = '';
    foreach my $num (1..$len) {
        $value .= ",v$num";
    }
    $value =~ s/^,//;
    $value = "'$value'";
    dosayif($VERBOSE_NEVER,"for %s %s returning: %s",$col,$len,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_enum {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 3; #todo consider parm
    my $num = int(rand()*$len)+1;
    my $value = "\"v$num\"";
    dosayif($VERBOSE_NEVER,"for %s returning: %s",$col,$value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_mediumtext {
    return value_generate_mediumblob(@ARG);
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_mediumblob {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_mediumlob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('m',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_blob {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_lob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('n',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_longtext {
    return value_generate_longblob(@ARG);
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_tinytext {
    return value_generate_tinyblob(@ARG);
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_text {
    return value_generate_blob(@ARG);
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_varchar {
    my ($col,$kind) = @ARG;
    croak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_varchar_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if ($len >= 1 and $valen > $len and rand() < process_rseq($VKCHAR));
    my $value = "REPEAT('b',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
};

# 1: schema.table
# 2: column list
# returns "V1, V2, ... " string and ref array of the same
# used only for INSERT
sub build_insert_values {
    my ($tnam, $plcols) = @ARG;
    my $values = '';
    foreach my $col (@$plcols) {
        my $colnam = "$tnam.$col";
        # consider DEFAULT
        if ($ghstc2hasdefault{$colnam} and rand() < $ghreal{'insert_default_p'}) {
            $values .= ", DEFAULT";
            next;
        }
        # consider NULL
        if ($ghstc2isautoinc{$colnam} == $TRUE) {
            if (rand() >= $ghreal{'autoinc_explicit_value_p'}) {
                $values .= ', NULL';
                next;
            }
        }
        if ($ghstc2cannull{$colnam} == $TRUE) {
            if (rand() < $ghreal{'null_legitimate_p'}) {
                $values .= ', NULL';
                next;
            }
        } else {
            if (rand() < $ghreal{'null_illegitimate_p'}) {
                $values .= ', NULL';
                next;
            }
        }
        my $val =  build_expression($tnam,$INSERT,$colnam);
        $values .= ", $val";
    }
    $values =~ s/^, //;

    return $values;
}

# returns statement
sub stmt_delete_generate {
    my $stmt = '';
    # determine schema.table
    my $tnam = $glstables[int(rand()*$gntables)];
    my $wher = build_where($tnam,'delete_where_all_p');
    $stmt = "DELETE FROM $tnam $wher";
    return $stmt;
}

# returns statement
sub stmt_update_generate {
    my $stmt = '';
    # determine schema.table
    my $tnam = $glstables[int(rand()*$gntables)];
    my $plcols = table_columns_subset($tnam,$UPDATE_COLUMN_P,$UPDATE);
    my $n = 0;
    foreach my $col (@$plcols) {
        my $expr = build_expression($tnam,$UPDATELC,"$tnam.$col");
        $stmt .= ", $col = $expr";
    }
    $stmt =~ s/^,//;
    my $wher = build_where($tnam,'update_where_all_p');
    $stmt = "UPDATE $tnam SET $stmt $wher";
    return $stmt;
}

# returns statement
sub stmt_insert_generate {
    my $stmt = 'INSERT INTO ';
    # determine schema.table
    my $tnam = $glstables[int(rand()*$gntables)];
    # https://bugs.mysql.com/?id=113951&edit=2
    my @lcols = shuffle(@{$ghst2nvcols{$tnam}});
    $stmt .= " $tnam (".join(',',@lcols).')';
    my $values = build_insert_values($tnam,\@lcols);
    $stmt .= " VALUES ($values)";
    return $stmt;
}

# return time in ms
sub mstime {
    my ($sec, $mks) = gettimeofday();
    my $rc = $sec*1000 + $mks / 1000;
    return $rc;
}

# 1: schema.table
# returns statement
sub stmt_alter_generate {
    my $tnam = $ARG[0];
    my $stmt = '';
    my $len = process_rseq('load_alter_length');
    for my $clausen (1..$len) {
        my $kind = process_rseq('load_alter_kind');
        if ($kind eq 'DROP_COL') {
            # select column to drop
            my @lcols = @{$ghst2cols{$tnam}};
            my $cnam = $lcols[int(rand()*scalar(@lcols))];
            $stmt .= "DROP COLUMN $cnam, ";
        } elsif ($kind eq 'ADD_COL') {
            my $cnf = process_rseq('column_non_pk_name_format'); #todo const
            my $cnam = sprintf($cnf,"_new_".int(rand()*1000));
            $stmt .= "ADD COLUMN $cnam INTEGER"; # todo robust
        } elsif ($kind eq 'TABLE_EB') {
            $stmt .= "ENGINE=InnoDB";
            last;
        }
    }
    $stmt =~ s/, *$//;
    $stmt = "ALTER TABLE $tnam $stmt";
    dosayif($VERBOSE_NEVER,"returning %s",$stmt);
    return $stmt;
}

# 1: schema.table
# returns CREATE TABLE without the CREATE TABLE schema.table prefix
sub tnam2ct {
    my $tnam = $ARG[0];
    my $com = "$ghmisc{$MYSQLSH_EXEC} 'SHOW CREATE TABLE $tnam'";
    my ($ec, $pljson) = readexec($com);
    $gstrj = join('',@$pljson);
    $gstrj =~ s/\\n//gms;
    my $psome = doeval('decode_json($gstrj)',$FALSE,$TRUE);      # silent
    return undef if (not defined($psome));
    my $str = $psome->{"Create Table"};
    $str =~ s/^[^(]*\(/(/;
    return $str;
}

# 1: schema.table
# 2: CREATE TABLE without prefix
sub internalise {
    my ($tnam,$ctnew) = @ARG;
    $ghst2createtable{$tnam} = $ctnew;
    $ctnew =~ s/\(/,/;
    my @lcoldefs = split(/, +`/,$ctnew);
    shift(@lcoldefs);
    my @lcols = ();
    my @lnvcols = ();
    foreach my $coline (@lcoldefs) {
        my @l2 = split(/` +/,$coline);
        push(@lcols,$l2[0]);
        my $cnam = "$tnam.$l2[0]";
        my $tail = $l2[1];
        $ghstc2cannull{$cnam} = ($tail =~ / NOT NULL/)? $FALSE : $TRUE;
        $ghstc2unsigned{$cnam} = ($tail =~ / unsigned/i)? $TRUE : $FALSE;
        $ghstc2isautoinc{$cnam} = ($tail =~ / AUTO_INCREMENT/? $TRUE : $FALSE);
        $ghstc2hasdefault{$cnam} = ($tail =~ / $DEFAULTUC /? $TRUE : $FALSE);
        if ($tail =~ / GENERATED ALWAYS AS /) {
            push(@lnvcols,$l2[0]);
            $ghstc2virtual{$cnam} = $TRUE;
        } else {
            $ghstc2virtual{$cnam} = $FALSE;
        }
        $ghstc2dt{$cnam} = $tail;    # wrong for last column but will do for now todo
        $tail =~ / SRID +([0-9]+) +/;
        $ghstc2srid{$cnam} = defined($1)? $1 : 0;
        $tail =~ /\(([0-9]+)\)/;
        $ghstc2len{$cnam} = defined($1)? $1 : 0;
        $tail =~ s/[ (].*//;
        $tail = uc($tail);
        $ghstc2just{$cnam} = $tail;
        $ghstc2class{$cnam} = $ghdt2class{$tail};
        $ghstc2canfull{$cnam} = (",$ghreal{'datatype_canfull'}," =~ /,$tail,/)? $TRUE : $FALSE;
    }
    $ghst2cols{$tnam} = \@lcols;
    $ghst2nvcols{$tnam} = \@lnvcols;
    return;
}

# 1: thread number, absolute
# 2: thread kind
sub server_load_thread {
    my $tnum = $ARG[0];
    my $tkind = $ARG[1];
    my $starttime = time();
    my $howlong = $ghreal{$TEST_DURATION};
    my $maxcount = $ghreal{'load_max_stmt'};
    my $lasttime = $starttime + $howlong;
    my $txnin = $FALSE;
    my $txnstmt = 0;
    my $txnstart = 0;
    my $ec = $EC_OK;

    # adjust load thread parameters
    if ($tkind ne '') {
        foreach my $parm (sort(grep {$_ =~ /${UKIND}$tkind$/} keys(%ghreal))) {
            my $soparm = $parm;
            $soparm =~ s/${UKIND}$tkind$//;
            dosayif($VERBOSE_ANY,"for %s thread #%s replacing %s of %s with %s of %s",
              $tkind,$tnum,$soparm,$ghreal{$soparm},$parm,$ghreal{$parm});
            $ghreal{$soparm} = $ghreal{$parm};
        }
    }
    
    dosayif($VERBOSE_ANY, "%s load thread %s to run for %s secons",$tkind,$tnum,$howlong);
    $ENV{_imatest_load_filebase} = "load_thread_$tnum";
    my $outto = doeval($ghreal{'load_thread_out'});
    my $errto = doeval($ghreal{'load_thread_err'});
    my $sqlto = doeval($ghreal{'load_thread_sql'});
    my $logto = doeval($ghreal{'load_thread_client_log'});
    $ENV{$LOAD_THREAD_CLIENT_LOG_ENV} = doeval($ghreal{$LOAD_THREAD_CLIENT_LOG});
    my $dosql = ($ghreal{'load_execute_sql'} eq $YES);
    dosayif($VERBOSE_ANY, "see also %s and %s and %s and %s",$ENV{$LOAD_THREAD_CLIENT_LOG_ENV},$outto,$errto,$sqlto);
    open(my $msql, ">$sqlto") or croak("failed to open >$sqlto: $ERRNO. CROAK.");
    my $shel = '';
    my $shelkind = $ghreal{'load_thread_execute_with'};
    if ($shelkind eq 'mysqlsh') {
        $shel = "$ghmisc{'mysqlsh_base'} --log-file $ENV{$LOAD_THREAD_CLIENT_LOG_ENV} >>$outto 2>>$errto";
    } elsif ($shelkind eq 'mysql') {
        $shel = "$ghmisc{'mysql_base'} >>$outto 2>>$errto";
    }
    my $msh = undef;
    my $wspid = open2(my $msout, $msh, $shel) or croak("Failed (errno: $ERRNO) to start $shel. CROAK.");
    dosayif($VERBOSE_ANY, "started as pid %s: %s",$wspid,$shel);
    $msh->autoflush();
    $msql->autoflush();
    my $f2read = undef;
    my $snum = 0;
    while ($TRUE) {
        my $thistime = time();
        last if ($thistime >= $lasttime);
        last if ($maxcount > 0 and $snum >= $maxcount);
        ++$snum;

        # now generate statement
        my $stmt = '';
        my $ksql = '';
        if ($ghreal{'txn_use'} eq $YES) {
            dosleepms(process_rseq('txn_sleep_in_ms')) if ($txnin);
            $ksql = 'END' if (rand() < $ghreal{'txn_end_p'});
            if ($txnin and $ksql eq '') {
                 $ksql = $END if ($snum - $txnstmt > $ghreal{'txn_maxlength_stmt'} or mstime() - $txnstart > $ghreal{'txn_maxlength_ms'});
            }
            if ($ksql ne $END) {
                $ksql = $BEGIN if (not $txnin and rand() < $ghreal{'txn_begin_p'});
            } else {
                $ksql = process_rseq('txn_end_how');
            }
        }
        $ksql = process_rseq('load_sql_class') if ($ksql eq '');

        my $canexp = $FALSE;
        my $tnam = '';
        if ($ksql eq 'SELECT') {
            $stmt = stmt_select_generate();
            $canexp = $TRUE;
        } elsif ($ksql eq 'INSERT') {
            $stmt = stmt_insert_generate();
            $canexp = $TRUE;
        } elsif ($ksql eq $UPDATE) {
            $stmt = stmt_update_generate();
            $canexp = $TRUE;
        } elsif ($ksql eq 'DELETE') {
            $stmt = stmt_delete_generate();
            $canexp = $TRUE;
        } elsif ($ksql eq 'CHECK') {
            $tnam = $glstables[int(rand()*$gntables)];
            $stmt = "$ksql TABLE $tnam";
        } elsif ($ksql eq $BEGIN) {
            $stmt = 'BEGIN WORK';
            $txnin = $TRUE;
            $txnstmt = $snum;
            $txnstart = mstime();
        } elsif ($ksql eq 'COMMIT' or $ksql eq 'ROLLBACK') {
            $stmt = $ksql;
            $txnin = $FALSE;
        } elsif ($ksql eq $ALTER) {
            # determine schema.table
            $tnam = $glstables[int(rand()*$gntables)];
            $stmt = stmt_alter_generate($tnam);
        } else {
            croak("load_sql_class=$ksql is not supported yet. CROAK.");
        }
        if ($canexp) {
            my $exp = process_rseq('explain');
            $exp =~ s/_/ /;
            $stmt = "$exp $stmt" if ($exp ne $EMPTY);
        }

        # now send statement for execution
        if (waitpid($wspid, WNOHANG) == $wspid) {
            dosayif($VERBOSE_ANY,"process $wspid has terminated, restarting");
            close($msh);
            $wspid = open2(my $msout, $msh, $shel) or croak("Failed (errno: $ERRNO) to start $shel. CROAK.");
            dosayif($VERBOSE_ANY, "restarted as pid %s: %s",$wspid,$shel);
            $msh->autoflush();
        }
        dosayif($VERBOSE_NEVER, "sending to execute: %s",$stmt);
        dosayif($VERBOSE_ANY, "sending to execute stmt #%s",$snum) if ($snum % $ghreal{'report_every_stmt'} == 0);
        printf($msh "%s;\n", $stmt) if ($dosql);
        ++$ghsql2stats{$ksql};
        printf($msql "%s;\n", $stmt);

        # now reflect the results in internal structures
        if ($ksql eq $ALTER) {
            # if ALTER succeed we do not necessarily get the current state. We will get it after the sever restart if specified
            # in test parameters
            my $ctnew = tnam2ct($tnam);
            if (not defined ($ctnew) or $ctnew eq $ghst2createtable{$tnam}) {
                dosayif($VERBOSE_MORE, "ALTER may have failed: %s", $stmt);
            } else {
                dosayif($VERBOSE_MORE, "ALTER may have succeeded: %s", $stmt);
                internalise($tnam,$ctnew);
            }
        }

        # now sleep after txn
        my $ms = process_rseq('txn_sleep_after_ms',$TRUE);
        dosleepms($ms);
    }
    close $msh;
    close $msql;
    dosayif($VERBOSE_ANY, " load thread %s exiting at %s with exit code %s after executing %s statements",$tnum,time(),$ec,$snum);
    dosayif($VERBOSE_ANY, " load thread %s statistics: %s",$tnum,Dumper(\%ghsql2stats));
    dosayif($VERBOSE_ANY, " see also %s and %s and %s and %s",$ENV{$LOAD_THREAD_CLIENT_LOG_ENV},$outto,$errto,$sqlto);
    exit $ec;
}

sub server_termination_thread {
    my $starttime = time();
    my $howlong = $ghreal{$TEST_DURATION};
    my $checkstart = $ghreal{'server_start_control'};
    my $starttimeout = $ghreal{'server_start_timeout'};
    my $dowait = $ghreal{'server_termination_wait'};
    my $waittimeout = $ghreal{$SERVER_TERMINATION_WAIT_TIMEOUT};
    my $lasttime = $starttime + $howlong;
    my $ec = $EC_OK;
    $gdosayoff = 2;
    dosayif($VERBOSE_ANY, " started at %s to run for %ss",$starttime,$howlong);
    my $stepnum = 0;
    while ($TRUE) {
        my $thistime = time();
        last if ($thistime >= $lasttime);
        ++$stepnum;
        my $step = process_rseq('server_termination_every_seconds');
        $step = $starttime + $step - $lasttime if ($starttime + $step > $lasttime);
        dosayif($VERBOSE_ANY," will sleep %s seconds for step %s",$step,$stepnum);
        # assume server is running atm even on 1st step
        dosleep($step);
        # now terminate server
        my $howterm = process_rseq('server_termination_how');
        my $howhow = $howterm eq $SHUTKILL? $ghreal{'server_terminate_shutdown'} : $ghreal{"server_terminate_$howterm"};
        $howhow .= " wait $waittimeout" if ($dowait eq $YES and $howterm ne $SIGSTOP and $howterm ne $SHUTKILL);
        my $howout = doeval("\"$howhow\"");
        dosayif($VERBOSE_ANY," terminating server with %s using %s for step %s",$howterm,$howout,$stepnum);
        my $subec = doeval("system(\"$howhow\")");
        $subec >>= $EIGHT;
        dosayif($VERBOSE_ANY," execution of %s resulted in exit code %s for step %s",$howout,$subec,$stepnum);
        # wait for shutkill
        if ($howterm eq $SHUTKILL) {
            my $slep = process_rseq('server_terminate_shutkill_before');
            dosayif($VERBOSE_ANY," sleeping %s seconds before killing server for %s",$slep,$howterm);
            dosleep($slep);
            my $howh = $ghreal{'server_terminate_sigkill'};
            $howh .= $dowait eq $YES? " wait $waittimeout" : '';
            my $kec = doeval("system(\"$howh\")");
            $kec >>= $EIGHT;
            dosayif($VERBOSE_ANY," execution of %s resulted in exit code %s for step %s",$howh,$kec,$stepnum);
        }
        # wait after termination
        my $after = process_rseq($howhow eq $SIGSTOP? 'server_termination_duration_on_sigstop' : 'server_termination_duration');
        dosayif($VERBOSE_ANY," will sleep %s seconds after server termination for step %s",$after,$stepnum);
        # assume server is running atm even on 1st step
        dosleep($after);
        # now restart server
        dosayif($VERBOSE_ANY," starting server for step %s",$stepnum);
        my $howrestart = $howterm eq $SIGSTOP ?  $ghreal{'server_terminate_unstop'} : $ghreal{$SERVER_START};
        $howrestart .= " wait $starttimeout" if ($checkstart eq $YES and $howterm ne $SIGSTOP);
        dosayif($VERBOSE_ANY," restarting server using %s for step %s",$howrestart,$stepnum);
        $subec = doeval("system(\"$howrestart\")");
        dosayif($VERBOSE_ANY," execution of %s resulted in exit code %s for step %s",$howrestart,$subec,$stepnum);
    }
    dosayif($VERBOSE_ANY, " exiting at %s with exit code %s",time(),$ec);
    exit $ec;
}

# 1: thread number
# 2: load kind or '' for base
# 3: random seed
sub start_load_thread {
    my $tnum = $ARG[0];
    my $tkind = $ARG[1];
    my $rseed = $ARG[2];
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY, " invoked with --%s=%s",  $DRYRUN, $ghasopt{$DRYRUN});
    if (not $ghasopt{$DRYRUN}) {
        my $pid = fork();
        if ($pid == 0) {
            srand($rseed);
            $ghmisc{$RSEED} = $rseed;
            dosayif($VERBOSE_ANY, "random seed is %s for this %s load thread #%s", $rseed, $tkind, $tnum);
            server_load_thread($tnum,$tkind);
        }
        dosayif($VERBOSE_ANY, " forked thread %s with pid=%s",$tnum,$pid);
        push(@glpids,$pid);
        $rc = $RC_ERROR if (not defined($pid) or $pid < 0);
    } 
    dosayif($VERBOSE_ANY, " returning %s %s",  $rc, $GHRC{$rc});
    return $rc;
}

sub start_server_termination_thread {
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY, " invoked with --%s=%s",  $DRYRUN, $ghasopt{$DRYRUN});
    if (not $ghasopt{$DRYRUN}) {
        my $pid = fork();
        if ($pid == 0) {
            server_termination_thread();
        }
        dosayif($VERBOSE_ANY, " forked thread with pid=%s",  $pid);
        push(@glpids,$pid);
        $rc = $RC_ERROR if (not defined($pid) or $pid < 0);
    } 
    dosayif($VERBOSE_ANY, " returning %s %s",  $rc, $GHRC{$rc});
    return $rc;
}

# rc RC_OK: initialised successfully
#    RC_ZERO: nothing to do
sub init_db {
    my $rc = $RC_OK;
    my $subrc;
    dosayif($VERBOSE_ANY,"invoked");
    $rc = $RC_ZERO if $ghasopt{$DRYRUN};

    my @lcnf = map {"SET PERSIST_ONLY $_;"} split("\n",$ghreal{'mysql_initial_cnf'});
    foreach my $sets (@lcnf) {
        my $com = "$ghmisc{$MYSQLSH_EXEC} '$sets'";
        my ($ec, $pljson) = readexec($com);
        dosayif($VERBOSE_ANY,"exit code %s for %s, details: %s",$ec,$com,($ec == $EC_OK? 'none' : Dumper($pljson)));
    }
    if (scalar(@lcnf) > 0) {
        dosayif($VERBOSE_ANY,"restart server because of PERSIST_ONLY config is of size %s",scalar(@lcnf));
        my $com = sprintf("%s wait %s", $ghreal{"server_terminate_shutdown"}, $ghreal{$SERVER_TERMINATION_WAIT_TIMEOUT});
        my $ec = doeval("system(\"$com\")");
        $ec >>= $EIGHT;
        dosayif($VERBOSE_ANY,"exit code %s for %s",$ec,$com);
    }

    my $subec = $ghasopt{$DRYRUN}? 0 : doeval("system(\"$ghreal{$SERVER_START} wait $ghreal{'server_start_timeout'}\")");
    dosayif($VERBOSE_ANY,"execution (--%s=%s of %s of '%s' resulted in exit code %s",
      $DRYRUN,$ghasopt{$DRYRUN},$SERVER_START,$ghreal{$SERVER_START},$subec);
  
    if ($ghreal{$CREATE_DB} eq $STRING_TRUE) {
        $subrc = db_create();
    } else {
        $subrc = db_discover();
    }
    $rc = $subrc if ($rc != $RC_OK and $rc != $RC_ZERO);

    dosayif($VERBOSE_ANY," returning %s",  $rc);
    return $rc;
}

# start execution. Execution starts HERE.
GetOptions(\%ghasopt, @LOPT) or usage("invalid options supplied",__LINE__);
scalar(@ARGV) == 0 or usage("no arguments are allowed",__LINE__);
foreach my $soname (keys(%HDEFOPT)) {
    $ghasopt{$soname} = $HDEFOPT{$soname} if (not defined($ghasopt{$soname}));
}
usage("invoked with --help",__LINE__) if ($ghasopt{$HELP});
usage("invoked with --version",__LINE__) if ($ghasopt{$VERSION});
dosayif($VERBOSE_ANY, "invoked with %s", "@ARGV");
dosayif($VERBOSE_ANY, "Options to use are %s", Dumper(\%ghasopt));
exists($ghasopt{$TESTYAML}) or usage("--".$TESTYAML." must be supplied",__LINE__);

my $test_script =  $ghasopt{$TESTYAML};
-f $test_script or usage("$test_script file does not exist, or inaccessible, or not a regular file",__LINE__);

my $rseed = "none";
exists($ghasopt{$SEED}) and do {
    $rseed = $ghasopt{$SEED};
    srand($rseed);
} or do {
    $rseed = srand();
};
$ghmisc{$RSEED} = $rseed;
dosayif($VERBOSE_ANY, "random seed is %s for this script version %s", $rseed, $version);

my $phv = doeval("LoadFile('$test_script')") or die "bad yaml in file $test_script";
%ghtest = %$phv;
$phv = dclone(\%ghtest);
%ghreal = %$phv;
$ENV{_imatest_tmpdir} = doeval($ghreal{'tmpdir'});
$ENV{_imatest_load_filebase} = "master_thread";      # will change in load threads
$ENV{$LOAD_THREAD_CLIENT_LOG_ENV} = doeval($ghreal{$LOAD_THREAD_CLIENT_LOG});

dosayif($VERBOSE_DEV, "%s start: %s\n%s end", $TESTYAML, Dumper(\%ghtest), $TESTYAML);

checkscript();
buildmisc();
dosayif($VERBOSE_DEV, "resulting test script is %s",Dumper(\%ghreal));

# initial ops
if ($ghreal{'init_stop_server'} eq $YES) {
    my $howto = "$ghreal{'server_terminate_shutdown'} wait $ghreal{$SERVER_TERMINATION_WAIT_TIMEOUT}";
    dosayif($VERBOSE_ANY," terminating server using %s for test start",$howto);
    my $subec = doeval("system(\"$howto\")");
    $subec >>= $EIGHT;
    dosayif($VERBOSE_ANY," execution of %s resulted in exit code %s",$howto,$subec);
}   
if ($ghreal{'init_remove'} eq $YES) {
    my $toglob = doeval($ghreal{'init_remove_pattern'});
    my @l2unlink = glob($toglob);
    safe_unlink(@l2unlink);
}

my $recreated = process_recreate();

if ($ghreal{$CREATE_DB} eq $STRING_TRUE and $recreated != $RC_ERROR) {
    init_db();
}

# todo here we run test
my $trc = $RC_OK;
$ghreal{$TEST_DURATION} = process_rseq($TEST_DURATION);
if ($ghreal{'server_terminate'} eq $YES) {
    $trc = start_server_termination_thread();
    croak("failed to start server termination thread. CROAK.") if ($trc != $RC_OK);
}
my $tlod = $ghreal{'load_threads'};
dosayif($VERBOSE_ANY,"starting test load threads: %s",$tlod);
my @lolod = split(/,/,$tlod);
my $talnum = 0;
foreach my $elem (@lolod) {
    my @lok = split('X',$elem);
    push(@lok,'') if (scalar(@lok) < 2);
    foreach my $tnum (1..$lok[0]) {
        ++$talnum;
        $trc = start_load_thread($talnum,$lok[1],int(rand()*10000+100));
        croak("failed to start test load thread. CROAK.") if ($trc != $RC_OK);
    }
}

# sleep while test is running
my $slep = $ghreal{$TEST_DURATION};
dosayif($VERBOSE_ANY,"will sleep for %s seconds",$slep);
dosleep($slep);

# kill load threads
dosayif($VERBOSE_ANY,"eliminating child processes %s","@glpids");
foreach my $pid (@glpids) {
    my $sub = waitpid($pid, WNOHANG);
    if ($sub != $pid) {
        kill('KILL', $pid);
        dosayif($VERBOSE_ANY,"killed process $pid");
    } else {
        dosayif($VERBOSE_ANY,"process $pid has already terminated");
    }
}

my $teardown = process_teardown();

my $ec = 0;
dosayif($VERBOSE_ANY,"exiting with exit code %s", $ec);
dosayif($VERBOSE_ANY,"See also %s", $ghasopt{$SEE_ALSO}) if (defined($ghasopt{$SEE_ALSO}));
exit($ec);
