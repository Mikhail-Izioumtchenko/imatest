use strict;
use warnings;
use English;

require 5.032;

# mind start execution. Execution starts HERE.

# style: flexible, mostly per perldoc perlstyle. Follow suit.
# M1. mandatory: no tabs, 4 blanks indentation
# M2. mandatory: no case statement, no camelCase
# 2. desirable: should look like C. Postfix if is OK and is preferred over postfix unless. 
# 5. blocks in {} even where a single statement after while or similar is allowed
# 7. comments start with single #, indent with code if on separate line
# 8. do avoid OO, do not use constant
# 9. 1+2 is OK, 1<2 is better written as 1 < 2
# 10. lowercase names except pseudo constants which should be all UPPERCASE
# 12. use not and or for logical ops, instead of && etc.
# 13. longnamesnounderscores are fine, names_with are also OK
# 14. important: names of variables in the same scope should differ in at least two characters
# 15. important: array names start with l, hash names, with h. Intended globals start with g e.g. @glist
# 16. max source code line len is 143

# perl features
# do not use shuffle()
# always sort(keys(%h))

#todo
# flag file to start tracing
# on duplicate key update
# limit order by group by having except union intersect join subqueries
# LOCK INSTANCE FOR BACKUP UNLOCK INSTANCE
# LOCK TABLES UNLOCK TABLES
# ANALYZE histogram
# FLUSH
# LOCK
# savepoints
# set

use Carp qw(croak shortmess);
use Data::Dumper qw(Dumper);
use DateTime;
use File::Tee qw(tee);
use Getopt::Long qw(GetOptions);
use IO::Handle;
use IPC::Open2 qw(open2);
use JSON qw(encode_json decode_json);
use POSIX qw(:sys_wait_h);
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);
use Time::HiRes qw(gettimeofday usleep);
use Tie::IxHash;
use YAML qw(LoadFile);

use DBI;
use DBD::mysql;

STDOUT->autoflush();
STDERR->autoflush();

my $version = '5.11';

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
my $VERBOSE_NEVER = 4;
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
my $CHECK_RW = 2;
my $CHECK_RO = 3;
my $CHECK_DOWN = 1;
my $CHECK_ASSERT = 4;
my $EC_OK = 0;
my $EC_ERROR = 1;

my $CHECKFILE = 'to_check_file';

my $FDEC = "%05d";

my $DEC_RANGE_MARKER = 'D';
my $INT_RANGE_MARKER = 'I';
my $NEG_MARKER = 'M';

my $CHARACTER_SET = 'character_set';
my $CHECK_SUBKEYS = '_2levelkeys';
my $DATETIME = 'datetime';
my $DATATYPE_LOB_KEY_LEN = 'datatype_lob_key_len';
my $DECIMAL = 'decimal';
my $DEFAULT = 'default';
my $EIGHT = 8;
my $EMPTY = 'EMPTY';
my $EXPRESSION_GROUP = 'expression_group';
my $INTEGER = 'integer';
my $JSON = 'json';
my $LOAD_THREAD_CLIENT_LOG = 'load_thread_client_log';
my $LOAD_THREAD_CLIENT_LOG_ENV = '_imatest_client_log';
my $LOB = 'lob';
my $NEEDS_ON_TRUE = 'needs_on_true';
my $NO = 'no';
my $NUMBER_REVERSE_SIGN_LEGITIMATE_P = 'number_reverse_sign_legitimate_p';
my $NUMBER_REVERSE_SIGN_ILLEGITIMATE_P = 'number_reverse_sign_illegitimate_p';
my $ONLY_NAMES = 'only_names';
my $ONLY_NON_NEGATIVE_INTEGERS = 'only_non_negative_integers';
my $ONLY_POSITIVE_INTEGERS = 'only_positive_integers';
my $ONLY_VALUES_ALLOWED = 'only_values_allowed';
my $OPERATOR_LOGICAL = 'operator_logical';
my $PARENTHESIS = 'parenthesis';
my $RAND = 'rand';
my $RSEED = 'rseed';
my $SELECT_COLUMN_P = 'select_column_p';
my $SERVER_RESTART = 'server_restart';
my $SERVER_TERMINATION_WAIT_TIMEOUT = 'server_termination_wait_timeout';
my $SHUTKILL = 'shutkill';
my $SIGSTOP = 'sigstop';
my $SPATIAL = 'spatial';
my $STRANGE = 'STRANGE';
my $STRING_TRUE = 'True';
my $SUPPORTED = 'supported';
my $TEST_DURATION = 'test_duration_seconds';
my $UKIND = '_k_';
my $V3072 = 3072;
my $V4326 = 4326;
my $VALUE_POINT_X = 'value_point_x';
my $VALUE_POINT_Y = 'value_point_y';
my $VALUE_POLYGON_LEN = 'value_polygon_len';
my $VKCHAR = 'value_kchar_length_adjust_p';
my $WHERE = 'where';
my $YES = 'yes';

my @LOPT = ("$DRYRUN!", "$HELP!", "$TESTYAML=s", "$SEE_ALSO=s", "$SEED=i", "$VERBOSE=i", "$VERSION!");
my %HDEFOPT = ("$DRYRUN" => 0, $HELP => 0, $VERBOSE => 0, $VERSION => 0);      # option defaults

# globals of sorts
my $gdbh;      # writer port
my %ghdbh = ();      # config ports
my $gstrj;
my $gdosayoff = 2;
my %ghasopt = ();      # resulting options values hash
my %ghver = ();      # syntax checker hash
my %ghtest = ();      # test script hash
my %ghreal = ();      # test script hash with Rseq and similar processed e.g. 1-7 becomes e.g. 4
my %ghdt2class = ();      # datatype => class
my %ghclass2dt = ();      # class => ref array datatypes
my %ghsql2stats = ();      # insert => N

# start schema related
my $gntables = 0;         # number of tables successfully created or discovered in all schemas
my @glschemas = ();      # schema names
my @glstables = ();         # list of all schema.table. Used to get table to run DML/DDL on.
# end schema related

# start table related
my %ghst2cols = ();      ## schema.table => ref array column names or :expr
my %ghst2pkcols = ();      ## schema.table => ref array pk column names
my %ghst2createtable = ();      ## schema.table => CREATE TABLE
my %ghst2nvcols = ();      ## schema.table => ref array column names for non virtual columns USED DML
my %ghst2aes = ();      ## schema.table => autoextend size or -1 for not specified
my %ghst2charset = ();      ## schema.table => default charset mandatory
my %ghst2col = ();      ## schema.table => default collation or EMPTY
my %ghst2stap = ();      ## schema.table => stats persistent value or -1
my %ghst2sar = ();      ## schema.table => stats autorecalc or -1
my %ghst2sampl = ();      ## schema.table => stats sample pages or -1
my %ghst2kbs = ();      ## schema.table => key block size or -1
my %ghst2rof = ();      ## schema.table => row format or 'EMPTY'
my %ghst2comp = ();      ## schema.table => compression or 'EMPTY'
my %ghst2ind = ();      ## schema.table => ref list non pk index names and :primary for primary if exists
my @ghstlist = (
\%ghst2ind,
\%ghst2createtable,
\%ghst2cols,
\%ghst2pkcols,
\%ghst2nvcols,
\%ghst2aes,
\%ghst2charset,
\%ghst2col,
\%ghst2stap,
\%ghst2sar,
\%ghst2rof,
\%ghst2comp,
\%ghst2kbs,
\%ghst2sampl
               );
# end schema.table hashes

# schema.table.index including :primary
my %ghsti2kind = ();    # schema.table.index => kind: primary unique key fulltext spatial
my %ghsti2cols = ();    # schema.table.index => ref list column names
my %ghsti2cotype = ();  # schema.table.index => ref array col type: 0 col 1 col(N) 2 expr
my %ghsti2lens = ();    # schema.table.index => ref array col prefix length or expr for functional or -1 if just column
my @ghstilist = (
\%ghsti2cols,
\%ghsti2lens,
\%ghsti2cotype,
\%ghsti2kind
                );

# start schema.table.column hashes
my %ghstc2class = ();      # schema.table.column => column datatype class
my %ghstc2just = ();      # schema.table.column => column datatype, just it
my %ghstc2len = ();      # schema.table.column => column length or scale 5 5,2 if specified or -1
my %ghstc2charset = ();      # schema.table.column => column charset if shown or :EMPTY
my %ghstc2collate = ();      # schema.table.column => column collate if shown or :EMPTY
my %ghstc2cannull = ();      # schema.table.column => column nullability 1 or 0
my %ghstc2unsigned = ();      # schema.table.column => column is unsigned 1 unsigned 0 signed or not specified
my %ghstc2srid = ();      # schema.table.column => SRID or -1
my %ghstc2canfull = ();      # schema.table.column => can be part of fulltext index
my %ghstc2isautoinc = ();      # schema.table.column => is autoinc
my %ghstc2virtual = ();      # schema.table.column => column is virtual 1 stored 2 virtual or 0
my %ghstc2virtex = ();      # schema.table.column => virtual expression or :EMPTY
my %ghstc2hasdefault = ();      # schema.table.column => has DEFAULT 1 or 0
my %ghstc2default = ();      # schema.table => DEFAULT or :EMPTY
my @ghstcolist = (
\%ghstc2class,
\%ghstc2charset,
\%ghstc2collate,
\%ghstc2default,
\%ghstc2hasdefault,
\%ghstc2just,
\%ghstc2srid,
\%ghstc2cannull,
\%ghstc2canfull,
\%ghstc2len,
\%ghstc2virtual,
\%ghstc2virtex,
\%ghstc2unsigned,
\%ghstc2isautoinc,
                 );
# end schema.table.column hashes

my %ghmisc = ();        # 
my %ghlpids = ();      # process ids of load threads => parameters to restart;
my %ghchepids = ();      # process ids of check thread => []
my %ghtermpids = ();      # process ids of termination threads => parameters to restart

# used to generate JSON values
tie my %gh2json, 'Tie::IxHash';
%gh2json = (
'a' => $gdosayoff ,
'b' => \%ghasopt ,
'c' => \%ghst2cols ,
'r' => $gntables ,
't' => \@glstables ,
'v' => \%ghst2nvcols ,
'p' => \%ghstc2class ,
'7' => \%ghstc2just ,
'i' => \%ghstc2cannull ,
'u' => \%ghstc2canfull ,
'y' => \%ghstc2len ,
'l' => \%ghstc2virtual ,
'k' => \%ghstc2unsigned ,
'1' => \%ghstc2isautoinc ,
'6' => \%ghlpids,
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
    --$SEE_ALSO string: optional, this string is output at the end of the run
    --$VERSION: show script version and exit
EOF
    ;
    dosayif($VERBOSE_ANY, "%s", $usage);
    docroak("usage() called. CROAK.");
}

sub dosrand {
    my $hav = scalar(@ARG);
    my $sran = $hav? srand($ARG[0]) : srand();
    dosayif($VERBOSE_MORE,"srand of %s returning %s",(defined($ARG[0])? $ARG[0] : 'nothing'),$sran);
    return $sran;
}

my $gnrand = 0;
sub dorand {
    my $hav = scalar(@ARG);
    docroak("dorand called with argument %s",$ARG[0]) if ($hav);
    my $ran = rand();
    ++$gnrand;
    my $mess = '';
    $mess = shortmess(); $mess =~ s/\n/ ; /g;
    dosayif($VERBOSE_DEV,"rand %s returning %s with shortmess %s",$gnrand,$ran,$mess);
    #dosayif($VERBOSE_MORE,"rand shortmess for %s is %s",$gnrand,shortmess());
    return $ran;
}

sub doshuffle {
    return reverse(@ARG);
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
    dosayif($VERBOSE_DEV," called with %s",$fn);
    open(my $fh, '<', $fn) or docroak("failed to open %s for reading. CROAK.",$fn);
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
    docroak("Trying to evaluate an undefined value. CROAK") if (not defined($toeval));
    my $aslist = defined($ARG[1])? $ARG[1] : 0;
    my $howver = (defined($ARG[2]) and $ARG[2])? $VERBOSE_NEVER : $VERBOSE_ANY;
    dosayif($VERBOSE_DEV, "is called with %s",  $toeval);
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
    dosayif($VERBOSE_DEV," called with %s",$com);
    my $fdout;
    my $pid = eval('open2($fdout, my $fdin, $com)');
    my @lres = ();
    while (my $lin = <$fdout>) {
        push(@lres,$lin);
    }
    waitpid($pid,0);
    my $ec = $CHILD_ERROR >> $EIGHT;
    my $rc = $ec == $EC_OK? $RC_OK : $RC_ERROR;
    dosayif($VERBOSE_DEV," execution of %s exit code %s returning %s",$com,$ec,$rc);
    return ($ec, \@lres);
}

# 1: verbosity level, prints out stuff only if --verbose >= that
# 2: format, if starts with -, no timestamp prefixed
# 3... : arguments
# prints the message prepending by something helpful
# returns whatever printf returns
sub dosayif {
    my $howver = shift @ARG;
    return if defined($ghasopt{$VERBOSE}) and $ghasopt{$VERBOSE} < $howver;
    my ($format, @largs) = @ARG;
    my $mes = shortmess();
    my @l = split(/\n/,$mes);
    my $res = defined($l[$gdosayoff])? $l[$gdosayoff] : 'main';
    $res =~ s/\(.*//;
    $res =~ s/.*://;
    $res = 'main' if ($res eq 'dosayif');
    $res = ($res eq 'dosrand' and defined($l[$gdosayoff+1]))? $l[$gdosayoff+1] : $res;
    if (not $format =~ /^-/) {
        my $doformat = "#P %s %s %s %s: $format\n";
        my $dt = DateTime->now(time_zone => 'UTC');
        my ($sec, $mks) = gettimeofday();
        my $dout = sprintf("%s %s.%06d %s", $dt->ymd(), $dt->hms(), $mks, $dt->time_zone_short_name());
        printf($doformat, $PID, $dout, $PROGRAM_NAME, $res, @largs);
    } else {
        $format =~ s/^-//;
        $format .= "\n";
        printf($format, @largs);
    }
}

# format, arguments
sub docroak {
    dosayif($VERBOSE_ANY,@ARG);
    my ($format,@larg) = @ARG;
    my $msg = sprintf("Now we CROAK. ".$format,@larg);
    printf STDERR "%s\n", $msg;
    croak($msg);
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
        $rc = $irange eq $INT_RANGE_MARKER? $valst + int(dorand()*$lr) : $valst + dorand()*$lr;
        dosayif($VERBOSE_DEV,"for this range we return %s",$rc);
    }
        
    dosayif($VERBOSE_DEV,"of '%s' returns %s","@$plval",$rc);
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
    docroak("internal error: '%s' is not an Rseq test parameter",$skey) if (not defined($ghreal{$skey}));
    my $silent = defined($ARG[1])? $ARG[1] : 1;
    my $check = defined($ARG[2])? $ARG[2] : 0;
    my $verbose = $silent? $VERBOSE_NEVER : $VERBOSE_DEV;
    my $val = $ghtest{$skey};
    my $phverk = $ghver{$skey};
    docroak("%s +%s+%s+ is not in test description file or not Rseq. CROAK.",$skey,$val,$skey) if ($check and not defined($phverk));
    my $rc = $RC_OK;
    my ($only_positive_integers, $only_non_negative_integers, $only_names, $only_values_allowed) =
         $check ?
           ($phverk->{$ONLY_POSITIVE_INTEGERS}, $phverk->{$ONLY_NON_NEGATIVE_INTEGERS}, $phverk->{$ONLY_NAMES},
            $phverk->{$ONLY_VALUES_ALLOWED}) :
           (0, 0, 0, $phverk->{$ONLY_VALUES_ALLOWED});

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
        my @lsem = split(/:/, $lcom);
        # Rule1: not more than one probability per item
        usage("$skey value $val violates Rseq Rule1: not more than one probability per item",__LINE__) if ($check and scalar(@lsem) > 2);
        # Rule3: range nor probability can be empty
        usage("$skey value $val violates Rseq Rule3: no empty ranges or probabilities, lcom '$lcom' and '@lsem: +$lsem[0]+$lsem[1]+' of size ".scalar(@lsem),__LINE__)
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
    dosayif($verbose, "%s line+%s+to+%s+of+%s+to+%s+hasprobs+%s+lastprob+%s+\n",
       $val,"@lcommas", scalar(@lcommas), Dumper(\%hcomma),$hasprobs,$lastprob);
    usage("$skey value $val violates Rseq Rule2: either no probabilities or each element but last must have probability",__LINE__)
      if ($check and (($lastprob == 1 || $hasprobs != scalar(@lcommas) - 1) && $hasprobs != 0));

    dosayif($verbose,"%s to process %s: %s, lcommas is %s, hasprobs=%s, hcommas is %s",
      $skey,$val,"@lcommas",$hasprobs,Dumper(\%hcomma));
    my $pltopr = [];
    if ($hasprobs == 0) {
        # list of equiprobable values or ranges
        my $nl = int(dorand()*scalar(@lcommas));
        $pltopr = $hcomma{sprintf($FDEC,$nl+1)};
    } else {
        # we have probabilities, go through the hash to choose a random value
        foreach my $k (sort(keys(%hcomma))) {
            my $plval = $hcomma{$k};
            my $prob = $plval->[scalar(@$plval)-1];
            my $ran = dorand();
            dosayif($verbose,"rand is %s and prob is %s for %s",$ran,$prob,Dumper($plval));
            $ran < $prob or next;
            dosayif($verbose,"for %s we choose %s",$skey,Dumper($plval));
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
    dosayif($VERBOSE_DEV, "is invoked for %s to write %s",  $fil, Dumper($pltext));

    open(my $fh, $fil) or docroak("failed to open %s. CROAK.",$fil);
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
    foreach my $skey (sort(keys(%ghtest))) {
        if ($strict eq $STRING_TRUE and not defined($ghver{$skey})) {
            if ($skey =~ /$UKIND/) {
                my $suf = $skey;
                $suf =~ s/.*$UKIND//;
                my @lok = @{$ghtest{'strict_exceptions'}};
                usage("strict is specified in $TESTYAML but '$skey' is not described in $CHECKFILE '$ghtest{$CHECKFILE}' and $suf is not in strict_exceptions of '@lok'",
                  __LINE__)
                    if (scalar(grep {$_ eq $suf } @lok) == 0);
            } else {
                usage("strict is specified in $TESTYAML but '$skey' is not described in $CHECKFILE '$ghtest{$CHECKFILE}'",__LINE__)
                  if ($skey ne 'define');
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
        foreach my $key (sort(keys(%ghver))) {
            next if ($key eq $CHECK_SUBKEYS);
            my $ph = $ghver{$key};
            foreach my $suk (sort(keys(%$ph))) {
                ++$hsub{$suk};
            } 
        }
        foreach my $have (sort(keys(%hsub))) {
            docroak("%s='%s' is defined in %s '%s' but '%s' is not there. CROAK.",
                    $CHECK_SUBKEYS,"@{$ghver{$CHECK_SUBKEYS}}", $CHECKFILE, $ghtest{$CHECKFILE}, $have)
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
                docroak("%s of %s in %s failed to evaluate. CROAK.",$skey,$ghtest{$skey},$testyaml);
            }
            $ghreal{$skey} = $ev;
            dosayif($VERBOSE_DEV, "by doeval set %s to '%s' of ref %s",$skey,$ev,ref($ev));
            next;
        }
        if (defined($vcheck) and $vcheck eq 'doeval_list') {
            my $ev = doeval($ghtest{$skey}, 1);
            if (not defined($ev)) {
                docroak("%s of %s in %s failed to evaluate. CROAK.",$skey,$ghtest{$skey},$testyaml);
            }
            $ghreal{$skey} = $ev;
            dosayif($VERBOSE_DEV, "by doeval_list set %s to '%s' of ref %s",$skey,$ev,ref($ev));
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
            process_rseq($skey, 1, 1);      # quiet, just check
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
    $ghreal{'password'} = $password;
    my $port_load = $ghreal{'port_load'} + $ghreal{'xportoffset'};
    my $myport_load = $ghreal{'port_load'} + $ghreal{'mportoffset'};
    $ENV{'_imatest_ports_destructive_rel'} = $ghreal{'ports_destructive'};
    $ENV{'_imatest_port_load_rel'} = $ghreal{'port_load'};
    my @lcla = split(/,/,$ghreal{'datatype_class2dt'});
    foreach my $clas (@lcla) {
        my @l2 = split(/:/,$clas);
        my @ldt = split(/-/,$l2[1]);
        foreach my $dat (@ldt) {
            $ghdt2class{$dat} = $l2[0];
            $ghclass2dt{$l2[0]} = [] if (not defined($ghclass2dt{$l2[0]}));
            push(@{$ghclass2dt{$l2[0]}},$dat);
        }
    }
    return $RC_OK;
}

# all
# 1: dbh
# 2: abort on SQL failure
sub db_discover {
    my ($dbh,$strict) = @ARG;
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY,"invoked");
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY,"with %s=%s returning %s", $DRYRUN, 1,  $rc);
        return $rc;
    }

    my $com = "SHOW SCHEMAS";
    my $plschemas = getarrayref($com,$dbh,$VERBOSE_ANY);
    docroak("Failed to execute %s",$com) if (not defined($plschemas) and $strict);
    my @lschemas = grep {$_ ne 'imaschema' and $_ ne 'sys' and $_ ne 'mysql' and not $_ =~ /^(performance|information)_schema$/}
                     map {$_->[0]} @$plschemas;
    docroak("we have no schemas to run test on") if (scalar(@lschemas == 0) and $strict);
    foreach my $schema (@lschemas) {
        dosayif($VERBOSE_ANY,"processing schema %s",$schema);
        my $stmt = "SHOW TABLES FROM $schema";
        my $pltables = getarrayref($stmt, $dbh,$VERBOSE_ANY);
        if (not defined($pltables)) {
            docroak("Failed to execute %s",$stmt) if ($strict);
            return $RC_ERROR;
        }
        my @ltables = map {$_->[0]} @$pltables;
        for my $tab (@ltables) {
            table_add("$schema.$tab",$dbh,$strict);
        }
    }
    
    dosayif($VERBOSE_ANY," returning %s",  $rc);
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
'value_generate_integer' => \&value_generate_int,
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

# 1: kind: virtual default where update etc
# 2: schema.table.column of the column we are building
# returns: (value_generate_sub function_sub operator)
sub descrcol {
    my ($kind,$colnam) = @ARG;
    docroak("No datatype class found for column %s",$colnam) if (not defined($ghstc2class{$colnam}));
    my $dtclass = $ghstc2class{$colnam};
    docroak("No datatype found for column %s",$colnam) if (not defined($ghstc2just{$colnam}));
    my $dt = $ghstc2just{$colnam};
    $dtclass = lc($dtclass);
    $dt = lc($dt);
    my $subvaldt = "value_generate_$dt";
    my $subvaldtclass = "value_generate_$dtclass";
    docroak("value_generate_%s nor _%s do not exist for column %s",$subvaldt,$subvaldtclass,$colnam)
        if (not defined($ghvgsub{$subvaldt}) and not defined($ghvgsub{$subvaldtclass}));
    my $subval = defined($ghvgsub{$subvaldt})? $subvaldt : $subvaldtclass;
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
        $op =~ s/MINUS/-/gi;
        $op =~ s/N=/!=/gi;
        if ($op =~ /o\@p/) {
            $op =~ s/o\@p//;
            docroak("Prefix operator '%s' is not + or - for %s",$op,$haveop) if ($op ne '+' and $op ne '-');
            $termval = "$op$termval";
            $op = process_rseq($haveop);
            $op =~ s/MINUS/-/gi;
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
    docroak("dooper() rc '%s' wrong. CROAK.",$rc) if ($rc =~ /MINUS/ or $rc =~ /N=/);
    return $rc;
}

# 1: schema.table
# 2: kind: virtual default where update etc
# 3: schema.table.column of the column we are building
sub build_expression {
    my ($tnam, $kind, $colnam) = @ARG;
    dosayif($VERBOSE_MORE, "build_expression enter");
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
            dosayif($VERBOSE_MORE, "in build_expression lev %s/%s item %s/%s",$level,$dep,$item,$len);
            my $termkind = process_rseq("${kind}_term_kind");
            my $termval = '';
            if ($termkind eq 'value') {
                docroak("%s() is not defined. CROAK.",$subval) if (not defined($ghvgsub{$subval}));
                $termval = $ghvgsub{$subval}->($colnam,$kind);
            } else {      # function
                $termval = defined($ghreal{$fun})? process_rseq($fun) : 'null';
                if ($kind eq $DEFAULT and $termval eq 'null' and not $cannull) {
                    # fallback to value
                    docroak("%s() is not defined. CROAK.",$subval) if (not defined($ghvgsub{$subval}));
                    $termval = $ghvgsub{$subval}->($colnam,$kind);
                }
                if ($termval =~ /\@F/) {
                    $termval =~ s/\@F//g;
                    $termval =~ s/[}]/)/g;
                }
                if ($termval =~ /\@COL/) {
                    my @lcols = @{$ghst2cols{$tnam}};
                    if ($termval =~ /\@COL_([a-zA-Z_]+)/) {
                        my $needtype = lc($1);
                        @lcols = grep {my $fn = "$tnam.$_"; ($ghstc2just{$fn} eq $needtype or $ghstc2class{$fn} eq $needtype)} @lcols;
                        push(@lcols,$ghst2cols{$tnam}->[0]) if (scalar(@lcols) == 0);
                    }
                    my $slcols = scalar(@lcols);
                    while ($termval =~ /\@COL/) {
                        my $rcol = $lcols[int(dorand()*$slcols)];
                        $termval =~ s/\@COL(_[a-zA-Z_]*)?/$rcol/;
                    }
                }
                $termval =~ s/\@STSELF/$colnam/g;
                $termval =~ s/\@QSTSELF/"$colnam"/g;
                $termval =~ s/\@SELF/$col/g;
                $termval =~ s/;/,/g;
                if ($termval =~ /\@S\(/) {
                    $termval =~ s/\@S//g;
                    my $evexpr = doeval($termval,0,1);      # return scalar, silent
                    $termval = defined($evexpr)? $evexpr : 'null';
                    if ($kind eq $DEFAULT and $termval eq 'null' and not $cannull) {
                        docroak("unrechable code for %s:%s, NULL for NOT NULL. CROAK.",$kind,$colnam);
                    }
                }
            }
            docroak("Empty term for %s:%s. CROAK.",$kind,$colnam) if ($termval eq '');
            docroak("Unexpected non empty exlev '%s' for %s:%s:%s/%s undef op",$exlev,$kind,$colnam,$item,$len)
              if ($exlev ne '' and not defined($haveop));
            $exlev .= dooper($haveop,$termval,$item);
        }
        docroak("Empty term for %s:%s len %s. CROAK.",$kind,$colnam,$len) if ($exlev eq '');
        if ($dep > 1) {
            $exlev = "($exlev)";
        }
        docroak("Unexpected non empty expr '%s' for %s:%s:%s/%s undef op",$expr,$kind,$colnam,$level,$dep)
          if ($expr ne '' and not defined($haveop));
        $expr .= dooper($haveop,$exlev,$level);
    }

    # consider parentesis overall
    my $ppnam = "${kind}_parenthesis_p";
    if (dorand() < $ghreal{$ppnam} and defined($ghreal{$ppnam})) {
        $expr = "($expr)";
    }
    docroak("expr '%s' wrong. CROAK.",$expr) if ($expr =~ /N=/ or $expr eq '');
    dosayif($VERBOSE_MORE, "build_expression returning");
    return $expr;
}

# pseudo globals
my %hpgstcol2def = ();      # obscure pk related see code
my %hpsgcolcanind = ();      # col => can_be_indexed
my %hpsgcolneedpref = ();       # col => need prefix if key
my $psgtable_pk = '';        # table PK clause
my $psgneedind = 0;          # indexes per table
my $pgneedvcols = 0;         # how many virtual cols we think we need
my $pghavevcols = 0;         # how many virtual cols we have
my $pgcolsnonpk = 0;         # how many non pk cols we have
my $pgcanautoinc = 0;        # can we have autoinc in table
my $pgcandefault = 0;        # can column have default
my $pghasautoinc = 0;        # do we have autoinc in table
my $pgpkautoinc = 0;         # autoinc is pk
# 1: kind: create_table, alter_table. Not used. Yet?
# 2: column name e.g. s.t.col1
# return: column definition e.g. col1 INTEGER
sub generate_column_def {
    my ($kind,$colnam) = @ARG;
    my ($schema,$tabl,$cnam) = split(/\./,$colnam);
    my $tnam = "$schema.$tabl";
    my $canpk = 1;
    my $coldef = '';
    $ghstc2isautoinc{$colnam} = 0;
    $ghstc2cannull{$colnam} = 1;
    $ghstc2canfull{$colnam} = 0;
    $ghstc2virtual{$colnam} = 0;
    $ghstc2unsigned{$colnam} = 0;
    $ghstc2len{$colnam} = -1;
    $ghstc2hasdefault{$colnam} = 0;
    my $srid = undef;
    my $tclass = process_rseq('datatype_class');
    my $keylen = undef;
    my $canunique = 1;
    # sink for PK
    if ($tclass eq $SPATIAL or $tclass eq $JSON) {
        $canpk = 0;
        $canunique = 0;
    }
    # now we have final datatype class
    $ghstc2class{$colnam} = lc($tclass);
    $hpsgcolcanind{$cnam} = 0;
    if ($tclass ne $JSON) {
        $hpsgcolcanind{$cnam} = 1;
        $pgcandefault = 1;
    } else {
        # https://bugs.mysql.com/bug.php?id=113860
        $pgcandefault = 0;
    }
    $hpsgcolneedpref{$cnam} = ($tclass eq $LOB)? 1 : 0;
    my $dt = $tclass;
    $ghstc2just{$colnam} = $dt;
    my $can_autoinc = 0;
    if ($tclass eq $INTEGER) {
        $can_autoinc = 1;
        $dt = process_rseq('datatype_integer');
        $ghstc2just{$colnam} = $dt;
        if ($dt eq 'bit') {
            my $len = process_rseq('datatype_bit_len');
            if ($len ne $EMPTY) {
                $dt .= "($len)";
                $ghstc2len{$colnam} = $len;
            }
        } else {
            my $prob = dorand();
            if ($prob < $ghreal{'integer_unsigned_p'}) {
                $dt .= " unsigned";
                $ghstc2unsigned{$colnam} = 1;
            }
            if (dorand() < $ghreal{table_has_autoinc_p} and $pgcanautoinc and not $pghasautoinc) {
                $pghasautoinc = 1;
                $dt .= " auto_increment";
                $ghstc2isautoinc{$colnam} = 1;
                $pgcandefault = 0;
                if (dorand() < $ghreal{'pk_autoinc_p'}) {
                    $pgpkautoinc = 1;
                    $dt .= " primary key";
                    $ghstc2cannull{$colnam} = 0;
                } else {
                    $dt .= " unique";
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
    } elsif ($tclass eq 'floating') {
        $dt = process_rseq('datatype_floating');
        $ghstc2just{$colnam} = $dt;
    } elsif ($tclass eq $DATETIME) {
        $dt = process_rseq('datatype_datetime');
        $ghstc2just{$colnam} = $dt;
        if ($dt eq $DATETIME or $dt eq 'timestamp') {
            my $frac = process_rseq('datetime_fractional');
            $dt .= "($frac)" if ($frac ne $EMPTY);
        }
    } elsif ($tclass eq 'character') {
        $ghstc2canfull{$colnam} = 1;
        $dt = process_rseq('datatype_character');
        $ghstc2just{$colnam} = $dt;
        my $len = $dt eq 'char'? process_rseq('datatype_char_len') : process_rseq('datatype_varchar_len');
        $dt .= "($len)";
        $ghstc2len{$colnam} = $len;
        my $cs = process_rseq($CHARACTER_SET);
        $dt .= " character set $cs" if ($cs ne $EMPTY);
    } elsif ($tclass eq 'binary') {
        $dt = process_rseq('datatype_binary');
        $ghstc2just{$colnam} = $dt;
        my $len = '';
        if ($dt eq 'binary') {
            $len = process_rseq('datatype_binary_len');
            $keylen = process_rseq($DATATYPE_LOB_KEY_LEN);
            $keylen = $len if ($len ne $EMPTY and $keylen > $len);
            $keylen = 1 if ($len eq $EMPTY);
        } else {
            $len = process_rseq('datatype_varbinary_len');
        }
        if ($len ne $EMPTY) {
            $dt .= "($len)";
            $ghstc2len{$colnam} = $len;
        } else {
            $ghstc2len{$colnam} = 1;
        }
    } elsif ($tclass eq $LOB) {
        $canunique = 0;
        $dt = process_rseq('datatype_lob');
        $ghstc2just{$colnam} = $dt;
        $ghstc2canfull{$colnam} = 1 if ($dt =~ /text/);
        $keylen = process_rseq($DATATYPE_LOB_KEY_LEN);
    } elsif ($tclass eq 'enums') {
        $dt = process_rseq('datatype_enums');
        $ghstc2just{$colnam} = $dt;
        my $len = $dt eq 'enum'? process_rseq('datatype_enum_len') : process_rseq('datatype_set_len');
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
    if (defined($srid)) {
        if ($srid ne $EMPTY) {
            $dt .= " srid $srid";
            $ghstc2srid{$colnam} = $srid;
        } else {
            $ghstc2srid{$colnam} = 0;
        }
    }
    my $virt = ($ghstc2isautoinc{$colnam} or $pghavevcols >= $pgneedvcols)?
                 $EMPTY: process_rseq('column_virtuality');
    if ($virt ne $EMPTY) {
        my $expr = build_expression($tnam,'virtual',$colnam);
        $dt .= " as ($expr) $virt";
        ++$pghavevcols;
        $ghstc2virtual{$colnam} = 1;
        $pgcandefault = 0;
    }
    if (dorand() < $ghreal{'column_unique_p'} and $canunique and $psgneedind > 0) {
        $dt .= " unique";
        --$psgneedind;
    }
    my $vis = process_rseq('column_visibility');
    if (not $canpk) {
        if ($ghstc2isautoinc{$colnam} or $tclass eq $SPATIAL) {
            $vis =  $EMPTY;
        } else {
            $vis = process_rseq('column_null');
            $ghstc2cannull{$colnam} = ($vis eq 'not_null')? 0 : 1;
        }
        $vis =~ s/_/ /;
        $dt .= " $vis" if ($vis ne $EMPTY);
    } else {
        $psgtable_pk .= " , $cnam";
        $psgtable_pk .= "($keylen)" if (defined($keylen));
        my $dir = process_rseq('part_direction');
        $psgtable_pk .= " $dir" if ($dir ne $EMPTY);
        $ghstc2cannull{$colnam} = 0;
    }
    if (dorand() < $ghreal{'column_default_p'} and $pgcandefault) {
        my $expr = build_expression($tnam,$DEFAULT,$colnam);
        $dt .= " default $expr";
        $ghstc2hasdefault{$colnam} = 1;
    }
    $coldef = "$cnam $dt";
    $ghstc2just{$colnam} = lc($ghstc2just{$colnam});
    return $coldef;
}

# 1: dbh
# 2: stmt
# 3: key name string
# returns hashref or undef
sub gethashref {
    my ($dbh,$stmt,$key) = @ARG;
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY, "SUCCESS with --dry-run executing %s",$stmt);
        return $RC_OK;
    }
    my $was = $SIG{'__WARN__'};
    $SIG{'__WARN__'} = sub {1;};
    my $err = '';
    my $errstr = '';
    my $rc = $dbh->selectall_hashref($stmt,$key);
    if (not defined($rc)) {
        $err = $dbh->err();
        $errstr = $dbh->errstr();
        dosayif($VERBOSE_ANY, "ERROR %s executing selectall_hashref %s: %s",$err,$stmt,$errstr);
    } else {
        dosayif($VERBOSE_SOME, "SUCCESS executing selectall_hashref %s",$stmt);
    }
    $SIG{'__WARN__'} = $was;
    return $rc;
}

# 1: stmt
# 2: dbh
# 3: verbosity on error
# returns arrayref or undef
sub getarrayref {
    my ($stmt,$dbh,$vererr) = @ARG;
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY, "SUCCESS with --dry-run executing %s",$stmt);
        return $RC_OK;
    }
    my $was = $SIG{'__WARN__'};
    $SIG{'__WARN__'} = sub {1;};
    my $err = '';
    my $errstr = '';
    dosayif($VERBOSE_SOME, "about to execute selectall_arrayref %s +%s+",$stmt,$dbh);
    my $rc = $dbh->selectall_arrayref($stmt);
    if (not defined($rc)) {
        $err = $dbh->err();
        $errstr = $dbh->errstr();
        dosayif($vererr, "ERROR %s executing selectall_arrayref %s: %s",$err,$stmt,$errstr);
    } else {
        dosayif($VERBOSE_SOME, "SUCCESS executing selectall_arrayref %s",$stmt);
    }
    $SIG{'__WARN__'} = $was;
    return $rc;
}

# 1: stmt
# 2: dbh
# 3: verbosity
# returns RC_OK or RC_ERROR
sub runreport {
    my ($stmt,$dbh,$verbose) = @ARG;
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY, "SUCCESS with --dry-run executing %s",$stmt);
        return $RC_OK;
    }
    my $was = $SIG{'__WARN__'};
    $SIG{'__WARN__'} = sub {1;};
    my $rc = $dbh->do($stmt);
    my $err = '';
    my $errstr = '';
    if (not defined($rc)) {
        $rc = $RC_ERROR;
        $err = $dbh->err();
        $errstr = $dbh->errstr();
        dosayif($verbose, "ERROR %s executing %s: %s",$err,$stmt,$errstr);
    } else {
        $rc = $RC_OK;
        dosayif($verbose, "SUCCESS executing %s",$stmt);
    }
    $SIG{'__WARN__'} = $was;
    return $rc;
}

# add schema.table to global structures
# 1: schema.table which is expected to exist
# 2: db handle
# 3: croak on error
sub table_add {
    my ($tnam,$dbh,$strict) = @ARG;
    my $stmt = "SHOW CREATE TABLE $tnam";
    my $plcre = getarrayref($stmt,$dbh,$VERBOSE_SOME);
    if (not defined($plcre)) {
        if ($strict) {
            docroak("Error executing %s",$stmt);
        } else {
            dosayif($VERBOSE_SOME,"Error executing %s",$stmt);
            return $RC_ERROR;
        }
    }
    my $str = $plcre->[0]->[1];
    push(@glstables,$tnam);
    my ($schema,$table) = split(/\./,$tnam);

    my $inum = 0;
    forget_table($tnam);
    $ghst2createtable{$tnam} = $str;
    $str =~ s/^[^(]*\(/(/;
    my @lstr = split(/\n/,$str);

    my @lcols = ();
    my @lind = ();
    my @lnvcols = ();
    my @lpkcols = ();

    my $nlin = 0;
    my $incols = 0;
    my $last = '';
    foreach my $lin (@lstr) {
        chomp($lin);
        $last = $lin;
        ++$nlin;
        docroak("BAD line 1 '%s', must be ( in: %s",$lin,$str) unless ($nlin != 1 or $lin eq '(');
        dosayif($VERBOSE_MORE,"-%s",$lin);
        $incols = 1 if ($nlin == 2);    # also in indexes
        $incols = 0 if ($lin =~ /^\)/);
        if ($incols) {
            my $re = '^\s*(\`|PRIMARY\s+KEY\s+\(\`|(UNIQUE|FULLTEXT|SPATIAL)?\s+?KEY\s+\`)';
            docroak("BAD line %s '%s', must be like +%s+ in: %s",$nlin,$lin,$re,$str) unless ($lin =~ /$re/);
            if ($lin =~ /^\s*\`([^\`]+)\`/) {
                my $colname = $1;
                my $stc = "$tnam.$colname";
                dosayif($VERBOSE_MORE,"-found column %s.%s",$tnam,$colname);
                push(@lcols,$colname);
                if (not $lin =~ /\sGENERATED\s+ALWAYS\s+AS\s/) {
                    push(@lnvcols,$colname);
                    dosayif($VERBOSE_MORE,"-non virtual column %s.%s %s",$tnam,$colname,$lin);
                } else {
                    dosayif($VERBOSE_MORE,"-virtual column %s.%s %s",$tnam,$colname,$lin);
                }
                #   `col02` varchar(155) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
                my $coldes = $lin;
                $coldes =~ s/^\s*\`$colname\`\s*//;
                $coldes =~ /^([^ \(,]+)[ \(,]?/;
                docroak("NO DATATYPE for column %s in %s",$colname,$lin) if (not defined($1));
                my $dt = lc($1);
                $ghstc2class{$stc} = $ghdt2class{$dt};
                $ghstc2just{$stc} = $dt;
                $ghstc2canfull{$stc} = ($dt eq 'character' or $dt =~ /text/)? 1 : 0;
                $coldes =~ s/^$dt\(?//;
                $coldes =~ /^([,\d]+)/;
                $ghstc2len{$stc} = defined($1)? $1 : -1;
                $coldes =~ s/^[,\d*\)]*\s*//;
                $coldes =~ s/^CHARACTER\s+SET\s+([^\s]+)\s+COLLATE\s+([^\s]+)\s*//;
                if (defined($1)) {
                    $ghstc2charset{$stc} = $1;
                    $ghstc2collate{$stc} = $2;
                } else {
                    $ghstc2charset{$stc} = ':EMPTY';
                    $ghstc2collate{$stc} = ':EMPTY';
                }
                $coldes =~ s/[\s,]*$//;
                $coldes =~ s/\s*(AUTO_INCREMENT)\s*//;
                $ghstc2isautoinc{$stc} = defined($1)? 1 : 0;
                $coldes =~ s/\s*(unsigned)\s*//;
                $ghstc2unsigned{$stc} = defined($1)? 1 : 0;
                #/*!80003 SRID 4326 */
                $coldes =~ s/\s*\/\*!\d+\s+SRID\s+(\d+)\s+\*\/\s*//;
                $ghstc2srid{$stc} = defined($1)? $1 : -1;
                #'v1','v2','v3','v4')
                $coldes =~ s/\s*[^\)]+\)\s*// if ($dt eq 'enum' or $dt eq 'set');
                #GENERATED ALWAYS AS (NULL) STORED or VIRTUAL
                if ($coldes =~ s/^\s*GENERATED\s+ALWAYS\s+AS\s+\(/(/) {
                    $ghstc2virtual{$stc} = $coldes =~ /\(.*\)\s+STORED/? 1 : 2;
                    $coldes =~ s/(\(.*\))\s+(STORED|VIRTUAL)[,\s]*//;
                    docroak("BAD virtual column description for %s: +%s+ dt +%s+ IN %s",$stc,$dt,$coldes,$lin) if (not defined($1));
                    $ghstc2virtex{$stc} = $1;
                } else {
                    $ghstc2virtual{$stc} = 0;
                    $ghstc2virtex{$stc} = ':EMPTY';
                }
                if ($coldes =~ s/\s*NOT\s+NULL\s*//) {
                    $ghstc2cannull{$stc} = 0;
                } elsif ($coldes =~ s/\s*((NULL\s+)?DEFAULT)\s+NULL\s*//) {
                    $ghstc2cannull{$stc} = 1;
                } else {
                    $ghstc2cannull{$stc} = 1;   # longblob and such
                    $coldes =~ s/\s*NULL[,\s]*//;
                }
                if ($coldes =~ s/^\s*DEFAULT\s+(.+),?$//) {
                    docroak("BAD default for %s +%s+ dt +%s+ IN %s",$stc,$dt,$coldes,$lin) if (not defined($1));
                    $ghstc2default{$stc} = $1;
                    $ghstc2hasdefault{$stc} = 1;
                } else {
                    $ghstc2default{$stc} = ':EMPTY';
                    $ghstc2hasdefault{$stc} = 0;
                }
                docroak("BAD column description for %s, need empty string now: +%s+ dt +%s+ IN %s",$stc,$dt,$coldes,$lin) if ($coldes ne '');
            }
        }
    }

    $ghst2cols{$tnam} = \@lcols;
    $ghst2ind{$tnam} = \@lind;
    $ghst2pkcols{$tnam} = \@lpkcols;
    $ghst2nvcols{$tnam} = \@lnvcols;

    docroak("BAD last line +%s+ must end with ) in %s",$last,$str) if (not $last =~ /^\)/);
    $ghst2aes{$tnam} = $last =~ s/AUTOEXTEND_SIZE=(\d+)//? $1: -1;
    $ghst2charset{$tnam} = $last =~ s/DEFAULT\s+CHARSET=([^\s]+)//? $1: docroak("NO DEFAULT CHARSET in %s: %s",$tnam,$str);
    $ghst2col{$tnam} = $last =~ s/COLLATE=([^\s]+)//? $1: 'EMPTY';
    $ghst2stap{$tnam} = $last =~ s/STATS_PERSISTENT=(\d+)//? $1: -1;
    $ghst2sar{$tnam} = $last =~ s/STATS_AUTO_RECALC=(\d+)//? $1: -1;
    $ghst2sampl{$tnam} = $last =~ s/STATS_SAMPLE_PAGES=(\d+)//? $1: -1;
    $ghst2kbs{$tnam} = $last =~ s/KEY_BLOCK_SIZE=(\d+)//? $1: -1;
    $ghst2rof{$tnam} = $last =~ s/ROW_FORMAT=([^\s]+)//? $1: 'EMPTY';
    $ghst2comp{$tnam} = $last =~ s/COMPRESSION=([^\s]+)//? $1: 'EMPTY';
    $last =~ s/\)//;
    $last =~ s/ENGINE=InnoDB//;
    $last =~ s/\/\*\s?!?\d+\s+\*\///;
    $last =~ s/AUTO_INCREMENT=[\d]+//g;   # for discovery
    $last =~ s/\s//g;
    docroak("BAD last +%s+ not all eliminated in %s",$last,$str) if ($last ne '');

    # indexes
    $stmt = "SELECT *, CONCAT(INDEX_NAME,'.',REPEAT('0',5-LENGTH(SEQ_IN_INDEX)),SEQ_IN_INDEX) PART_ID FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$schema' AND TABLE_NAME = '$table'";
    my $key = 'PART_ID';
    my $phind = gethashref($gdbh,"SELECT *, CONCAT(INDEX_NAME,'.',REPEAT('0',5-LENGTH(SEQ_IN_INDEX)),SEQ_IN_INDEX) PART_ID FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$schema' AND TABLE_NAME = '$table'",$key);
    if (not defined($phind)) {
        if ($strict) {
            docroak("For %s failed to gethasref of %s with key column %s",$tnam,$stmt,$key);
        } else {
            dosayif($VERBOSE_SOME,"For %s failed to gethasref of %s with key column %s",$tnam,$stmt,$key);
            return $RC_ERROR;
        }
    }
    
    my %hiname = ();
    foreach my $ipart (sort(keys(%$phind))) {
        my ($iname,$num) = split(/\./,$ipart);
        ++$hiname{$iname};
    }
    @lind = sort(keys(%hiname));
    foreach my $ind (@lind) {
        my $sti = "$tnam.$ind";
        my @lcols = ();
        my @llen = ();
        my @lcot = ();
        my @lparts = sort grep {/^$ind\./} sort(keys(%$phind));
        foreach my $part (@lparts) {
            my $phpart = $phind->{$part};
            if ($phpart->{'INDEX_NAME'} eq 'PRIMARY') {
                $ghsti2kind{$sti} = 'primary';
            } elsif ($phpart->{'INDEX_TYPE'} eq 'BTREE') {
                $ghsti2kind{$sti} = $phpart->{'NON_UNIQUE'} == 0? 'unique' : 'key';
            } else {
                $ghsti2kind{$sti} = lc($phpart->{'INDEX_TYPE'});
            }
            my $len = -1;
            my $cot = 0;
            if (defined($phpart->{'SUB_PART'})) {
                $len = $phpart->{'SUB_PART'};
                $cot = 1;
            }
            if (defined($phpart->{'EXPRESSION'})) {
                $len = $phpart->{'EXPRESSION'};
                $cot = 2;
            }
            push(@llen,$len);
            push(@lcot,$cot);
            push(@lcols,(defined($phpart->{'COLUMN_NAME'})? $phpart->{'COLUMN_NAME'} : ':expr'));
            
        }
        $ghsti2cols{$sti} = \@lcols;
        $ghsti2lens{$sti} = \@llen;
        $ghsti2cotype{$sti} = \@lcot;
    }

    return $RC_OK;
}

# 1: schema.table
sub forget_table {
    my ($tnam) = @ARG;
    foreach my $pha (@ghstlist) {
        foreach my $cnam (sort(keys(%$pha))) {
            delete($pha->{$cnam}) if ($cnam =~ /^$tnam\./);
        }
    }
    foreach my $ph (@ghstilist) {
        foreach my $sti (sort(keys(%$ph))) {
            delete $ph->{$sti} if ($sti =~ /^$tnam\./);
        }
    }
    foreach my $ph (@ghstcolist) {
        foreach my $sti (sort(keys(%$ph))) {
            delete $ph->{$sti} if ($sti =~ /^$tnam\./);
        }
    }
    return $RC_OK;
}

# returns RC_OK if all SQL is executed successfully, othrwise RC_WARNING
sub db_create {
    my $rc = $RC_OK;
    # CREATE TABLE SQL for all tables
    %hpgstcol2def = ();      # obscure pk related see code

    my $nschemas = $ghreal{'schemas'};
    if (not $nschemas =~ /^\d+$/ or $nschemas <= 0) {
        docroak("For db creation schemas must be a positive integer, not '%s'",$nschemas);
    }
    dosayif($VERBOSE_ANY," will create %s schemas", $nschemas);
    my @lsesql = ();
    foreach my $sn (1..$nschemas) {
        process_rseq('schema_name_format');
        my $nam = sprintf($ghreal{'schema_name_format'},$sn);
        my $drop = $ghreal{'schema_drop_first'} eq $YES? "DROP SCHEMA $nam" : '';
        push(@lsesql,$drop) if ($drop ne '');
        push(@glschemas,$nam);
        push(@lsesql, "CREATE SCHEMA $nam");
    }
    foreach my $stmt (@lsesql) {
        my $subrc = runreport($stmt,$gdbh,$VERBOSE_ANY);
        $rc = $RC_WARNING if ($subrc != $RC_OK);
    }

    my $ntables = $ghreal{'tables_per_schema'};
    if (not $ntables =~ /^\d+$/ or $ntables <= 0) {
        docroak("For db creation tables_per_schema must be a positive integer, not '%s'",$ntables);
    }
    my %hs2ntables = ();
    foreach my $snam (@glschemas) {
        $hs2ntables{$snam} = $ntables;
    }
    foreach my $snam (@glschemas) {
        # for each table
        for my $ntab (1..$hs2ntables{$snam}) {
            my $tsql = '';
            # table structure
            $psgneedind = process_rseq("indexes_per_table");
            my $frm = process_rseq("table_name_format");
            my $tnam = "$snam.".sprintf($frm,$ntab);
            $ghst2createtable{$tnam} = ':TBD';
            $pghavevcols = 0;
            $pgcanautoinc = 1 if (dorand() < $ghreal{'table_has_autoinc_p'});
            $tsql .= "CREATE TABLE $tnam (";
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
            my $ncolspk = process_rseq('columns_pk');
            $pgcolsnonpk = process_rseq('columns_non_pk');
            $psgtable_pk = '';
            %hpsgcolcanind = ();
            %hpsgcolneedpref = ();
            %hpgstcol2def = ();
            my @lcols = ();
            foreach my $ncol (1..$ncolspk) {
                $frm = process_rseq("column_pk_name_format");
                my $colsn = sprintf($frm,$ncol);
                my $colnam = "$tnam.$colsn";
                push(@lcols,$colsn);
                $hpgstcol2def{$colnam} = 1;      # mark PK
            }
            foreach my $ncol (1..$pgcolsnonpk) {
                $frm = process_rseq("column_non_pk_name_format");
                my $colsn = sprintf($frm,$ncol);
                my $colnam = "$tnam.$colsn";
                push(@lcols,$colsn);
                $hpgstcol2def{$colnam} = 0;
            }
            $pgneedvcols = process_rseq('virtual_columns_per_table');
            $pgneedvcols = scalar(@lcols)-1 if ($pgneedvcols >= scalar(@lcols));
            if (dorand() < $ghreal{'pk_first_p'}) {
                dosayif($VERBOSE_DEV," table %s will have pk columns first",$tnam);
            } else {
                dosayif($VERBOSE_DEV,"table %s will NOT have pk columns first",$tnam);
                @lcols = doshuffle(@lcols);
            }
            my $indnum = 0;
            foreach my $cnam (@lcols) {
                # each column in table
                my $colnam = "$tnam.$cnam";
                my $coldef = generate_column_def('create_table',$colnam);
                # small chance there will be no keys after the last column
                $coldef .= ',' unless ($pgpkautoinc and $psgneedind == 0 and $cnam eq $lcols[scalar(@lcols)-1]);
                $tsql .= $coldef;
            }
            $psgtable_pk =~ s/^ *,+/ PRIMARY KEY(/;
            my $table_indexes = '';
            $tsql .= "$psgtable_pk)"
              unless ($pgpkautoinc);
            my @lindcols = sort(keys(%hpsgcolcanind));
            $psgneedind = 0 if (scalar(@lindcols) == 0);
            foreach my $inum (1..$psgneedind) {
                my $needcols = process_rseq('parts_per_index');
                if ($needcols eq 'ALL') {
                    $needcols = scalar(@lindcols);
                }
                my $fulltext = dorand() < $ghreal{'fulltext_index_p'}? 'FULLTEXT ' : '';
                my @lhavefull = grep {$ghstc2canfull{"$tnam.$_"}} @lindcols;
                $fulltext = '' if (scalar(@lhavefull) == 0);
                my $uniq = (dorand() < $ghreal{'index_unique_p'} and $fulltext eq '')? 'UNIQUE ' : '';
                my $iline = ", ${fulltext}${uniq}INDEX ind$inum (";
                ++$indnum;
                # pk may not be before
                $iline =~ s/,// if ($indnum == 1 and $pgpkautoinc);
                my @lhavecols = $fulltext eq ''? doshuffle(@lindcols) : doshuffle(@lhavefull);
                my $hasfun = 0;
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
                    my $type = process_rseq('index_part_type');
                    if ($type eq 'column') {
                        $iline .= ", $thiscol";
                        if (($ghstc2class{$coname} eq 'character' and $type eq 'column' and process_rseq('index_prefix_use') eq 'yes')
                            or $hpsgcolneedpref{$thiscol}) {
                            my $lenp = process_rseq('index_prefix_len');
                            $lenp = $ghstc2len{$coname}
                              if (dorand() < process_rseq($VKCHAR) and $ghstc2len{$coname} > 0 and $lenp > $ghstc2len{$coname});
                            $iline .= "($lenp)" if ($lenp ne $EMPTY);
                        }
                    } else { #function
                        $iline .= ", (length($thiscol))"; #todo more
                        $hasfun = 1;
                    }
                    my $dir = process_rseq('part_direction');
                    $iline .= " $dir" if ($dir ne $EMPTY);
                }
                my $was = $iline;
                $iline =~ s/\( *,/(/;
                $iline .= ")";
                my $vis = process_rseq('index_visibility');
                $iline .= " $vis" if ($vis ne $EMPTY);
                if (not $iline =~ /\(\)/) {
                    $tsql .= $iline;
                } else {
                    $tsql =~ s/,$//;
                }
                
            }
            $tsql .= $tail;
            runreport("DROP TABLE IF EXISTS $tnam",$gdbh,$VERBOSE_SOME);
            runreport($tsql,$gdbh,$VERBOSE_SOME);
        }
    }

    if (not $ghasopt{$DRYRUN}) {
        # clean up records for tables that failed to create
        dosayif($VERBOSE_ANY,"remove records for tables that failed to create");
        my $badtables = 0;
        foreach my $tnam (sort(keys(%ghst2createtable))) {
            my $plcre = getarrayref("SHOW CREATE TABLE $tnam",$gdbh,$VERBOSE_SOME);
            if (not defined($plcre)) {
                ++$badtables;
                dosayif($VERBOSE_ANY," table %s does not exist, forgetting it",$tnam);
                forget_table($tnam);
            } else {
                ++$gntables;
                table_add($tnam,$gdbh,1);
            }
        }
        dosayif($VERBOSE_ANY," we have %s good tables, forgot %s bad tables",$gntables,$badtables);
        docroak("Cannot proceed, no good tables. CROAK.") if ($gntables == 0);
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
    $lex = "($lex)" if (dorand() < $ghreal{$par});
    # consider prefix with NOT
    if (dorand() < $ghreal{'where_expression_not_p'}) {
        $lex = " NOT $lex";
        # and wrap that
        $lex = "($lex)" if (dorand() < $ghreal{$par});
    }
    # consider IS [NOT] null again
    my $isnull = process_rseq('operator_null');
    if ($isnull ne $EMPTY) {
        $isnull =~ s/_/ /g;
        $lex = "$lex $isnull";
        # and wrap that
        $lex = "($lex)" if (dorand() < $ghreal{$par});
    }
    return $lex;
}

# 1: schema.table
# 2: parameter name for no where
# returns WHERE clause with WHERE
sub build_where {
    my ($tnam,$parm) = @ARG;
    dosayif($VERBOSE_MORE, "build_where enter");
    if (dorand() < $ghreal{$parm}) {
        my $rc = dorand() < $ghreal{'where_all_by_no_where_p'}? '' : 'WHERE (1 = 1)';
        dosayif($VERBOSE_MORE, "build_where return simple");
        return $rc
    }

    my $expr = '';
    my $dep = process_rseq('where_logical_depth');
    # columns we will use
    my @lcols = grep {dorand() < $ghreal{'where_column_p'}} @{$ghst2cols{$tnam}};
    @lcols = scalar(@lcols) == 0? @{$ghst2cols{$tnam}} : @lcols;
    my $havecols = scalar(@lcols);
    for (my $level = 1; $level <= $dep; ++$level) {
        my $add = '';
        my $len = process_rseq('where_logical_length');
        for (my $enum = 1; $enum <= $len; ++$enum) {
            # choose column to build expression on
            my $sucolnam = $lcols[int(dorand()*$havecols)];
            my $colnam = "$tnam.$sucolnam";
            my $dtclass = $ghstc2class{$colnam};
            my $dt = $ghstc2just{$colnam};
            #croak("$tnam:where:$colnam: no datatype or datatype class for $colnam. CROAK.") if (not defined($dt) or not defined($dtclass));
            $dtclass = 'x' if (not defined($dtclass));
            $dt = 'x' if (not defined($dt));
            $dtclass = lc($dtclass);
            $dt = lc($dt);
            my $haveop = defined($ghreal{"operator_logical_$dt"})?
                           "operator_logical_$dt" :
                           (defined($ghreal{"operator_logical_$dtclass"})? "operator_logical_$dtclass" : undef);
            dosayif($VERBOSE_MORE, "go build_expression lev %s/%s enum %s/%s for %s.%s",$level,$dep,$enum,$len,$tnam,$colnam);
            my $lex = build_expression($tnam,'where',$colnam);
            # consider IS [NOT] null
            my $isnull = process_rseq('operator_null');
            if ($isnull ne $EMPTY) {
                $isnull =~ s/_/ /g;
                $lex = "$lex $isnull";
            } elsif (defined($haveop)) {
                my $op = process_rseq($haveop);
                $op =~ s/o\@//;
                $op =~ s/MINUS/-/; # todo do move to process
                $op =~ s/N=/!=/; # todo do move to process
                dosayif($VERBOSE_MORE, "go build_expression haveop lev %s/%s enum %s/%s for %s.%s",$level,$dep,$enum,$len,$tnam,$colnam);
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

    $expr = pnotnull($expr,'where');
    $expr = "WHERE $expr";
    dosayif($VERBOSE_MORE, "build_where return");
    return $expr;
}

# 1: schema.table
# 2: test parameter to use for selection
# 3: kind: if not 'select', do not use virtual columns
#          if UPDATE, return ref array
sub table_columns_subset {
    my ($tnam, $parm, $kind) = @ARG;
    my @lcall = $kind eq 'select'? @{$ghst2cols{$tnam}} : @{$ghst2nvcols{$tnam}};
    @lcall = @{$ghst2cols{$tnam}} if (scalar(@lcall) == 0);
    my @lc = grep {dorand() < $ghreal{$parm}} @lcall;
    push(@lc,$lcall[0]) if (scalar(@lc) == 0);
    my $rc = $kind eq 'update'? \@lc : join(',',@lc);
    return $rc;
}

# get random table
sub table_get {
    my $tnam = $glstables[int(dorand()*$gntables)];
    return $tnam;
}

# returns statement, subkind
sub stmt_select_generate {
    my $stmt = 'SELECT';
    my $sub = 'SEL';
    if (dorand() < $ghreal{'select_distinct_p'}) {
        $stmt .= ' DISTINCT';
        $sub .= 'D';
    }
    # determine schema.table
    my $tnam = table_get();
    my $tosel = process_rseq('select_how');
    if ($tosel eq 'all') {
        $tosel = '*';
        $sub .= 'S';
    } elsif ($tosel eq 'count') {
        $tosel = 'COUNT(*)';
        $sub .= 'C';
    } else {
        $tosel = table_columns_subset($tnam,$SELECT_COLUMN_P,'select');
    }
    $stmt .= " $tosel FROM $tnam";
    my $wher = build_where($tnam,'select_where_all_p');
    $stmt .= " $wher";
    return $stmt,$sub;
}

# returns statement
sub stmt_insel_generate {
    # determine schema.table
    my $tnam = table_get();
    my $stmt .= " INSERT into $tnam SELECT * FROM $tnam";
    my $wher = build_where($tnam,'select_where_all_p');
    $stmt .= " $wher";
    #docroak("#debug+%s+",$stmt);
    return $stmt;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_decimal {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $bas = process_rseq('decimal_value');
    my $mas = defined($ghstc2len{$col})? $ghstc2len{$col} : $bas;
    $bas = $mas if (dorand() < process_rseq($VKCHAR) and $bas > $mas);
    my $value = dorand()*(10.0**$bas);
    $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_int');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_tinyint {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_tinyint');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_bigint {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_bigint');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_bit {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_bit');
    my $valmax = defined($ghstc2len{$col})? 2**$ghstc2len{$col}-1 : $value;
    $value = $valmax if (dorand() < process_rseq($VKCHAR) and $value > $valmax);
    $value = abs($value);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_smallint {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_smallint');
    if ($ghstc2unsigned{$col}) {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_mediumint {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('value_mediumint');
    if (not defined($ghstc2unsigned{$col}) or $ghstc2unsigned{$col} == 1) { #todo consider
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
    } else {
        $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    }
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_float {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $exp = process_rseq('float_value_exp');
    my $value = $exp eq $EMPTY? value_generate_decimal($col,$kind) : sprintf("%sE%s",dorand(),$exp);
    $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_double {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $exp = process_rseq('double_value_exp');
    my $value = $exp eq $EMPTY? value_generate_decimal($col,$kind) : sprintf("%sE%s",dorand(),$exp);
    $value = -$value if (dorand() < $ghreal{$NUMBER_REVERSE_SIGN_LEGITIMATE_P});
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_char {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_char_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = 'c' x $valen;
    $value = "'$value'";
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_varbinary {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_varbinary_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('x',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_binary {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_binary_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('y',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_tinyblob {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_tinylob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('t',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_longblob {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_longlob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('l',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_datetime {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my ($year,$month,$day) = value_generate_date($col,$kind,0);
    my ($hour,$minute,$sec,$micr) = value_generate_time($col,$kind,1);
    my $value = sprintf("%04s-%02s-%02s %02s:%02s:%02s",$year,$month,$day,$hour,$minute,$sec);
    $value .= sprintf(".%06s",$micr) if ($micr ne $EMPTY);
    $value = "'$value'";
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: return list
# returns: value as string suitable to add to VALUES, if 2 is TRUE, returns list of h,m,s,ms as strings, including EMPTY for ms
sub value_generate_time {
    my $col = $ARG[0];
    my $kind = $ARG[1];
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $retlist = (defined($ARG[2]) and $ARG[2] == 1)? 1 : 0;
    my $hor = $retlist? process_rseq('datetime_hour_value') :  process_rseq('time_hour_value');
    my $mit = process_rseq('datetime_minute_value');
    my $sec = process_rseq('datetime_second_value');
    my $micr = process_rseq('datetime_microsecond_value');
    if ($retlist) {
        my @lval = ($hor,$mit,$sec,$micr);
        return @lval;
    } else {
        my $value = "$hor:$mit:$sec";
        $value .= ".$micr" if ($micr ne $EMPTY);
        $value = "'$value'";
        return $value;
    }
    docroak('internal error: reached unreachable code. CROAK.');
}

# 1: schema.table.column
# 2: kind e.g. default
# 3: true if timestamp wanted, false if datetime, undef if date
# returns: value as string suitable to add to VALUES, or if defined 2, list of year month day:w
sub value_generate_date {
    my $col = $ARG[0];
    my $kind = $ARG[1];
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $ists = defined($ARG[2])? $ARG[2] : undef;
    my $month = process_rseq('datetime_month_value');
    my $day = process_rseq('datetime_day_value');
    my $year = $ists? process_rseq('timestamp_year_value') : process_rseq('datetime_year_value');
    if (defined($ists)) {
        my @lval = ($year,$month,$day);
        return @lval;
    } else {
        my $value = sprintf("'%04d-%02d-%02d'",$year,$month,$day);
        return $value;
    }
    docroak('internal error: reached unreachable code. CROAK.');
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_timestamp {
    my ($col,$kind) = @ARG;
    my ($year,$month,$day) = value_generate_date($col,$kind,1);
    my ($hour,$minute,$sec,$micr) = value_generate_time($col,$kind,1);
    my $value = sprintf("%04s-%02s-%02s %02s:%02s:%02s",$year,$month,$day,$hour,$minute,$sec);
    $value .= sprintf(".%06s",$micr) if ($micr ne $EMPTY);
    $value = "'$value'";
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_multipolygon {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multipolygon_len');
    for my $n (1..$len) {
        $value .= ','.value_generate_polygon($col,$kind,1);
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
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
    docroak("inkind is not defined. CROAK.") if (not defined($inkind));
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multilinestring_len');
    for my $n (1..$len) {
        $value .= ','.value_generate_linestring($col,$kind,1);
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $raw = defined($ARG[2])? $ARG[2] : 0;
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = '';
    my $len = process_rseq('value_multigeometry_len');
    for my $n (1..$len) {
        my $subkind = process_rseq('multigeometry_kind');
        my $subval = "value_generate_".lc($subkind);
        docroak("value_generate_%s() is not defined. CROAK.",$subval) if (not defined($ghvgsub{$subval}));
        my $termval = $ghvgsub{$subval}->($col,$kind,1);
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $subkind = 'value_generate_'.lc(process_rseq('geometry_kind'));
    docroak("%s() is not defined. CROAK.",$subkind) if (not defined($ghvgsub{$subkind}));
    my $value = $ghvgsub{$subkind}->($col,$kind);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_json {
    my ($col,$inkind) = @ARG;
    docroak("inkind is not defined. CROAK.") if (not defined($inkind));
    my $value = "{}";
    my $kind = process_rseq('value_json_kind');
    if ($kind eq 'SIMPLEML') {
        # multilevel to be developed further todo
        tie my %ha, 'Tie::IxHash';
        %ha = ('a' => '1a', 'b' => '2b', 'c' => ['l1','l2',3], 'd' => {'x' => 1});
        $value = encode_json(\%ha);
    } elsif ($kind eq 'FROMSCRIPT') {
        # local from script
        $gh2json{$RAND} = dorand();
        $value = encode_json(\%gh2json); #todo parameter and shorter
    } elsif ($kind eq 'REFARRAY') {
        # local ref array
        my @l = ();
        my $len = process_rseq('value_json_len');
        foreach my $i (1..$len) {
            push(@l,dorand()*$i);
        }
        $value = encode_json(\@l);
    } elsif ($kind eq 'SCALAR') { 
        # local scalar
        $value = encode_json('j'.process_rseq('value_json_len'));
    } elsif ($kind eq 'REFHASH') { 
        # local ref hash
        tie my %hl, 'Tie::IxHash';
        %hl = ();
        my $len = process_rseq('value_json_small_len');
        foreach my $i (1..$len) {
            $hl{$i} = 'abc' x $i;
        }
        $value = encode_json(\%hl);
    }
    $value =~ s/'/\\'/g;
    $value = "'$value'";
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_year {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $value = process_rseq('year_value');
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_set {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $len = process_rseq('datatype_set_value_len');
    $len = $ghstc2len{$col} if (dorand() < process_rseq($VKCHAR) and defined($ghstc2len{$col}) and $len > $ghstc2len{$col});
    my $value = '';
    foreach my $num (1..$len) {
        $value .= ",v$num";
    }
    $value =~ s/^,//;
    $value = "'$value'";
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_enum {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 3; #todo consider parm
    my $num = int(dorand()*$len)+1;
    my $value = "\"v$num\"";
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_mediumlob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('m',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
}

# 1: schema.table.column
# 2: kind e.g. default
# returns: value as string suitable to add to VALUES
sub value_generate_blob {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_lob_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
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
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_varchar_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('b',$valen)";
    $value = "($value)" if ($kind eq $DEFAULT);
    return $value;
};

# 1: schema.table
# 2: column list
# returns "V1, V2, ... " string and ref array of the same
# used only for insert
sub build_insert_values {
    my ($tnam, $plcols) = @ARG;
    my $values = '';
    foreach my $col (@$plcols) {
        my $colnam = "$tnam.$col";
        # consider DEFAULT
        if (dorand() < $ghreal{'insert_default_p'} and $ghstc2hasdefault{$colnam}) {
            $values .= ", DEFAULT";
            next;
        }
        # consider null
        docroak("undefined autoinc info for '%s' with '%s'",$colnam,"@{$plcols}") if (not defined($ghstc2isautoinc{$colnam}));
        if ($ghstc2isautoinc{$colnam}) {
            if (dorand() >= $ghreal{'autoinc_explicit_value_p'}) {
                $values .= ', null';
                next;
            }
        }
        if ($ghstc2cannull{$colnam} == 1) {
            if (dorand() < $ghreal{'null_legitimate_p'}) {
                $values .= ', null';
                next;
            }
        } else {
            if (dorand() < $ghreal{'null_illegitimate_p'}) {
                $values .= ', null';
                next;
            }
        }
        my $val =  build_expression($tnam,'insert',$colnam);
        $values .= ", $val";
    }
    $values =~ s/^, //;

    return $values;
}

# returns statement
sub stmt_delete_generate {
    my $stmt = '';
    # determine schema.table
    my $tnam = table_get();
    my $wher = build_where($tnam,'delete_where_all_p');
    $stmt = "DELETE FROM $tnam $wher";
    return $stmt;
}

# returns statement
sub stmt_update_generate {
    dosayif($VERBOSE_MORE, "stmt_update_generate enter");
    my $stmt = '';
    # determine schema.table
    my $tnam = table_get();
    dosayif($VERBOSE_MORE, "tnam %s",$tnam);
    my $plcols = table_columns_subset($tnam,'update_column_p','update');
    my $n = 0;
    foreach my $col (@$plcols) {
        dosayif($VERBOSE_MORE, "go build_expression for %s","$tnam.$col");
        my $expr = build_expression($tnam,'update',"$tnam.$col");
        $stmt .= ", $col = $expr";
    }
    $stmt =~ s/^,//;
    dosayif($VERBOSE_MORE, "go build_where for %s",$tnam);
    my $wher = build_where($tnam,'update_where_all_p');
    $stmt = "UPDATE $tnam SET $stmt $wher";
    dosayif($VERBOSE_MORE, "stmt_update_generate return");
    return $stmt;
}

# returns statement
sub stmt_insert_generate {
    my $stmt = 'INSERT into ';
    # determine schema.table
    my $tnam = table_get();
    # https://bugs.mysql.com/?id=113951&edit=2
    my @lcols = @{$ghst2nvcols{$tnam}};
    $stmt .= " $tnam (".join(',',@lcols).')';
    my $values = build_insert_values($tnam,\@lcols);
    $stmt .= " VALUES ($values)";
    return $stmt;
}

# returns statement
sub stmt_replace_generate {
    my $stmt = 'REPLACE into ';
    # determine schema.table
    my $tnam = table_get();
    # https://bugs.mysql.com/?id=113951&edit=2
    my @lcols = @{$ghst2nvcols{$tnam}};
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
# returns statement, subtype
sub stmt_alter_generate {
    my $tnam = $ARG[0];
    my $stmt = '';
    my $len = process_rseq('load_alter_length');
    my $subt = "ALTER$len";
    for my $clausen (1..$len) {
        my $kind = process_rseq('load_alter_kind');
        if ($kind eq 'DROP_COL') {
            # select column to drop
            my @lcols = @{$ghst2cols{$tnam}};
            my $cnam = $lcols[int(dorand()*scalar(@lcols))];
            $stmt .= "DROP COLUMN $cnam, ";
            $subt .= 'dC';
        } elsif ($kind eq 'ADD_COL') {
            my $colnam = sprintf("%s.added_col_%s",$tnam,int(dorand()*1000));
            my $coldef = generate_column_def('alter_table',$colnam); #todo const
            $stmt .= "ADD COLUMN $coldef, ";
            $subt .= 'aC';
        } elsif ($kind eq 'TABLE_EB') {
            $stmt .= "ENGINE=InnoDB, ";
            $subt .= 'eB';
        }
    }
    $stmt =~ s/, *$//;
    $stmt = "ALTER TABLE $tnam $stmt";
    return ($stmt,$subt);
}

sub hdump {
    my $ph = $ARG[0];
    my $nl = (defined($ARG[1]) and $ARG[1])? "\n" : '';
    my $rc = '';
    foreach my $key (sort(keys(%$ph))) { 
        $rc .= ",$nl $key: $ph->{$key}";
    }
    $rc =~ s/, //;
    return $rc;
}

# 1: thread number, absolute
# 2: thread kind
# 3: random seed
sub server_load_thread {
    my $tnum = $ARG[0];
    my $tkind = $ARG[1];
    my $rseed = $ARG[2];
    my $starttime = time();
    tie %gh2json, 'Tie::IxHash';
    my $serterm = ($ghreal{'server_terminate'} eq 'yes');

    # adjust load thread parameters
    if ($tkind ne '') {
        foreach my $parm (sort(grep {$_ =~ /${UKIND}$tkind$/} sort(keys(%ghtest)))) {
            my $soparm = $parm;
            $soparm =~ s/${UKIND}$tkind$//;
            dosayif($VERBOSE_ANY,"-for %s thread #%s replacing %s of %s with %s of %s in ghtest",
              $tkind,$tnum,$soparm,$ghtest{$soparm},$parm,$ghtest{$parm});
            $ghtest{$soparm} = $ghtest{$parm};
            next if (not defined($ghreal{$parm}));
            dosayif($VERBOSE_ANY,"-for %s thread #%s replacing %s of %s with %s of %s in ghreal",
              $tkind,$tnum,$soparm,$ghreal{$soparm},$parm,$ghreal{$parm});
            $ghreal{$soparm} = $ghreal{$parm};
        }
    }
    
    my $finfile = "$ghreal{'tmpdir'}/$PID.fin";
    my $howlong = $ghreal{$TEST_DURATION};
    my $maxcount = $ghreal{'load_max_stmt'};
    my $lasttime = $starttime + $howlong;
    my $txnin = 0;
    my $txnstmt = 0;
    my $txnstart = 0;
    my $ec = $EC_OK;
    my %herr2count = ();      # Eerr->count includes EFAIL and such
    my %herr2errstr = ();      # Eerr -> errstr ! stmt last
    my %herrkind2count = ();      # Eerr kind errstr ->count

    sub msg_adjust_simple {
        my $msg = $ARG[0];
        my $rc = $msg;
        $rc =~ s/at row\s[0-9]*/at row N/g;
        $rc =~ s/entry\s'[^']*'/entry CONST/g;
        $rc =~ s/key\s'[^']*'/key KEYNAME/g;
        $rc =~ s/value:\s?'?[^']*'?/value VALUE/g;
        $rc =~ s/[iI]ncorrect\s+[^\s]+\s+value/Incorrect TYPE value/g;
        $rc =~ s/range in\s'[^']*'/range in EXPR/g;
        $rc =~ s/column\s'[^']*'/column COLNAME/g;
        $rc =~ s/check the manual that corresponds to your MySQL server version for the right syntax/RTFM/g;
        $rc =~ s/for\s+CAST\s+to\s+[^\s]+\s+from\s+column\s+[^s]+/for CAST to TYPE from column COLNAME/g;
        $rc =~ s/[^\s]+\s+(UNSIGNED\s+)?value is out of range/TYPE value is out of range/g;
        $rc =~ s/in\s+\'[^\']*\'/in PLACE/g;
        $rc =~ s/from column [\s+] at /from column COLNAME at/g;
        $rc =~ s/Column\s'[^']*'/Column COLNAME/g;
        $rc =~ s/\s+DROP\s+'[^']*'/ DROP COLNAME/g;
        $rc =~ s/arguments\s+to\s+[^\s]*/arguments to FUNC/g;
        $rc =~ s/Field\s'[^']*'/Field COLNAME/g;
        $rc =~ s/syntax to use near '.*$/syntax to use near HERE/g;
        $rc =~ s/out of range in function [^ ]+\./out of range in function GEOFUNC/;
        $rc =~ s/(Longitude|Latitude)\s+[\d.-]+\s+/LONGLAT VALUE /;
        $rc =~ s/within\s+[\(\)\[\]\d,\s.-]+/within RANGE/;
        $rc =~ s/Truncated Incorrect TYPE value VALUE.*/Truncated Incorrect TYPE value VALUE/;
        return $rc;
    }

    sub msg_adjust {
        my $msg = $ARG[0];
        my $rc = $msg;
        $rc =~ s/'[^']*'/QQ/g;
        $rc =~ s/"[^"]*"/DD/g;
        $rc =~ s/ALTER\s+TABLE\s+[^\s]+\s+/ALTER TABLE TT /ig;
        $rc =~ s/CHECK\s+TABLE\s+[^\s]+\s+/CHECK TABLE TT /ig;
        $rc =~ s/INSERT\s+INTO\s+[^\s]+\s+\([^\)]+\)\s+/INSERT INTO TT CC /ig;
        $rc =~ s/SELECT\s+[^\s]+\s+FROM\s+[^\s]+\s+/SELECT EE FROM TT /ig;
        $rc =~ s/UPDATE\s+[^\s]+\s+SET\s+[^\s]+/UPDATE TT SET CC/ig;
        $rc =~ s/,\s*[^\s]+\s*=\s*/, CC = /ig;
        $rc =~ s/\s+(AND|OR)\s+/ AA /ig;
        $rc =~ s/\s+[-+*\%\/<>^]+?/ OO/ig;
        while ($rc =~ /[\(\)]/) {
            my $was = $rc;
            $rc =~ s/\(\)/SS/g;
            $rc =~ s/\([^\)\(]+\)/PP/g;
            if ($rc =~ /[\(]/ and not $rc =~ /[\)]/) {
                $rc =~ s/[\(]+/UL/g;
                dosayif($VERBOSE_SOME,"-UNBALANCED left: +%s+ from +%s+",$rc,$msg);
                #docroak("semiCROAK: UNBALANCED left: +%s+ from +%s+",$rc,$msg);
            }
            if ($rc =~ /[\)]/ and not $rc =~ /[\(]/) {
                $rc =~ s/[\)]+/UR/g;
                dosayif($VERBOSE_SOME,"-UNBALANCED right +%s+ from +%s+",$rc,$msg);
                #docroak("semiCROAK: UNBALANCED right +%s+ from +%s+",$rc,$msg);
            }
            if ($was eq $rc) {
                $rc =~ s/[\)]+/UBR/g;
                $rc =~ s/[\(]+/UBL/g;
                dosayif($VERBOSE_SOME,"-UNBALANCED both +%s+ from +%s+",$rc,$msg);
                #docroak("semiCROAK: UNBALANCED both +$rc+ from +$msg+");
            }
        }
        $rc =~ s/CC\s*=\s+[a-zA-Z0-9_]+\s?(,\s*CC\s*=\s+[a-zA-Z0-9_]+\s?)/LL /g;
        $rc =~ s/[a-zA-Z0-9_]+PP/FF /g;
        $rc =~ s/Incorrect arguments to [^ ]+/Incorrect arguments to FF/g;
        return $rc;
    }

    # 1: optional something like 'final'
    sub load_report {
        dosayif($VERBOSE_ANY, "=== %sLOAD THREAD %s STATISTICS: %s",$ARG[0],$tnum,hdump(\%ghsql2stats));
        dosayif($VERBOSE_ANY, "- --- thread %s ERROR COUNTS: %s",$tnum,hdump(\%herr2count));
        dosayif($VERBOSE_ANY, "- --- thread %s ERROR TO LAST MSG:",$tnum);
        for my $key (sort(keys(%herr2errstr))) {
            my $str = $herr2errstr{$key};
            dosayif($VERBOSE_ANY, "-   -- %s %s", $key, $str);
        }
        dosayif($VERBOSE_ANY, "- --- thread %s ERROR STMT KIND COUNTS: %s",$tnum,hdump(\%herrkind2count,1));
    }

# 1: stmt
# 2: rc from exec
# 3: err
# 4: errstr
# 5: ksql eq alter
# 6: subtype eq same ksql or ALTER_DROP etc
    sub docount {
        my ($stmt,$rc,$err,$errstr,$qsql,$kup1) = @ARG;
        docroak("No qsql for %s",$stmt) if (not defined($qsql) or $qsql eq '');
        docroak("No kup1 for %s",$stmt) if (not defined($kup1) or $kup1 eq '');
        $qsql = uc($qsql);
        $kup1 = uc($kup1);
        $kup1 = $kup1 eq $qsql? '' : "$kup1 ->";
        my $adjstmt = msg_adjust($stmt);
        my $adjsimple = msg_adjust_simple($errstr);
        foreach my $ksql ($qsql,$kup1) {
            next if ($ksql eq '');
            if (not defined($rc)) {
                ++$herr2count{"E$err"};
                ++$herr2count{'EFAIL'};
                ++$herr2count{'ETOTL'};
                $herr2errstr{"E$err"} = "$errstr ! $stmt";
                ++$herrkind2count{"E$err $ksql $adjsimple"};
                ++$herrkind2count{"E$err * TOTL $adjsimple"};
                ++$herrkind2count{"EFAIL $ksql"};
                ++$herrkind2count{"ETOTL $ksql"};
                $herr2count{'ETOTL'} = 0 if (not defined($herr2count{'ETOTL'}));
                $herrkind2count{"ETOTL $ksql"} = 0 if (not defined($herrkind2count{"ETOTL $ksql"}));
                $herr2count{'EGOOD'} = 0 if (not defined($herr2count{'EGOOD'}));
                $herrkind2count{"EGOOD $ksql"} = 0 if (not defined($herrkind2count{"EGOOD $ksql"}));
            } else {
                ++$herr2count{'EGOOD'};
                ++$herr2count{'ETOTL'};
                ++$herrkind2count{"EGOOD $ksql"};
                ++$herrkind2count{"ETOTL $ksql"};
                $herr2count{'EFAIL'} = 0 if (not defined($herr2count{'EFAIL'}));
                $herr2count{'ETOTL'} = 0 if (not defined($herr2count{'ETOTL'}));
                $herrkind2count{"EFAIL $ksql"} = 0 if (not defined($herrkind2count{"EFAIL $ksql"}));
                $herrkind2count{"ETOTL $ksql"} = 0 if (not defined($herrkind2count{"ETOTL $ksql"}));
            }
        }
        return $RC_OK;
    }

    dosayif($VERBOSE_ANY, "%s load thread %s to run for %s seconds",$tkind,$tnum,$howlong);
    $ENV{_imatest_load_filebase} = sprintf("load_thread_%02s",$tnum);
    my $outto = doeval($ghreal{'load_thread_out'});
    my $errto = doeval($ghreal{'load_thread_err'});
    my $sqlto = doeval($ghreal{'load_thread_sql'});
    my $logto = doeval($ghreal{'load_thread_client_log'});
    $ENV{$LOAD_THREAD_CLIENT_LOG_ENV} = doeval($ghreal{$LOAD_THREAD_CLIENT_LOG});
    my $dosql = ($ghreal{'load_execute_sql'} eq $YES);
    dosayif($VERBOSE_ANY, "-see also %s and %s and %s and %s",$ENV{$LOAD_THREAD_CLIENT_LOG_ENV},$outto,$errto,$sqlto);
    open(my $msql, ">$sqlto") or docroak("failed to open >%s: $ERRNO. CROAK.",$sqlto);
    $msql->autoflush();
    my $shel = '';
    my $shelkind = $ghreal{'load_thread_execute_with'};
    my $dsn;
    my $dbh;
    if ($shelkind eq 'perl') {
        $SIG{'__WARN__'} = sub {1;};
        close(STDOUT);
        open (STDOUT, '>>', $outto);      # do append since the name does not have process id
        tee (STDERR, '>>', $errto);
        STDOUT->autoflush();
        STDERR->autoflush();
        dosayif($VERBOSE_ANY, "-random seed is %s for this %s load thread #%s", $rseed, $tkind, $tnum);
        my $absport = $ghtest{'port_load'} + $ghtest{'mportoffset'};
        $dsn = "DBI:mysql:host=127.0.0.1;port=$absport";
        dosayif($VERBOSE_ANY, "-dsn is %s for this %s load thread #%s", $dsn, $tkind, $tnum);
        $dbh = DBI->connect($dsn,$ghreal{'user'},$ghreal{'password'},{'PrintWarn' => 0,
          'TraceLevel' => 0, 'RaiseError' => 0, 'mysql_server_prepare' => 0, 'mysql_auto_reconnect' => 1});
          #'TraceLevel' => 0, 'RaiseError' => 0, 'mysql_server_prepare' => 1, 'mysql_auto_reconnect' => 1}); # prepare do not use ! E1461
        if (not defined($dbh)) {
            my $err = DBI->err();
            my $errstr = DBI->errstr();
            docroak("semiCROAK: failed to connect to $dsn: err $err errstr $errstr");
        }
        DBI->trace(0);
        $dbh->trace(0);
    }
    my $snum = 0;
    my $dlast = time();
    my $dwait = process_rseq('rediscover_every_seconds');
    while (1) {
        my $thistime = time();
        last if ($thistime >= $lasttime);
        last if ($maxcount > 0 and $snum >= $maxcount);
        if (-f $finfile) {
            dosayif($VERBOSE_ANY,"load thread %s pid %s exits after %s statements because of %s",$tkind,$PID,$snum,$finfile);
            load_report('FINAL BY FILE ');
            exit($ec);
        }
        if ($thistime - $dlast > $dwait) {
            dosayif($VERBOSE_ANY,"load thread %s pid %s will rediscover after having waited %s seconds",$tkind,$PID,$dwait);
            db_discover($dbh,0);
            $dlast = time();
            $dwait = process_rseq('rediscover_every_seconds');
            dosayif($VERBOSE_ANY,"load thread %s pid %s rediscovery complete,next in %s seconds",$tkind,$PID,$dwait);
        }
        ++$snum;

        # now generate statement
        my $stmt = '';
        my $ksql = '';
        if ($ghreal{'txn_use'} eq $YES) {
            dosleepms(process_rseq('txn_sleep_in_ms')) if ($txnin);
            $ksql = 'END' if (dorand() < $ghreal{'txn_end_p'});
            if ($txnin and $ksql eq '') {
                 $ksql = 'END' if ($snum - $txnstmt > $ghreal{'txn_maxlength_stmt'} or mstime() - $txnstart > $ghreal{'txn_maxlength_ms'});
            }
            if ($ksql ne 'END') {
                $ksql = 'BEGIN' if (dorand() < $ghreal{'txn_begin_p'} and not $txnin);
            } else {
                $ksql = process_rseq('txn_end_how');
            }
        }
        $ksql = process_rseq('load_sql_class') if ($ksql eq '');
        my $kup1 = $ksql;

        my $canexp = 0;
        my $tnam = '';
        dosayif($VERBOSE_MORE, "-ksql: %s",$ksql);
        if ($ksql eq 'select') {
            ($stmt,$kup1) = stmt_select_generate();
            $canexp = 1;
        } elsif ($ksql eq 'sop') {
            ($stmt,$kup1) = stmt_select_generate();
            $stmt = "SHOW PARSE_TREE $stmt";
            $kup1 = $ksql;
        } elsif ($ksql eq 'insert') {
            $stmt = stmt_insert_generate();
            $canexp = 1;
        } elsif ($ksql eq 'replace') {
            $stmt = stmt_replace_generate();
            $canexp = 1;
        } elsif ($ksql eq 'insel') {
            $stmt = stmt_insel_generate();
            $canexp = 1;
        } elsif ($ksql eq 'update') {
            $stmt = stmt_update_generate();
            $canexp = 1;
        } elsif ($ksql eq 'delete') {
            $stmt = stmt_delete_generate();
            $canexp = 1;
        } elsif ($ksql eq 'sot') {
            $stmt = 'SHOW OPEN TABLES';
        } elsif ($ksql eq 'checksum') {
            $tnam = table_get();
            $stmt = "CHECKSUM TABLE $tnam";
        } elsif ($ksql eq 'check') {
            $tnam = table_get();
            $stmt = "$ksql TABLE $tnam";
            if (dorand() < $ghreal{'load_check_quick_p'}) {
                $stmt .= ' QUICK';
                $kup1 = 'CHECKQ';
            } else {
                $kup1 = 'CHECKS';
            }
        } elsif ($ksql eq 'optimize') {
            $tnam = table_get();
            $stmt = 'OPTIMIZE';
            $kup1 = 'OPTIM';
            if (dorand() < $ghreal{'load_optimize_local_p'}) {
                $stmt .= ' LOCAL';
                $kup1 .= 'L';
            } else {
                $kup1 .= 'G';
            }
            $stmt = "$stmt TABLE $tnam";
        } elsif ($ksql eq 'analyze') {
            $tnam = table_get();
            $stmt = 'ANALYZE';
            $kup1 = 'ANAL';
            if (dorand() < $ghreal{'load_analyze_local_p'}) {
                $stmt .= ' LOCAL';
                $kup1 .= 'L';
            } else {
                $kup1 .= 'G';
            }
            $stmt = "$stmt TABLE $tnam";
        } elsif ($ksql eq 'BEGIN') {
            my $how = process_rseq('txn_begin_how');
            $kup1 = $how;
            $stmt = 'BEGIN WORK';
            $stmt = 'SET TRANSACTION READ ONLY' if ($how eq 'ro');
            $stmt = 'SET TRANSACTION READ WRITE' if ($how eq 'rw');
            $txnin = 1;
            $txnstmt = $snum;
            $txnstart = mstime();
        } elsif ($ksql eq 'commit' or $ksql eq 'rollback') {
            $stmt = uc($ksql);
            $txnin = 0;
        } elsif ($ksql eq 'alter') {
            # determine schema.table
            $tnam = table_get();
            ($stmt,$kup1) = stmt_alter_generate($tnam);
        } else {
            docroak("load_sql_class=%s is not supported yet. CROAK.",$ksql);
        }
        my $exp = $EMPTY;
        if ($canexp) {
            $exp = process_rseq('explain');
            if ($exp ne $EMPTY) {
                $kup1 = 'EXPLAIN';
                $ksql = "${exp}_$ksql";
                $exp =~ s/_/ /g;
                $stmt = "$exp $stmt";
            }
        }

        # now send statement for execution
        dosayif($VERBOSE_MORE, "send ksql: %s",$ksql);
        if ($snum % $ghreal{'report_every_stmt'} == 0) {
            dosayif($VERBOSE_ANY, "sending to execute stmt #%s",$snum);
            load_report('INTERIM ');
        }
        dosayif($VERBOSE_MORE, "do ksql: %s",$ksql);
        if ($dosql) {
            dosayif($VERBOSE_MORE, "perl ksql: %s",$ksql);
            my $rc = $dbh->do($stmt);
            my $err = $dbh->err();
            my $errstr = $dbh->errstr();
            dosayif($VERBOSE_MORE, "done perl ksql: %s",$ksql);
            docroak("FALSE ERROR RC rc +%s+ err +%s+ errstr +%s+ after %s",(defined($rc)?$rc:'undef'),$err,$errstr,$stmt)
              if (defined($rc) and ($err ne '' or $errstr ne ''));
            if (not defined($rc) and ($err eq '' or $errstr eq '') and not $serterm) {
                dosayif($VERBOSE_ANY,"ERROR NO RC THE SERVER MAY HAVE ABORTED +%s+ err +%s+ errstr +%s+ after %s",
                  (defined($rc)?$rc:'undef'),$err,$errstr,$stmt);
                $err = '9999';
                $errstr = 'ERROR NO RC THE SERVER MAY HAVE ABORTED';
            }
            docroak("PREPARED!+%s+%s+%s+",$err,$errstr,$stmt) if ($err eq '1461');
            dosayif($VERBOSE_MORE, "adjust1 ksql: %s",$ksql);
            dosayif($VERBOSE_MORE, "adjust2 ksql: %s %s",$ksql,$stmt);
            docount($stmt,$rc,$err,$errstr,$ksql,$kup1);
        }
        dosayif($VERBOSE_MORE, "done ksql: %s",$ksql);
        ++$ghsql2stats{$ksql};
        printf($msql "%s;\n", $stmt);

        # now reflect the results in internal structures
        if ($ksql eq 'alter') {
            table_add($tnam,$dbh,0);
        }

        # now sleep after txn
        my $ms = process_rseq('txn_sleep_after_ms',1);
        dosleepms($ms);
    }
    close $msql;
    dosayif($VERBOSE_ANY, "load thread %s exiting at %s with exit code %s after executing %s statements",$tnum,time(),$ec,$snum);
    load_report('FINAL BY COUNT ');
    dosayif($VERBOSE_ANY, "- see also %s and %s and %s and %s",$ENV{$LOAD_THREAD_CLIENT_LOG_ENV},$outto,$errto,$sqlto);
    exit $ec;
}

# 1: thread number, absolute
# 2: thread kind
# 3: random seed
sub server_destructive_thread {
    my $tnum = $ARG[0];
    my $tkind = $ARG[1];
    my $rseed = $ARG[2];
    my $starttime = time();

    # adjust destructive thread parameters
    if ($tkind ne '') {
        foreach my $parm (sort(grep {$_ =~ /${UKIND}$tkind$/} sort(keys(%ghtest)))) {
            my $soparm = $parm;
            $soparm =~ s/${UKIND}$tkind$//;
            dosayif($VERBOSE_ANY,"for %s thread #%s replacing %s of %s with %s of %s in ghtest",
              $tkind,$tnum,$soparm,$ghtest{$soparm},$parm,$ghtest{$parm});
            $ghtest{$soparm} = $ghtest{$parm};
            next if (not defined($ghreal{$parm}));
            dosayif($VERBOSE_ANY,"for %s thread #%s replacing %s of %s with %s of %s in ghreal",
              $tkind,$tnum,$soparm,$ghreal{$soparm},$parm,$ghreal{$parm});
            $ghreal{$soparm} = $ghreal{$parm};
        }
    }
    
    my $finfile = "$ghreal{'tmpdir'}/$PID.fin";
    my @ldeports = split(/,+/,$ghreal{'ports_destructive'});
    $ENV{_imatest_destructive_filebase} = "destructive_thread_$tnum";
    my $outto = doeval($ghreal{'destructive_thread_out'});
    my $errto = doeval($ghreal{'destructive_thread_err'});
    dosayif($VERBOSE_ANY, "see also %s and %s",$outto,$errto);
    close(STDOUT);
    open (STDOUT, '>>', $outto);      # do append since the name does not have process id
    tee (STDERR, '>>', $errto);
    STDOUT->autoflush();
    STDERR->autoflush();
    my $howlong = $ghreal{$TEST_DURATION};
    my $checkstart = $ghreal{'server_start_control'};
    my $starttimeout = $ghreal{'server_start_timeout'};
    my $dowait = $ghreal{'server_termination_wait'};
    my $waittimeout = $ghreal{$SERVER_TERMINATION_WAIT_TIMEOUT};
    my $lasttime = $starttime + $howlong;
    my $ec = $EC_OK;
    my $slep = $ghreal{'destructive_thread_sleep'};
    $gdosayoff = 2;
    dosayif($VERBOSE_ANY, " started at %s to run for %ss",$starttime,$howlong);
    dosayif($VERBOSE_ANY, "random seed is %s for this %s destructive thread #%s", $rseed, $tkind, $tnum);
    my $stepnum = 0;
    while (1) {
        my $thistime = time();
        last if ($thistime >= $lasttime);
        ++$stepnum;
        if (-f $finfile) {
            dosayif($VERBOSE_ANY,"destructive thread %s pid %s exits in step %s because of %s",$tkind,$PID,$stepnum,$finfile);
            exit($ec);
        }
        my $step = process_rseq('server_termination_every_seconds');
        $step = $starttime + $step - $lasttime if ($starttime + $step > $lasttime);
        dosayif($VERBOSE_ANY," will sleep %s seconds for step %s in increments of %ss",$step,$stepnum,$slep);
        my $startstep = time();
        while (time() - $startstep < $step) {
            dosleep($slep);
            if (-f $finfile) {
                dosayif($VERBOSE_ANY,"destructive thread %s pid %s exits in step %s after sleep because of %s",$tkind,$PID,$stepnum,$finfile);
                exit($ec);
            }
        }
        # now terminate servers
        my $howmany = process_rseq('ports_destructive_how_many');
        $howmany = scalar(@ldeports) if ($howmany > scalar(@ldeports));
        my @ltarg = @ldeports;
        @ltarg = splice(@ltarg,0,$howmany);
        $ENV{'_imatest_ports_destructive_rel'} = join(',',@ltarg);
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
        my $howrestart = $howterm eq $SIGSTOP ?  $ghreal{'server_terminate_unstop'} : $ghreal{$SERVER_RESTART};
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
            use DBI;
            use DBD::mysql;
            dosrand($rseed);
            $ghmisc{$RSEED} = $rseed;
            dosayif($VERBOSE_ANY, "random seed is %s for this %s load thread #%s", $rseed, $tkind, $tnum);
            server_load_thread($tnum,$tkind,$rseed);
        }
        dosayif($VERBOSE_ANY, " forked thread %s with pid=%s",$tnum,$pid);
        $ghlpids{$pid} = [$tnum,$tkind,$rseed];
	$rc = $RC_ERROR if (not defined($pid) or $pid < 0);
    } 
    dosayif($VERBOSE_ANY, " returning %s %s",  $rc, $GHRC{$rc});
    return $rc;
}

# 1: thread number
# 2: load kind or '' for base
# 3: random seed
sub start_destructive_thread {
    my $tnum = $ARG[0];
    my $tkind = $ARG[1];
    my $rseed = $ARG[2];
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY, " invoked with --%s=%s",  $DRYRUN, $ghasopt{$DRYRUN});
    if (not $ghasopt{$DRYRUN}) {
        my $pid = fork();
        if ($pid == 0) {
            dosrand($rseed);
            $ghmisc{$RSEED} = $rseed;
            dosayif($VERBOSE_ANY, "random seed is %s for this %s destructive thread #%s", $rseed, $tkind, $tnum);
            server_destructive_thread($tnum,$tkind,$rseed);
        }
        dosayif($VERBOSE_ANY, " forked thread with pid=%s",  $pid);
        $ghtermpids{$pid} = [$tnum,$tkind,$rseed];
        $rc = $RC_ERROR if (not defined($pid) or $pid < 0);
    } 
    dosayif($VERBOSE_ANY, " returning %s %s",  $rc, $GHRC{$rc});
    return $rc;
}

sub server_check_thread {
    my $starttime = time();
    my $finfile = "$ghreal{'tmpdir'}/$PID.fin";
    my $step = $ghreal{'check_thread_sleep'};
    my $ports = $ghreal{'check_thread_ports'};
    my @lcheck = split(/,+/,$ports);
    $ENV{'_imatest_check_filebase'} = 'check_thread';
    my $howcheck = $ghreal{'server_check'};
    my $outto = doeval($ghreal{'check_thread_out'});
    my $errto = doeval($ghreal{'check_thread_err'});
    dosayif($VERBOSE_ANY, "see also %s and %s",$outto,$errto);
    close(STDOUT);
    open (STDOUT, '>>', $outto);      # do append since the name does not have process id
    tee (STDERR, '>>', $errto);
    STDOUT->autoflush();
    STDERR->autoflush();
    my $howlong = $ghreal{$TEST_DURATION};
    my $lasttime = $starttime + $howlong;
    my $ec = $EC_OK;
    $gdosayoff = 2;
    dosayif($VERBOSE_ANY, " started at %s to run for %ss to check ports %s every %ss",$starttime,$howlong,"@lcheck",$step);
    my $num = 0;
    my $wasstate = '';
    my $nowstate = '';
    my %hbyport = ();
    my %hwasbyport = ();
    foreach my $port (@lcheck) {
        $hbyport{$port} = 'ASSUMED_UP';
        $hwasbyport{$port} = 'ASSUMED_UP';
    }
    my $haveassert = 0;
    while (1) {
        my $thistime = time();
        ++$num;
        last if ($thistime >= $lasttime);
        if (-f $finfile) {
            dosayif($VERBOSE_ANY,"check thread pid %s exits because of %s",$PID,$finfile);
            exit($ec);
        }
        if ($haveassert and $ghreal{'terminate_on_assert'} eq 'yes') {
            my $fintest = "$ghreal{'tmpdir'}/$ghmisc{'_master_pid'}.fin";
            my $slep = $ghreal{'sleep_on_assert'};
            dosayif($VERBOSE_ANY,"check thread detected server assert and will sleep %s seconds then force test termination by creating %s",
              $slep,$fintest);
              dosleep($slep);
              # todo sub
              my $cmd = "$ENV{'TOUCH'} $fintest";
              my $subec = system($cmd);
              dosayif($VERBOSE_ANY,"exit code %s for %s",$subec,$cmd);
              last;
        }
        # now check servers
        my $stat = '';
        my %hhow = ('RW' => 0, 'RO' => 0, 'DOWN' => 0, 'ASSERT' => 0);
        my $rw = 'NONE';
        my $ro = 'NONE';
        my $down = 'NONE';
        my $strange = 'NONE';
        foreach my $port (@lcheck) {
            $ENV{'_imatest_ports_check_rel'} = $port;
            my $howreal = doeval("\"$howcheck\"");
            dosayif($VERBOSE_ANY," executing %s",$howreal);
            my $before = time();
            my $subec = doeval("system(\"$howreal\")");
            my $howlong = time()-$before;
            $subec >>= $EIGHT;
            my $expl = 'UNKNOWN';
            if ($subec == $CHECK_RW) {
                $expl = 'RW';
                $strange .= ",$port" if ($rw ne 'NONE');
                $rw .= ",$port";
            } elsif ($subec == $CHECK_RO) {
                $expl = 'RO';
                $ro .= ",$port";
            } elsif ($subec == $CHECK_ASSERT) {
                $expl = 'ASSERT';
                $ro .= ",$port";
                $haveassert = 1;
            } elsif ($subec == $CHECK_DOWN) {
                $expl = 'DOWN';
                $down .= ",$port";
            }
            $hbyport{$port} = $expl;
            $stat .= ",$port$expl";
            ++$hhow{$expl};
            my $slow = $howlong > 1? 'SLOW' : 'FAST';
            dosayif($VERBOSE_ANY,"%s CHECK_THREAD_PER_PORT %s port %s %s %s %s %s",$howreal,$num,$port,$subec,$expl,$howlong,$slow);
        }
        my $cnts = '';
        foreach my $expl (reverse(sort(keys(%hhow)))) {
            $cnts .= ",$hhow{$expl}x$expl";
        }
        $cnts =~ s/^,//;
        $stat =~ s/^,//;
        $strange =~ s/^NONE,//;
        $ro =~ s/^NONE,//;
        $rw =~ s/^NONE,//;
        $down =~ s/^NONE,//;
        $nowstate = sprintf("ports %s state %s cnt %s RW %s RO %s DOWN %s STRANGE_%s",$ports,$stat,$cnts,$rw,$ro,$down,$strange);
        dosayif($VERBOSE_ANY,"CHECK_THREAD_OVERALL %s",$nowstate);
        if ($wasstate ne $nowstate) {
            if ($wasstate ne '') {
                dosayif($VERBOSE_ANY,"CHECK_THREAD_STATE_CHANGE was: %s now: %s",$wasstate,$nowstate);
                my $howex = '';
                foreach my $port (sort(keys(%hbyport))) {
                    $howex .= $hbyport{$port} eq $hwasbyport{$port}?
                      " $port stays $hbyport{$port}" : "$port goes $hwasbyport{$port}->$hbyport{$port}";
                }
                dosayif($VERBOSE_ANY,"CHECK_THREAD_STATE_CHANGE_HOW %s",$howex);
            }
            %hwasbyport = %hbyport;
            $wasstate = $nowstate;
        }
        dosleep($step);
    }
    dosayif($VERBOSE_ANY, " exiting at %s with exit code %s",time(),$ec);
    exit $ec;
}

sub start_check_thread {
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY, " invoked with --%s=%s",  $DRYRUN, $ghasopt{$DRYRUN});
    if (not $ghasopt{$DRYRUN}) {
        my $pid = fork();
        if ($pid == 0) {
            server_check_thread();
        }
        dosayif($VERBOSE_ANY, " forked check thread with pid=%s",$pid);
        $ghchepids{$pid} = [];
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
    my $absport = $ghtest{'port_writer'} + $ghtest{'mportoffset'};
    my $dsn = "DBI:mysql:host=127.0.0.1;port=$absport";
    dosayif($VERBOSE_ANY, "-dsn is %s for db init", $dsn);
    $gdbh = DBI->connect($dsn,$ghreal{'user'},$ghreal{'password'},{'PrintWarn' => 0,
      'TraceLevel' => 0, 'RaiseError' => 0, 'mysql_server_prepare' => 0, 'mysql_auto_reconnect' => 1});
    if (not defined($gdbh)) {
        my $err = DBI->err();
        my $errstr = DBI->errstr();
        docroak("CROAK: failed to connect to %s: err %s errstr %s",$dsn,$err,$errstr);
    }
    $ghdbh{$absport} = $gdbh;
    $gdbh->trace(0);
    DBI->trace(0);

    my @ltarg = split(/,+/,$ghreal{'mysql_initial_cnf_targets'});
    foreach my $target (@ltarg) {
        my $suf = $target eq '0'? '' : "_k_$target";
        my $portsarg = "mysql_initial_cnf_ports$suf";
        my $confarg = "mysql_initial_cnf$suf";
        docroak("mysql_initial_cnf_targets contains $target but there is no $portsarg in test description file",$target,$portsarg)
          unless (defined($ghreal{$portsarg}));
        docroak("mysql_initial_cnf_targets contains %s but there is no %s in test description file",$target,$confarg)
          unless (defined($ghreal{$confarg}));
        my @lports = split(/,+/,$ghreal{$portsarg});
        foreach my $relport (@lports) {
            #todo sub
            my $absport = $relport + $ghtest{'mportoffset'};
            if (not defined($ghdbh{$absport})) {
                my $dsn = "DBI:mysql:host=127.0.0.1;port=$absport";
                dosayif($VERBOSE_ANY, "-port %s dsn is %s for db config", $relport,$dsn);
                $ghdbh{$absport} = DBI->connect($dsn,$ghreal{'user'},$ghreal{'password'},{'PrintWarn' => 0,
                  'TraceLevel' => 0, 'RaiseError' => 0, 'mysql_server_prepare' => 0, 'mysql_auto_reconnect' => 1});
                if (not defined($ghdbh{$absport})) {
                    my $err = DBI->err();
                    my $errstr = DBI->errstr();
                    dosayif($VERBOSE_ANY,"semiCROAK: failed to connect to %s: err %s errstr %s",$dsn,$err,$errstr);
                }
                $ghdbh{$absport}->trace(0);
            }
            my @lcnf = map {"SET PERSIST $_"} split("\n",$ghreal{$confarg});
            foreach my $sets (@lcnf) {
                runreport($sets,$ghdbh{$absport},$VERBOSE_ANY);
            }
        }
    }

    if ($ghreal{'create_db'} eq 'yes') {
        $subrc = db_create();
    } else {
        $subrc = db_discover($gdbh,1);
    }
    $rc = $subrc if ($rc != $RC_OK and $rc != $RC_ZERO);

    dosayif($VERBOSE_ANY," returning %s",  $rc);
    return $rc;
}

# start execution. Execution starts HERE.
GetOptions(\%ghasopt, @LOPT) or usage("invalid options supplied",__LINE__);
scalar(@ARGV) == 0 or usage("no arguments are allowed",__LINE__);
foreach my $soname (sort(keys(%HDEFOPT))) {
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
if (defined($ghasopt{$SEED}) and $ghasopt{$SEED} != 0) {
    $rseed = $ghasopt{$SEED};
    dosrand($rseed);
} else {
    $rseed = dosrand();
};
$ghmisc{$RSEED} = $rseed;
$ghmisc{'_master_pid'} = $PID;
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

init_db();

start_check_thread();

# now we run test
my $trc = $RC_OK;
$ghreal{$TEST_DURATION} = process_rseq($TEST_DURATION);

if ($ghreal{'server_terminate'} eq $YES) {
    my $tdes = $ghreal{'destructive_threads'};
    dosayif($VERBOSE_ANY,"starting test destructive threads: %s",$tdes);
    my @lodes = split(/,/,$tdes);
    my $talnum = 0;
    my @lseed = ();
    @lseed = split(/,+/,$ghreal{'destructive_thread_random_seeds'}) if ($ghreal{'destructive_thread_random_seeds'} ne '0');
    docroak("failed to start server termination thread. CROAK.") if ($trc != $RC_OK);
    foreach my $elem (@lodes) {
        my @lok = split('X',$elem);
        push(@lok,'') if (scalar(@lok) < 2);
        foreach my $tnum (1..$lok[0]) {
            my $rseed = scalar(@lseed) > $talnum? $lseed[$talnum] : int(dorand()*1000000+100);
            ++$talnum;
            $trc = start_destructive_thread($talnum,$lok[1],$rseed);
            docroak("failed to start test destructive thread %s kind=%s rseed=%s. CROAK.",$talnum,$lok[1],$rseed) if ($trc != $RC_OK);
        }
    }
}

my $tlod = $ghreal{'load_threads'};
dosayif($VERBOSE_ANY,"starting test load threads: %s",$tlod);
my @lolod = split(/,/,$tlod);
my $talnum = 0;
my @lseed = ();
@lseed = split(/,+/,$ghreal{'load_thread_random_seeds'}) if ($ghreal{'load_thread_random_seeds'} ne '0');
foreach my $elem (@lolod) {
    my @lok = split('X',$elem);
    push(@lok,'') if (scalar(@lok) < 2);
    foreach my $tnum (1..$lok[0]) {
        my $rseed = scalar(@lseed) > $talnum? $lseed[$talnum] : int(dorand()*1000000+100);
        ++$talnum;
        $trc = start_load_thread($talnum,$lok[1],$rseed);
        docroak("failed to start test load thread. CROAK.") if ($trc != $RC_OK);
    }
}

# sleep while test is running while checking for child threads
my $slep = $ghreal{$TEST_DURATION};
my $interval = 10;
my $fintest = "$ghreal{'tmpdir'}/$PID.fin";
dosayif($VERBOSE_ANY,"will sleep for %s seconds checking for %s or threads every %s seconds",$slep,$fintest,$interval);
my $end = time() + $slep;
my $now = time();
my $reload = $ghreal{'load_thread_restart'};
while ($now < $end) {
    if (-f "$fintest") {
        if ($ghreal{'terminate_on_assert'} eq 'yes') {
            dosayif($VERBOSE_ANY,"terminating test because of %s",$fintest);
            last;
        } else {
            dosayif($VERBOSE_ANY,"ignoring %s because terminate_on_assert=no",$fintest);
        }
    }
# fixme refactor
    foreach my $pid (sort(keys(%ghlpids))) {
        my $sub = waitpid($pid, WNOHANG);
        if ($sub == $pid) {
            my $finfile = "$ghreal{'tmpdir'}/$pid.fin";
            if (-f $finfile) {
                dosayif($VERBOSE_ANY,"load thread process id %s terminated because of %s, not restarting",$pid,$finfile);
            } else {
                dosayif($VERBOSE_ANY,"semiCROAK load thread process id %s has terminated, restart is %s", $pid,$reload);
                if ($reload eq 'yes') {
                    dosayif($VERBOSE_ANY,"restarting load thread");
                    my ($tnum,$tkind,$rseed) = @{$ghlpids{$pid}};
                    my $new = fork();
                    if ($new == 0) {
                        dosrand($rseed);
                        $ghmisc{$RSEED} = $rseed;
                        dosayif($VERBOSE_ANY, "random seed is %s for this new %s load thread #%s", $rseed, $tkind, $tnum);
                        server_load_thread($tnum,$tkind,$rseed);
                    }
                    dosayif($VERBOSE_ANY, " restarted load thread: forked thread %s with pid=%s and rseed %s",$tnum,$new,$rseed);
                    $ghlpids{$new} = $ghlpids{$pid};
                }
            }
            delete($ghlpids{$pid});
        }
    }
    foreach my $pid (sort(keys(%ghtermpids))) {
        my $sub = waitpid($pid, WNOHANG);
        if ($sub == $pid) {
            my $finfile = "$ghreal{'tmpdir'}/$pid.fin";
            if (-f $finfile) {
                dosayif($VERBOSE_ANY,"destructive thread process id %s terminated because of %s, not restarting",$pid,$finfile);
            } else {
                dosayif($VERBOSE_ANY,"semiCROAK destructive thread process id $pid has unexpectedly terminated, restarting");
                my ($tnum,$tkind,$rseed) = @{$ghtermpids{$pid}};
                my $new = fork();
                if ($new == 0) {
                    dosrand($rseed);
                    $ghmisc{$RSEED} = $rseed;
                    dosayif($VERBOSE_ANY, "random seed is %s for this %s destructive thread #%s", $rseed, $tkind, $tnum);
                    server_destructive_thread($tnum,$tkind,$rseed);
                }
                dosayif($VERBOSE_ANY, " restarted destructive thread: forked thread %s with pid=%s and rseed %s",$tnum,$new,$rseed);
                $ghtermpids{$new} = $ghtermpids{$pid};
            }
            delete($ghtermpids{$pid});
        }
    }
    foreach my $pid (sort(keys(%ghchepids))) {
        my $sub = waitpid($pid, WNOHANG);
        if ($sub == $pid) {
            my $finfile = "$ghreal{'tmpdir'}/$pid.fin";
            if (-f $finfile) {
                dosayif($VERBOSE_ANY,"check thread process id %s terminated because of %s, not restarting",$pid,$finfile);
            } else {
                dosayif($VERBOSE_ANY,"semiCROAK check thread process id %s has unexpectedly terminated, restarting",$pid);
                my $new = fork();
                if ($new == 0) {
                    server_check_thread();
                }
                dosayif($VERBOSE_ANY, " restarted check thread: forked with pid=%s",$new);
                $ghchepids{$new} = [];
            }
            delete($ghchepids{$pid});
        }
    }
    dosleep($interval);
    $now = time();
}

# kill load and termination and check threads
# first let them go away quietly
foreach my $pid (sort(keys(%ghlpids)), sort(keys(%ghtermpids), sort(keys(%ghchepids)))) {
    my $finfile = "$ghreal{'tmpdir'}/$pid.fin";
    my $cmd = "$ENV{'TOUCH'} $finfile";
    my $subec = system($cmd);
    dosayif($VERBOSE_ANY,"exit code %s for %s",$subec,$cmd);
}
$slep = $ghreal{'sleep_final'};
dosayif($VERBOSE_ANY,"letting child processes go away gracefully while sleeping %ss",$slep);
dosleep($slep);
dosayif($VERBOSE_ANY,"eliminating remaining child processes");
foreach my $pid (sort(keys(%ghlpids)), sort(keys(%ghtermpids), sort(keys(%ghchepids)))) {
    my $sub = waitpid($pid, WNOHANG);
    if ($sub != $pid) {
        kill('KILL', $pid);
        dosayif($VERBOSE_ANY,"killed process $pid");
    } else {
        dosayif($VERBOSE_ANY,"process $pid has already terminated");
    }
}

my $ec = 0;
dosayif($VERBOSE_ANY,"exiting with exit code %s", $ec);
dosayif($VERBOSE_ANY,"See also %s", $ghasopt{$SEE_ALSO}) if (defined($ghasopt{$SEE_ALSO}));
exit($ec);
