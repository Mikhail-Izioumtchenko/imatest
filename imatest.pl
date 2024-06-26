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
# test case for seed
# flag file to start tracing
# join subqueries moreALTER finishSET setsqlmode

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

my $version = '6.0';

$Data::Dumper::Sortkeys = 1;

# constants. Do not use constant.
# UPPERCASE names
my $DRYRUN = 'dry-run';
my $HELP = 'help';
my $SEE_ALSO = 'see-also';
my $SEED = 'seed';
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
my $NEG_MARKER = 'MNN';

my $CHECK_SUBKEYS = '_2levelkeys';
my $DECIMAL = 'decimal';
my $EIGHT = 8;
my $EMPTY = 'EMPTY';
my $DEFEMPTY = ':EMPTY';
my $ERR_NO_TABLE = '1146';
my $ERR_NO_LOCK = '1100';
my $EXPRESSION_GROUP = 'expression_group';
my $JSON = 'json';
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

my @LOPT = ("$DRYRUN!", "$HELP!", "testyaml=s", "$SEE_ALSO=s", "$SEED=i", "$VERBOSE=i", "$VERSION!");
my %HDEFOPT = ("$DRYRUN" => 0, $HELP => 0, $VERBOSE => 0, $VERSION => 0);      # option defaults

# globals of sorts
my $gdbh;
my $gabsport;
my %ghdbh = ();      # config ports
my $gstrj;
my $gdosayoff = 2;
my %ghasopt = ();      # resulting options values hash
my %ghver = ();      # syntax checker hash
my %ghtest = ();      # test script hash
my %ghreal = ();      # test script hash with Rseq and similar processed e.g. 1-7 becomes e.g. 4
my %ghdt2have = ();      # datatype => 1
my %ghclass2have = ();      # datatype class => 1
my %ghsuc2have = ();      # datatype superclass => 1
my %ghdt2class = ();      # datatype => class
my %ghdt2suc = ();      # datatype => best superclass
my %ghclass2suc = ();      # class => best superclass
my %ghclass2dt = ();      # class => ref array datatypes
my %ghsuc2dt = ();      # superclass => ref array datatypes
my %ghsuc2class = ();      # superclass => ref array classes
my %ghsql2stats = ();      # insert => N
my $gstr = '';
my $gstrlen = 0;

# start schema related
my @glschemas = ();      # schema names
# end schema related

# start table related
my %ghst2cols = ();      ## schema.table => ref array column names
my %ghst2pkcols = ();      ## schema.table => ref array pk column names
my %ghst2pkautoinc = ();      ## schema.table => is pk autoinc 1 or 0
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
my %ghst2ind = ();      ## schema.table => ref list non pk index names and PRIMARY for primary if exists
my @ghstlist = (
\%ghst2pkautoinc,
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

# schema.table.index including PRIMARY
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
my $SUC_ANY = 'any';
my $SUC_NUMERAL = 'numeral';
my $SUC_CHARLIKE = 'charlike';
my $SUC_DATELIKE = 'datelike';
my %ghstc2suc = ();      # schema.table.column => 1 numeral 2 charlike 0 other
my %ghstc2class = ();      # schema.table.column => column datatype class
my %ghstc2just = ();      # schema.table.column => column datatype, just it
my %ghstc2len = ();      # schema.table.column => column length or scale 5 5,2 if specified or -1
my %ghstc2charset = ();      # schema.table.column => column charset if shown or :EMPTY
my %ghstc2collate = ();      # schema.table.column => column collate if shown or :EMPTY
my %ghstc2cannull = ();      # schema.table.column => column nullability 1 or 0
my %ghstc2unsigned = ();      # schema.table.column => column is unsigned 1 unsigned 0 signed or not specified
my %ghstc2srid = ();      # schema.table.column => SRID or -1
my %ghstc2canfull = ();      # schema.table.column => can be part of fulltext index
my %ghstc2isautoinc = ();      # schema.table.column => is autoinc 0, 1 2 if just KEY
my %ghstc2virtual = ();      # schema.table.column => column is virtual 1 stored 2 virtual or 0
my %ghstc2virtex = ();      # schema.table.column => virtual expression or :EMPTY
my %ghstc2hasdefault = ();      # schema.table.column => has default 1 or 0
my %ghstc2default = ();      # schema.table => DEFAULT or :EMPTY
my @ghstcolist = (
\%ghstc2suc,
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

# parameters: usage message, __LINE__ # exits with USAGE_ERROR_EC
sub usage {
    my $msg = $ARG[0];
    $msg = "line $ARG[1]: $msg" if (defined($ARG[1]));
    $msg .= "\nversion $ghmisc{$VERSION}" if (defined($ghasopt{$VERSION}) and $ghasopt{$VERSION});
    my $usage = <<EOF
  $msg
  Usage: $EXECUTABLE_NAME $PROGRAM_NAME option...
    --$HELP show this message and exit
    --[no]$DRYRUN optional, run no test if supplied, just check test file syntax
    --testyaml test_script.yaml: mandatory
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
    return $ran;
}

sub doshuffle {
    my @larg = @ARG;
    return @larg if (scalar(@larg) < 2);
    my $els = scalar(@larg);
    my $hom = int(dorand()*10);
    foreach my $i (0..$hom) {
        my $cutnum = int(dorand()*$els);
        my $cutel = splice(@larg,$cutnum,1);
        push(@larg,$cutel);
    }
    docroak("bad doshuffle %s to %s hom=%s",scalar(@ARG),scalar(@larg),$hom) if (scalar(@ARG) != scalar(@larg));
    return reverse(@larg);
}

# 1: sleep time in milliseconds # returns: whatever usleep returns or sleep time if --dry-run
sub dosleepms {
    my $slep = $ARG[0];
    return $ghasopt{$DRYRUN}? $slep : usleep($slep*1000);
}

# 1: sleep time in seconds # returns: whatever sleep returns or sleep time if --dry-run
sub dosleep {
    my $slep = $ARG[0];
    my $finfile = "$ghreal{'tmpdir'}/$PID.fin";
    if (-f $finfile) {
        my $rc = -1;
        dosayif($VERBOSE_ANY,"will not sleep %s seconds, return %s because of %s",$slep,$rc,$finfile);
        return $rc;
    }
    return $ghasopt{$DRYRUN}? $slep : sleep($slep);
}

my $gal = 'abcdefghijklmnopqrstuvwxyz0123456789';
sub generate_glstrings {
    my $llen = int(dorand()*1000)+1000;
    my $eachmax = 5;
    $gal .= uc($gal);
    my $tot = length($gal);
    for my $i (1..$llen) {
        $gstr .= substr($gal,int($tot*dorand()),int($eachmax*dorand()+1));
    }
    $gstrlen = length($gstr);
}

# 1: text file pathname # returns file contents # dies on error
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

# 1: string to eval # 2: eval as list if TRUE # 3: silent # returns: eval result. Will not make sense on eval error.  # on eval error prints helpful message and returns undef
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

# 1: verbosity level, prints out stuff only if --verbose >= that # 2: format, if starts with -, no timestamp prefixed # 3... : arguments # prints the message prepending by something helpful # returns whatever printf returns
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

# 1: key in test scripr hash # 2: 1 or not defined: quiet, 0: report a little # 3: 1: check, do not necessarily calculate the random outcome of Rseq #    0 or not defined: just calculate, try to avoid checking toil # side effect: sets part of ghreal unless check only # be careful with rule numbering which is not sequential nor numeric #    current last rule is 9 # on error calls usage # on success returns the value chosen
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
            $clval =~ s/:[0-9.]*//;
            my @lhave = split(/[,!]/,$clval);
            foreach my $el (@lhave) {
                $el =~ s/\(@[A-Z@;(}]+\)/()/ if ($el =~ /\(@/);
                usage("$skey subvalue '$el' violates Rseq Rule9: with '$ONLY_VALUES_ALLOWED' value must be one of: '@lal' +val+$val+clval+$clval+",__LINE__)
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
    my $prob = 1.0/scalar(@lcommas);
    $prob = $ghreal{'missing_probability_replacement'} if ($prob < $ghreal{'missing_probability_replacement'});
    my $n = 0;
    my %hcomma = ();
    my $hasprobs = 0;
    my $lastprob = 0;
    foreach my $lcom (@lcommas) {
        ++$n;
        if ($n != scalar(@lcommas) and not $lcom =~ /:/) {
            dosayif($verbose,"replacing missing probabilities with %s in %s of %s",$prob,$skey,$val);
            $lcom .= ":$prob";
        }
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
                usage("$skey value $val violates Rseq Rule6: in integer ranges are allowed only characters 0-9 - MNN ",__LINE__)
                  if ($check and join('',@lrange) =~ /[^-0-9MN]/);
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
        @lsem = map {s/^$NEG_MARKER/-/;s/MMM/M/;$_} @lsem
          if (not defined($only_values_allowed));
        $hcomma{sprintf($FDEC,$n)} = \@lsem;
    }

    dosayif($verbose,"%s to process %s: %s, lcommas is %s, hasprobs=%s, hcommas is %s",
      $skey,$val,"@lcommas",$hasprobs,Dumper(\%hcomma));
    my $pltopr = [];
    if ($hasprobs == 0) {
        # list of equiprobable values or ranges
        my $nl = int(dorand()*scalar(@lcommas));
        $pltopr = $hcomma{sprintf($FDEC,$nl+1)};
    } else {
        # we have probabilities, go through the hash to choose a random value
        my $n = 0;
        my $all = scalar(my @l=sort(keys(%hcomma)));
        foreach my $k (sort(keys(%hcomma))) {
            ++$n;
            my $plval = $hcomma{$k};
            my $prob = $plval->[scalar(@$plval)-1];
            my $ran = $n == $all? -1.0 : dorand();
            dosayif($verbose,"rand is %s and prob is %s for %s",$ran,$prob,Dumper($plval));
            $ran < $prob or next;
            dosayif($verbose,"for %s we choose %s",$skey,Dumper($plval));
            $pltopr = $plval;
            last;
        }
    }
    if (scalar(@$pltopr) == 2) {      # not range, single value and probability
        if ($only_names) {
            # Rule8: string is in fact a name but also ()
            usage(
              "$skey value $val violates Rseq Rule8: for $ONLY_NAMES first character must be [a-zA-Z_]",__LINE__)
              if ($check and (not $pltopr->[0] =~ /^[a-zA-Z_(]/));
        }
        # Rule6: wrong character
        usage("$skey value $val violates Rseq Rule6.3: $skey only supports positive integers",__LINE__)
          if ($only_positive_integers && (join('',@$pltopr) =~ /M/ || $pltopr->[0] <= 0));
        usage("$skey value $val violates Rseq Rule6.4: $skey only supports non negative integers",__LINE__)
          if ($only_non_negative_integers && join('',@$pltopr) =~ /M/);
    }
    $ghreal{$skey} = process_range($pltopr);
    $rc = $ghreal{$skey};

    return $rc;
}

sub checkscript {
    my $testyaml = $ghasopt{'testyaml'};
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
                usage("strict is specified in '$testyaml' but '$skey' is not described in $CHECKFILE '$ghtest{$CHECKFILE}' and $suf is not in strict_exceptions of '@lok'",
                  __LINE__)
                    if (scalar(grep {$_ eq $suf } @lok) == 0);
            } else {
                usage("strict is specified in '$testyaml' but '$skey' is not described in $CHECKFILE '$ghtest{$CHECKFILE}'",__LINE__)
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

    dosayif($VERBOSE_ANY, "Test script %s is syntactically correct", $ghasopt{'testyaml'});

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
    my @ldt = qw(tinyint boolean smallint mediumint bigint int bit polygon multipolygon geometrycollection geomcollection point multilinestring multipoint geometry linestring decimal numeric float double char varchar binary varbinary tinyblob tinytext blob text mediumblob mediumtext longblob longtext enum set datetime date timestamp time year json);
    foreach my $dt (@ldt) {
        $ghdt2have{$dt} = 1;
        $ghdt2suc{$dt} = 'any';
        $ghsuc2dt{$ghdt2suc{$dt}} = [] if (not defined($ghsuc2dt{$ghdt2suc{$dt}}));
        push(@{$ghsuc2dt{$ghdt2suc{$dt}}},$dt);
        if (is_datatype_charlike($dt)) {
            $ghdt2suc{$dt} = 'charlike';
            $ghsuc2dt{$ghdt2suc{$dt}} = [] if (not defined($ghsuc2dt{$ghdt2suc{$dt}}));
            push(@{$ghsuc2dt{$ghdt2suc{$dt}}},$dt);
        } elsif (is_datatype_numeral($dt)) {
            $ghdt2suc{$dt} = 'numeral';
            $ghsuc2dt{$ghdt2suc{$dt}} = [] if (not defined($ghsuc2dt{$ghdt2suc{$dt}}));
            push(@{$ghsuc2dt{$ghdt2suc{$dt}}},$dt);
        } elsif (is_datatype_datelike($dt)) {
            $ghdt2suc{$dt} = 'datelike';
            $ghsuc2dt{$ghdt2suc{$dt}} = [] if (not defined($ghsuc2dt{$ghdt2suc{$dt}}));
            push(@{$ghsuc2dt{$ghdt2suc{$dt}}},$dt);
        }
    }
    my @lclass = qw(integer decimal floating datetime character binary lob enums json spatial);
    foreach my $class (@lclass) {
        $ghclass2have{$class} = 1;
    }
    my @lsuc = ('numeral','charlike','datelike','any');
    foreach my $suc (@lsuc) {
        $ghsuc2have{$suc} = 1;
    }
    my $class2dt = 'integer:tinyint-boolean-smallint-mediumint-bigint-int-bit,spatial:polygon-multipolygon-geometrycollection-geomcollection-point-multilinestring-multipoint-geometry-linestring,decimal:decimal-numeric,floating:float-double,character:char-varchar,binary:binary-varbinary,lob:tinyblob-tinytext-blob-text-mediumblob-mediumtext-longblob-longtext,enums:enum-set,datetime:datetime-date-timestamp-time-year,json:json';
    my @lcla = split(/,/,$class2dt);
    foreach my $clas (@lcla) {
        my @l2 = split(/:/,$clas);
        my @ldt = split(/-/,$l2[1]);
        foreach my $dat (@ldt) {
            $ghdt2class{$dat} = $l2[0];
            $ghclass2dt{$l2[0]} = [] if (not defined($ghclass2dt{$l2[0]}));
            $ghsuc2class{$ghdt2suc{$dat}} = [] if (not defined($ghsuc2class{$ghdt2suc{$dat}}));
            if (not defined($ghclass2suc{$l2[0]})) {
                $ghclass2suc{$l2[0]} = $ghdt2suc{$dat};
                push(@{$ghclass2dt{$l2[0]}},$dat);
                push(@{$ghsuc2class{$ghdt2suc{$dat}}},$ghdt2class{$dat});
            }
        }
    }
    $ghsuc2dt{'any'} = \@ldt;
    $ghsuc2class{'any'} = \@lclass;
    return $RC_OK;
}

sub db_discover {
    my ($pdbh,$absport,$strict) = @ARG;
    my $dbh = ${$pdbh};
    my %haveadded = ();
    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY,"invoked db_discover");
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY,"with %s=%s returning %s", $DRYRUN, 1,  $rc);
        return $rc;
    }

    @glschemas = ();
    my $com = "SHOW SCHEMAS";
    my $plschemas = getarrayref($com,$dbh,$absport,$VERBOSE_ANY);
    if (not defined($plschemas)) {
        if ($strict) {
            docroak("Failed to execute %s",$com);
        } else {
            $dbh = doconnect($pdbh,$absport,0,1);
            $pdbh = \$dbh;
            $plschemas = getarrayref($com,$dbh,$absport,$VERBOSE_ANY);
            if (not defined($plschemas)) {
                dosayif($VERBOSE_ANY, "Failed to execute %s. Maybe the server is down. Best retry soon.",$com);
                return $RC_ERROR;
            }
        }
    }
    @glschemas = grep {$_ ne 'imaschema' and $_ ne 'sys' and $_ ne 'mysql' and not $_ =~ /^(performance|information)_schema$/}
                     map {$_->[0]} @$plschemas;
    docroak("we have no schemas to run test on") if (scalar(@glschemas == 0) and $strict);
    foreach my $schema (@glschemas) {
        dosayif($VERBOSE_ANY,"processing schema %s",$schema);
        my $stmt = "SHOW TABLES FROM $schema";
        my $pltables = getarrayref($stmt, $dbh,$absport,$VERBOSE_ANY);
        if (not defined($pltables)) {
            if ($strict) {
                docroak("Failed to execute %s",$stmt);
            } else {
                dosayif($VERBOSE_ANY, "Failed to execute %s. Maybe the server is down. Best retry soon.",$stmt);
                return $RC_ERROR;
            }
        }
        my @ltables = map {$_->[0]} @$pltables;
        for my $tab (@ltables) {
            if (table_add("$schema.$tab",$dbh,$absport,$strict) == $RC_OK) {
                ++$haveadded{"$schema.$tab"};
            }
        }
    }
    docroak("rc %s is not OK",$rc) if ($rc != $RC_OK);
    foreach my $st (sort(keys(%ghst2createtable))) {
        forget_table($st) if (not defined($haveadded{$st}));
    }
    
    dosayif($VERBOSE_ANY," db_discover returning %s",  $rc);
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

# 1: kind: virtual default where update etc # 2: schema.table.column of the column we are building # returns: (value_generate_sub function_sub operator)
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

# 1: s.t 2: c
sub new_generate_virtual {
    my ($tnam,$col) = @ARG;
    my $colnam = "$tnam.$col";
    my $dt = $ghstc2just{$colnam};
    docroak("no datatype for %s",$colnam) if (not defined($dt));
    my $dtc = $ghstc2class{$colnam};
    docroak("no datatype class for %s",$colnam) if (not defined($dtc));
    my $suc = $ghstc2suc{$colnam};
    docroak("no datsuc class for %s",$colnam) if (not defined($suc));
    my @luseall = grep {$_ ne $col} @{$ghst2cols{$tnam}};
    @luseall = ($col) if (scalar(@luseall) == 0);
    my @luse = @luseall;
    if ($suc eq 'numeral') {
        @luse = grep {$ghstc2suc{"$tnam.$_"} eq $SUC_NUMERAL} @luseall;
        @luse = @luseall if (scalar(@luse) == 0);
    } elsif ($suc eq 'charlike') {
        @luse = grep {$ghstc2suc{"$tnam.$_"} eq $SUC_CHARLIKE} @luseall;
        @luse = @luseall if (scalar(@luse) == 0);
    } elsif ($suc eq 'datelike') {
        @luse = grep {$ghstc2suc{"$tnam.$_"} eq $SUC_DATELIKE} @luseall;
        @luse = @luseall if (scalar(@luse) == 0);
    }
    my $pluse = \@luse;
    my $suval = '';
    my $parmdtc = "virtual_term_${suc}_datatype_class";
    my $tlen = process_rseq($suc eq 'numeral'? 'virtual_term_numeral_len' : 'virtual_term_non_numeral_len');
    my $parmunop = "virtual_term_unary_${suc}_operator";
    my $parmop = "virtual_term_${suc}_operator";
    my $parmfun = "virtual_functions_$suc";
    for my $termnum (1..$tlen) {
        my $tdtc = process_rseq($parmdtc);
        my $tdt = $tdtc eq 'json'? $tdtc : process_rseq("datatype_$tdtc");
        my $tkind = process_rseq('virtual_term_item_kind');
        my $tval = '';
        if ($tkind eq 'value') {
            $tval = new_generate_value("$tdtc:$tdt",0,'any');
        } elsif ($tkind eq 'column') {
            $tval = $pluse->[dorand()*scalar(@$pluse)];
        } else { # function
            my $tfun = process_rseq($parmfun);
            while ($tfun =~ /\@(SELF|COL)/) {
                my $tcol = '';
                if ($tfun =~ /\@COL_([a-z]+)/) {
                    my $typ = $1;
                    $tcol = new_get_column($tnam,$pluse,$typ);
                    $tfun =~ s/\@COL_([a-z]+)/$tcol/;
                } else {
                    $tcol = $pluse->[dorand()*scalar(@$pluse)];
                    $tfun =~ s/\@(SELF|COL)/$tcol/;
                }
            }
            $tfun =~ s/;/,/g;
            $tval = $tfun;
        }
        my $unop = process_rseq($parmunop);
        $unop =~ s/PREFNNN/-/g;
        $tval = "$unop$tval" if ($unop ne $EMPTY);
        if ($termnum < $tlen) {
            my $op = process_rseq($parmop);
            $op =~ s/NNN/-/g;
            $op =~ s/_/ /g;
            $tval = "$tval $op ";
        }
        $suval .= "$tval ";
    }
    docroak("bad virtual has \@ '%s'",$suval) if ($suval =~ /\@/);
    return $suval;
}

# 1: stc # 2: 1 to adjust length
sub new_generate_value {
    my ($colnam,$adjlen,$kind) = @ARG;
    my $dtc;
    my $dt;
    if ($colnam =~ /(.*):(.*)/) {
        $dtc = $1;
        $dt = $2;
    } else {
        $dt = $ghstc2just{$colnam};
        docroak("no datatype for %s",$colnam) if (not defined($dt));
        $dtc = $ghstc2class{$colnam};
        docroak("no datatype class for %s",$colnam) if (not defined($dtc));
    }
    my $rc = '';
    return 'NULL' if (($kind eq 'insert' or $kind eq 'replace') and $ghstc2isautoinc{$colnam} and dorand() >= $ghreal{'autoinc_explicit_value_p'});
    if ($dt eq 'tinyint') {
        $rc = value_generate_tinyint($colnam,$kind);
    } elsif ($dt eq 'bit') {
        $rc = value_generate_bit($colnam,$kind);
    } elsif ($dt eq 'boolean') {
        $rc = int(2*dorand());
    } elsif ($dt eq 'smallint') {
        $rc = value_generate_smallint($colnam,$kind);
    } elsif ($dt eq 'mediumint') {
        $rc = value_generate_mediumint($colnam,$kind);
    } elsif ($dt eq 'int') {
        $rc = value_generate_int($colnam,$kind);
    } elsif ($dt eq 'bigint') {
        $rc = value_generate_bigint($colnam,$kind);
    } elsif ($dt eq 'decimal' or $dt eq 'numeric') {
        $rc = value_generate_decimal($colnam,$kind);
    } elsif ($dt eq 'char') {
        $rc = value_generate_str($colnam,$adjlen,$kind);
    } elsif ($dt eq 'binary') {
        $rc = value_generate_str($colnam,$adjlen,$kind);
    } elsif ($dt eq 'tinytext') {
        $rc = value_generate_str($colnam,$adjlen,$kind);
    } elsif ($dt eq 'tinyblob') {
        $rc = value_generate_str($colnam,$adjlen,$kind);
    } elsif ($dt eq 'varbinary') {
        $rc = value_generate_str($colnam,$adjlen,$kind);
    } elsif ($dt eq 'varchar') {
        $rc = value_generate_str($colnam,$adjlen,$kind);
    } elsif ($dt eq 'text' or $dt eq 'blob') {
        $rc = substr($gstr,int(dorand()*$gstrlen),int(dorand()*1024)) x int(dorand()*50);
        $rc = substr($rc,0,65535) if (length($rc) > 65535);
        $rc = "'$rc'";
    } elsif ($dt eq 'mediumtext' or $dt eq 'mediumblob') {
        $rc = substr($gstr,int(dorand()*$gstrlen),int(dorand()*1024)) x int(dorand()*91);
        $rc = "'$rc'";
    } elsif ($dt eq 'longtext' or $dt eq 'longblob') {
        $rc = substr($gstr,int(dorand()*$gstrlen),int(dorand()*1024)) x int(dorand()*1001);
        $rc = "'$rc'";
    } elsif ($dt eq 'float') {
        $rc = value_generate_float($colnam,$kind);
    } elsif ($dt eq 'double') {
        $rc = value_generate_double($colnam,$kind);
    } elsif ($dt eq 'timestamp') {
        $rc = value_generate_timestamp($colnam,$kind);
    } elsif ($dt eq 'datetime') {
        $rc = value_generate_datetime($colnam,$kind);
    } elsif ($dt eq 'year') {
        $rc = value_generate_year($colnam,$kind);
    } elsif ($dt eq 'time') {
        $rc = value_generate_time($colnam,$kind);
    } elsif ($dt eq 'date') {
        $rc = value_generate_date($colnam,$kind);
    } elsif ($dt eq 'set') {
        $rc = value_generate_set($colnam,$kind);
    } elsif ($dt eq 'enum') {
        $rc = value_generate_enum($colnam,$kind);
    } elsif ($dtc eq 'spatial') {
        my $fun = "value_generate_$dt";
        docroak("No functions to calculate value for %s %s %s %s",$colnam,$dtc,$dt,$fun) if (not defined ($ghvgsub{$fun}));
        $rc = $ghvgsub{$fun}->($colnam,'any');
    } elsif ($dt eq 'json') {
        $rc = value_generate_json($colnam,'any');
    } else {
        docroak("no support to get value for dt '%s' dtc '%s' of '%s'",$dt,$dtc,$colnam);
    }
    return $rc;
}

# 1: schema.table # 2: ref columns returns ref list
sub new_generate_update_values {
    my ($tnam,$plcols) = @ARG;
    my $verbose = $VERBOSE_ANY;
    my @lrc = ();
    foreach my $col (@$plcols) {
        my $kind = process_rseq('update_kind');
        my $colnam = "$tnam.$col";
        my $dtc = $ghstc2class{$colnam};
        docroak("no datatype class for %s",$colnam) if (not defined($dtc));
        my $dt = $ghstc2just{$colnam};
        docroak("no datatype for %s",$colnam) if (not defined($dt));
        if (($dtc eq 'spatial' or $dt eq 'enum' or $dt eq 'set' or $dt eq 'json') and $kind eq 'function') {
            $kind = 'value';
            dosayif($verbose,"fallback from function to %s for %s %s, dtc %s dt %s",$kind,$tnam,$colnam,$dtc,$dt);
        }
        if ($kind eq 'column') {
            my $vcol = $ghst2cols{$tnam}->[int(dorand()*scalar(@{$ghst2cols{$tnam}}))];
            if ($vcol eq $col) {
                $kind = ($dt eq 'json' or $dtc eq 'spatial' or $dt eq 'enum' or $dt eq 'set' or $dt eq 'bit')? 'value' : 'function';
                dosayif($verbose,"fallback from column to %s for %s %s dtc %s dt %s",$kind,$tnam,$colnam,$dtc,$dt);
            } else {
                push(@lrc,"\`$vcol\`");
                next;
            }
        }
        if ($kind eq 'function') {
            my $parm = "update_functions_$dt";
            if (not defined($ghreal{$parm})) {
                $parm = "update_functions_$dtc";
                docroak("no update functions for %s: %s %s",$colnam,$dtc,$dt) if (not defined($ghreal{$parm}));
            }
            my $subrc = process_rseq($parm);
            $subrc =~ s/;/,/g;
            while ($subrc =~ /(\@[a-z_0-9]+)/) {
                my $at = $1;
                my $need = $at;
                $need =~ s/\@//;
                my $val = process_rseq($need);
                $subrc =~ s/$at/$val/;
            }
            $subrc =~ s/NNN/M/g;
            push(@lrc, $subrc);
            next;
        }
        if ($kind eq 'value') {
            push(@lrc,new_generate_value($colnam,1,'any'));
        } elsif ($kind eq 'default') {
            push(@lrc, 'DEFAULT');
        } else {
            docroak("update kind %s for %s %s is not supported",$kind,$tnam,$colnam);
        }
    }
    return \@lrc;
}

# 1: schema.table # 2: ref columns
sub new_generate_insert_values {
    my ($tnam,$plcols) = @ARG;
    my $verbose = $VERBOSE_ANY;
    my $rc = '';
    foreach my $col (@$plcols) {
        my $kind = process_rseq('insert_kind');
        my $colnam = "$tnam.$col";
        my $dtc = $ghstc2class{$colnam};
        docroak("no datatype class for %s",$colnam) if (not defined($dtc));
        my $dt = $ghstc2just{$colnam};
        docroak("no datatype for %s",$colnam) if (not defined($dt));
        if (($dtc eq 'spatial' or $dt eq 'enum' or $dt eq 'set' or $dt eq 'json' or $dt eq 'bit') and $kind eq 'function') {
            $kind = 'value';
            dosayif($verbose,"fallback from function to %s for %s %s, dtc %s dt %s",$kind,$tnam,$colnam,$dtc,$dt);
        }
        if ($kind eq 'column') {
            my $vcol = $ghst2cols{$tnam}->[int(dorand()*scalar(@{$ghst2cols{$tnam}}))];
            if ($vcol eq $col) {
                $kind = ($dt eq 'json' or $dtc eq 'spatial' or $dt eq 'enum' or $dt eq 'set' or $dt eq 'bit')? 'value' : 'function';
                dosayif($verbose,"fallback from column to %s for %s %s dtc %s dt %s",$kind,$tnam,$colnam,$dtc,$dt);
            } else {
                $rc .= ", \`$vcol\`";
                next;
            }
        }
        if ($kind eq 'function') {
            my $parm = "insert_functions_$dt";
            if (not defined($ghreal{$parm})) {
                $parm = "insert_functions_$dtc";
                docroak("no insert functions for %s: %s %s",$colnam,$dtc,$dt) if (not defined($ghreal{$parm}));
            }
            my $subrc = process_rseq($parm);
            $subrc =~ s/;/,/g;
            while ($subrc =~ /(\@[a-z_0-9]+)/) {
                my $at = $1;
                my $need = $at;
                $need =~ s/\@//;
                my $val = process_rseq($need);
                $subrc =~ s/$at/$val/;
            }
            $subrc =~ s/NNN/M/g;
            $rc .= ", $subrc";
            next;
        }
        if ($kind eq 'value') {
            $rc .= ", ".new_generate_value($colnam,1,'insert');
        } elsif ($kind eq 'default') {
            $rc .= ", DEFAULT";
        } else {
            docroak("insert kind %s for %s %s is not supported",$kind,$tnam,$colnam);
        }
    }
    $rc =~ s/^,//;
    return $rc;
}

# 1: schema.table # 2: schema.table.column
sub new_generate_default {
    my ($tnam,$colnam) = @ARG;
    my $verbose = $VERBOSE_SOME;
    my $rc = '';
    my $kind = process_rseq('default_kind');
    my $dtc = $ghstc2class{$colnam};
    docroak("no datatype class for %s",$colnam) if (not defined($dtc));
    my $dt = $ghstc2just{$colnam};
    docroak("no datatype for %s",$colnam) if (not defined($dt));
    if (($dtc eq 'spatial' or $dt eq 'enum') and $kind eq 'function') {
        $kind = 'value';
        dosayif($verbose,"fallback from function to %s for %s %s, dtc %s",$kind,$tnam,$colnam,$dtc);
    }
    my @lc = grep {"$tnam.$_" ne $colnam} @{$ghst2cols{$tnam}};
    if (scalar(@lc) == 0 and $kind eq 'column' and $dtc ne 'enums' and $dtc ne 'spatial') {
        $kind = 'function';
        dosayif($verbose,"fallback from column to %s for %s %s, columns '%s'",$kind,$tnam,$colnam,"@lc");
    }
    if ($kind eq 'column') {
        $rc = $lc[int(dorand()*scalar(@lc))];
        $rc = "($rc)";
    } elsif ($kind eq 'function') {
        my $parm = "default_functions_$dt";
        if (not defined($ghreal{$parm})) {
            $parm = "default_functions_$dtc";
            docroak("no default functions for %s: %s %s",$colnam,$dtc,$dt) if (not defined($ghreal{$parm}));
        }
        $rc = process_rseq($parm);
        $rc =~ s/;/,/g;
        while ($rc =~ /\@COL_([a-z_0-9]+)/) {
            my $at = $1;
            my $tcol = scalar(@lc) > 0? new_get_column($tnam,\@lc,$at) : new_generate_value($colnam,1,'default');
            $rc =~ s/\@COL_([a-z_0-9]+)/$tcol/;
        }
        $rc =~ s/NNN/M/g;
        $rc = "($rc)";
    } elsif ($kind eq 'value') {
        $rc = new_generate_value($colnam,1,'default');
    } else {
        docroak("default kind %s for %s %s is not supported, columns '%s'",$kind,$tnam,$colnam,"@lc");
    }
    dosayif($verbose,"default '%s' kind %s for %s %s",$rc,$kind,$tnam,$colnam);
    docroak("bad default tnam '%s' colnam '%s' has \@ '%s'",$tnam,$colnam,$rc) if ($rc =~ /\@/);
    return $rc;
}

sub is_datatype_charlike {
    my ($dt) = @ARG;
    my $rc = 0;
    $rc = 1 if ($dt =~ /^(char|varchar|binary|varbinary|tinyblob|tinytext|blob|text|mediumblob|mediumtext|longblob|longtext)$/i);
    return $rc;
}

sub is_datatype_numeral {
    my ($dt) = @ARG;
    my $rc = 0;
    $rc = 1 if ($dt =~ /^(numeric|tinyint|smallint|mediumint|bigint|int|decimal|float|double)$/i);
    return $rc;
}

sub is_datatype_datelike {
    my ($dt) = @ARG;
    my $rc = 0;
    $rc = 1 if ($dt =~ /(date|time|year)/i);
    return $rc;
}

sub new_set_suc {
    my ($dt) = @ARG;
    my $rc = $SUC_ANY;
    if (is_datatype_numeral($dt)) {
        $rc = $SUC_NUMERAL;
    } elsif (is_datatype_charlike($dt)) {
        $rc = $SUC_CHARLIKE;
    } elsif (is_datatype_datelike($dt)) {
    }
    return $rc;
}

# pseudo globals
my $pgneedvcols = 0;         # how many virtual cols we think we need
my $pghavevcols = 0;         # how many virtual cols we have
my $pgcolsnonpk = 0;         # how many non pk cols we have
my $pgcanautoinc = 0;        # can we have autoinc in table
my $pgcandefault = 0;        # can column have default
my $pghasautoinc = 0;        # do we have autoinc in table
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
    $ghstc2default{$colnam} = $DEFEMPTY;
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
    if ($tclass ne $JSON and $tclass ne 'spatial' and $tclass ne 'lob') {
        $pgcandefault = 1;
    } else {
        # https://bugs.mysql.com/bug.php?id=113860
        $pgcandefault = 0;
    }
    my $dt = $tclass;
    $ghstc2just{$colnam} = $dt;
    $ghstc2suc{$colnam} = new_set_suc($dt);
    my $can_autoinc = 0;
    if ($tclass eq 'integer') {
        $can_autoinc = 1;
        $dt = process_rseq('datatype_integer');
        $ghstc2just{$colnam} = $dt;
        $ghstc2suc{$colnam} = new_set_suc($dt);
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
                $ghstc2cannull{$colnam} = 0;
                $pgcandefault = 0;
                my $how = process_rseq('table_autoinc_kind');
                if ($how eq 'PRIMARY') {
                    $ghst2pkautoinc{$tnam} = 1;
                    $dt .= " PRIMARY KEY";
                } elsif ($how eq 'UNIQUE') {
                    $dt .= " UNIQUE";
                } else {
                    $ghstc2isautoinc{$colnam} = 2;
                }
            }
        }
    } elsif ($tclass eq $DECIMAL) {
        $dt = process_rseq('datatype_decimal');
        $ghstc2just{$colnam} = $dt;
        $ghstc2suc{$colnam} = new_set_suc($dt);
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
        $ghstc2suc{$colnam} = new_set_suc($dt);
    } elsif ($tclass eq 'datetime') {
        $dt = process_rseq('datatype_datetime');
        $ghstc2just{$colnam} = $dt;
        if ($dt eq 'datetime' or $dt eq 'timestamp') {
            my $frac = process_rseq('datetime_fractional');
            $dt .= "($frac)" if ($frac ne $EMPTY);
        }
    } elsif ($tclass eq 'character') {
        $ghstc2canfull{$colnam} = 1;
        $dt = process_rseq('datatype_character');
        $ghstc2just{$colnam} = $dt;
        $ghstc2suc{$colnam} = new_set_suc($dt);
        my $len = $dt eq 'char'? process_rseq('datatype_char_len') : process_rseq('datatype_varchar_len');
        $dt .= "($len)";
        $ghstc2len{$colnam} = $len;
        my $cs = process_rseq('character_set');
        $dt .= " character set $cs" if ($cs ne $EMPTY);
    } elsif ($tclass eq 'binary') {
        $dt = process_rseq('datatype_binary');
        $ghstc2just{$colnam} = $dt;
        $ghstc2suc{$colnam} = new_set_suc($dt);
        my $len = '';
        if ($dt eq 'binary') {
            $len = process_rseq('datatype_binary_len');
            $keylen = process_rseq('datatype_lob_key_len');
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
        $ghstc2suc{$colnam} = new_set_suc($dt);
        $ghstc2canfull{$colnam} = 1 if ($dt =~ /text/);
        $keylen = process_rseq('datatype_lob_key_len');
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
        $dt .= " AS_PEXPRP_COL$cnam $virt";
        ++$pghavevcols;
        $ghstc2virtual{$colnam} = 1;
        $pgcandefault = 0;
    }
    if (dorand() < $ghreal{'column_unique_p'} and $canunique) {
        $dt .= " unique";
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
        $ghstc2cannull{$colnam} = 0;
    }
    if (dorand() < $ghreal{'column_default_p'} and $pgcandefault) {
        my $expr = new_generate_default($tnam,$colnam);
        $dt .= " DEFAULT $expr";
        $ghstc2hasdefault{$colnam} = 1;
        $ghstc2default{$colnam} = $expr;
    }
    $coldef = "$cnam $dt";
    $ghstc2just{$colnam} = lc($ghstc2just{$colnam});
    return $coldef;
}

# 1: dbh 2: absport # 3: stmt # 4: key name string
# returns hashref or undef
sub gethashref {
    my ($dbh,$absport,$stmt,$key) = @ARG;
    docroak("undef absport") if (not defined($absport));
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
        check_reconnect(\$dbh,$absport,$err,$errstr);
    } else {
        dosayif($VERBOSE_SOME, "SUCCESS executing selectall_hashref %s",$stmt);
    }
    $SIG{'__WARN__'} = $was;
    return $rc;
}

# 1: stmt # 2: dbh 3: absport # 4: verbosity on error # returns arrayref or undef
sub getarrayref {
    my ($stmt,$dbh,$absport,$vererr) = @ARG;
    docroak("undef stmt") if (not defined($stmt));
    docroak("undef dbh") if (not defined($dbh));
    docroak("undef absport") if (not defined($absport));
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
        check_reconnect(\$dbh,$absport,$err,$errstr);
    } else {
        dosayif($VERBOSE_SOME, "SUCCESS executing selectall_arrayref %s",$stmt);
    }
    $SIG{'__WARN__'} = $was;
    return $rc;
}

# 1: stmt
# 2: dbh
# 3: verbosity on error
# returns RC_OK or RC_ERROR
sub runreport {
    my ($stmt,$dbh,$absport,$verbose) = @ARG;
    docroak("undef absport") if (not defined($absport));
    if ($ghasopt{$DRYRUN}) {
        dosayif($VERBOSE_ANY, "SUCCESS with --dry-run executing %s",$stmt);
        return $RC_OK;
    }
    docroak("undefined dbh for %s",$stmt) if (not defined($dbh));
    my $was = $SIG{'__WARN__'};
    $SIG{'__WARN__'} = sub {1;};
    my $rc = $dbh->do($stmt);
    my $err = '';
    my $errstr = '';
    $stmt =~ s/[a-z0-9]{1000}/LONG1000_/gi;
    $stmt =~ s/(LONG1000_)+/MANYLONG1000_/gi;
    if (not defined($rc)) {
        $rc = $RC_ERROR;
        $err = $dbh->err();
        $errstr = $dbh->errstr();
        dosayif($verbose, "ERROR %s executing %s: %s",$err,$stmt,$errstr);
        check_reconnect(\$dbh,$absport,$err,$errstr);
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
    my ($tnam,$dbh,$absport,$strict) = @ARG;
    dosayif($VERBOSE_ANY,"adding table '%s'",$tnam);
    my $stmt = "SHOW CREATE TABLE $tnam";
    my $plcre = getarrayref($stmt,$dbh,$absport,($strict? $VERBOSE_ANY : $VERBOSE_SOME));
    if (not defined($plcre)) {
        if ($strict) {
            docroak("Error executing %s",$stmt);
        } else {
            my $err = $dbh->err();
            my $errstr = $dbh->errstr();
            my $rc = $RC_WARNING;
            dosayif($VERBOSE_ANY,"keeping the table '%s' until rediscovery, rc %s, error executing %s: %s %s",$tnam,$rc,$stmt,$err,$errstr);
            return $rc;
        }
    }
    my $str = $plcre->[0]->[1];
    my ($schema,$table) = split(/\./,$tnam);

    my $inum = 0;
    dosayif($VERBOSE_ANY,"adding table %s to ghst2createtable",$tnam);
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
                $coldes =~ s/^\s*\`[^\`]+\`\s*//;
                $coldes =~ /^([^ \(,]+)[ \(,]?/;
                docroak("NO DATATYPE for column %s in %s",$colname,$lin) if (not defined($1));
                my $dt = lc($1);
                $ghstc2class{$stc} = $ghdt2class{$dt};
                $ghstc2just{$stc} = $dt;
                $ghstc2suc{$stc} = new_set_suc($dt);
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
                $coldes =~ s/\s*CHARACTER\s+SET\s+[^\s]* *//;
                if ($coldes =~ s/^\s*DEFAULT\s+(.+),?$//) {
                    docroak("BAD default for %s +%s+ dt +%s+ IN %s",$stc,$dt,$coldes,$lin) if (not defined($1));
                    $ghstc2hasdefault{$stc} = 1;
                    $ghstc2default{$stc} = $1;
                } else {
                    $ghstc2hasdefault{$stc} = 0;
                    $ghstc2default{$stc} = $DEFEMPTY;
                }
                $coldes =~ s/ON\s+UPDATE\s+CURRENT_TIMESTAMP//;
                $coldes =~ s/\(\d+\)//;
                $coldes =~ s/\'[a-zA-Z0-9]*\'//;
                docroak("BAD column description for %s, need empty string now: +%s+ dt +%s+ IN %s",$stc,$dt,$coldes,$lin) if ($coldes ne '');
            }
        }
    }

    $ghst2cols{$tnam} = \@lcols;
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
    $ghst2ind{$tnam} = [];
    my $phind = gethashref($dbh,$absport,"SELECT *, CONCAT(INDEX_NAME,'.',REPEAT('0',5-LENGTH(SEQ_IN_INDEX)),SEQ_IN_INDEX) PART_ID FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$schema' AND TABLE_NAME = '$table'",$key);
    if (not defined($phind)) {
        if ($strict) {
            docroak("For %s failed to gethasref of %s with key column %s",$tnam,$stmt,$key);
        } else {
            my $err = $dbh->err();
            my $errstr = $dbh->errstr();
            my $rc = $RC_WARNING;
            dosayif($VERBOSE_ANY,"For '%s' failed to gethashref of %s with key column %s, rc %s, %s: %s",$tnam,$stmt,$key,$rc,$err,$errstr);
            return $rc;
        }
    }
    
    my %hiname = ();
    foreach my $ipart (sort(keys(%$phind))) {
        my ($iname,$num) = split(/\./,$ipart);
        ++$hiname{$iname};
    }
    @lind = sort(keys(%hiname));
    $ghst2ind{$tnam} = \@lind;
    foreach my $ind (@lind) {
        my $sti = "$tnam.$ind";
        my @lcols = ();
        my @llen = ();
        my @lcot = ();
        my @lparts = sort grep {/^$ind\./} sort(keys(%$phind));
        foreach my $part (@lparts) {
            my $phpart = $phind->{$part};
            if ($phpart->{'INDEX_NAME'} eq 'PRIMARY') {
                $ghsti2kind{$sti} = 'PRIMARY';
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

    my $rc = $RC_OK;
    dosayif($VERBOSE_ANY,"For '%s' rc %s",$tnam,$rc);
    return $rc
}

# 1: schema.table
sub forget_table {
    my ($tnam) = @ARG;
    dosayif($VERBOSE_ANY,"forgetting table %s",$tnam);
    foreach my $pha (@ghstlist) {
        delete($pha->{$tnam});
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

# 1: s.c 2: pl cols 3: type
sub new_get_column {
    my ($tnam,$pluse,$typ) = @ARG;
    docroak("no pluse for tnam '%s' typ '%s'",$tnam,$typ) if (scalar(@$pluse) == 0);
    my ($dt,$dtc,$suc);
    if (defined($ghdt2have{$typ})) {
        $dt = $typ;
        $dtc = $ghdt2class{$dt};
        $suc = $ghdt2suc{$dt};
    } elsif (defined($ghclass2have{$typ})) {
        $dtc = $typ;
        $suc = $ghclass2suc{$dtc};
    } elsif (defined($ghsuc2have{$typ})) {
        $suc = $typ;
    } else {
        docroak("unsupported typ '%s' for tnam '%s' pluse '%s'",$typ,$tnam,"@$pluse") if (not defined($suc));
    }
    my $tcol = '';
    my @luse = ();
    if (defined($dt)) {
        @luse = grep {(defined($ghstc2just{"$tnam.$_"}) and $ghstc2just{"$tnam.$_"} eq $dt)} @$pluse;
    }
    if (defined($dtc) and scalar(@luse) == 0) {
        @luse = grep {(defined($ghstc2class{"$tnam.$_"}) and $ghstc2class{"$tnam.$_"} eq $dtc)} @$pluse;
    }
    if (scalar(@luse) == 0) {
        @luse = grep {(defined($ghstc2suc{"$tnam.$_"}) and $ghstc2suc{"$tnam.$_"} eq $suc)} @$pluse;
    }
    @luse = @$pluse if (scalar(@luse) == 0);
    $tcol = $luse[dorand()*scalar(@luse)];
    $tcol = "\`$tcol\`" if (not $tcol =~ /\`/);
    return $tcol;
}

# 1: schema.table # 2: ind num for name
sub generate_index_clause {
    my ($tnam,$inum) = @ARG;
    my $ispk = ($inum == 1 and not $ghst2pkautoinc{$tnam});
    my $needcols = process_rseq('parts_per_index');
    my @lindcols = grep {$ghstc2class{"$tnam.$_"} ne $JSON} @{$ghst2cols{$tnam}};
    if ($needcols eq 'ALL') {
        $needcols = scalar(@lindcols);
    }
    my $fulltext = (not $ispk and dorand() < $ghreal{'fulltext_index_p'})? 'FULLTEXT ' : '';
    my @lhavefull = grep {$ghstc2canfull{"$tnam.$_"}} @lindcols;
    $fulltext = '' if (scalar(@lhavefull) == 0);
    my $uniq = (not $ispk and dorand() < $ghreal{'index_unique_p'} and $fulltext eq '')? 'UNIQUE ' : '';
    $uniq = 'PRIMARY ' if ($ispk);
    my $rc = ", ${fulltext}${uniq}KEY ind$inum (";
    $rc =~ s/,// if ($ispk and $ghst2pkautoinc{$tnam});
    my @lhavecols = $fulltext eq ''? doshuffle(@lindcols) : doshuffle(@lhavefull);
    my $hasfun = 0;
    my $keylen = 0;
    PART:
    for my $colnum (1..$needcols) {
        last if ($colnum > scalar(@lhavecols));
        my $thiscol = $lhavecols[$colnum-1];
        docroak("No thiscol of %s/%s +%s:%s+%s:%s+%s:%s+",$colnum,$needcols,"@lhavecols",scalar(@lhavecols),"@lindcols",scalar(@lindcols),"@lhavefull",scalar(@lhavefull)) if (not defined($thiscol));
        my $qcol = $thiscol;
        $qcol = "\`$qcol\`" if (not $qcol =~ /\`/);
        my $coname = "$tnam.$thiscol";
        my $dtc = $ghstc2class{$coname};
        my $dt = $ghstc2just{$coname};
        if ($dtc eq $SPATIAL) {
            if ($ghstc2cannull{$coname} or $uniq ne '') {
                next;
            } else {
                $rc = ", $qcol";
                last;
            }
        }
        my $type = process_rseq('index_part_type');
        if ($dtc eq 'enums' and $type eq 'function') {
            $type = 'column';
            dosayif($VERBOSE_SOME,"fallback from function to %s for %s %s, dtc %s dt %s",$type,$tnam,$coname,$dtc,$dt);
        }
        if (($type eq 'column' or $ispk) and $ghstc2len{$coname} != 0) {
            $rc .= ", $qcol";
            if (($dtc eq 'character' and $type eq 'column' and process_rseq('index_prefix_use') eq 'yes')
                or $dtc eq $LOB) {
                my $lenp = process_rseq('index_prefix_len');
                $lenp = $ghstc2len{$coname}
                  if (dorand() < process_rseq($VKCHAR) and $ghstc2len{$coname} > 0 and $lenp > $ghstc2len{$coname});
                $keylen += $lenp eq '$EMPTY'? $ghstc2len{$coname} : $lenp;
                my $enough = 0;
                if ($keylen > 3072) {
                    $lenp = $lenp eq $EMPTY? $ghstc2len{$coname} - $keylen + 3072 : $lenp - $keylen + 3072;
                    $enough = 1;
                }
                $rc .= "($lenp)" if ($lenp ne $EMPTY);
                last PART if ($enough);
            }
        } else { #function
            $rc =~ s/PRIMARY//;
            my $dt = $ghstc2just{$coname};
            my $dtc = $ghstc2class{$coname};
            my $suc = $ghstc2suc{$coname};
            my $parm = "index_functions_$dt";
            if (not defined($ghreal{$parm})) {
                $parm = "index_functions_$dtc";
                if (not defined($ghreal{$parm})) {
                    $parm = "index_functions_$suc";
                    docroak("no index functions for %s: dtc index_functions_%s dt index_functions_%s suc index_functions_%s",$coname,$dtc,$dt,$suc) if (not defined($ghreal{$parm}));
                }
            }
            my $tfun = process_rseq($parm);
            while ($tfun =~ /\@(SELF|COL)/) {
                my $pluse = $ghst2cols{$tnam};
                my $tcol = '';
                if ($tfun =~ /\@COL_([a-z]+)/) {
                    my $typ = $1;
                    $tcol = new_get_column($tnam,$pluse,$typ);
                    $tfun =~ s/\@COL_([a-z]+)/$tcol/;
                } else {
                    $tcol = $qcol;
                    $tfun =~ s/\@(SELF|COL)/$tcol/;
                }
            }
            $tfun =~ s/;/,/g;
            $rc .= ", ($tfun)";
            $hasfun = 1;
        }
        my $dir = process_rseq('part_direction');
        $rc .= " $dir" if ($dir ne $EMPTY);
    }
    $rc =~ s/\( *,/(/;
    $rc .= ")";
    my $vis = $ispk? $EMPTY : process_rseq('index_visibility');
    $rc .= " $vis" if ($vis ne $EMPTY);
    if ($rc =~ /\(\s*\)/) {
        $rc = '';
    }
    $rc =~ s/^ *,//;
    return $rc;
}

# 1: schema.table
# 2: if tbd
# returns CREATE TABLE
sub generate_create_table {
    my ($tnam,$tbd) = @ARG;
    my $tsql = '';
    # table structure
    my $needind = process_rseq("indexes_per_table");
    if ($tbd) {
        #dosayif($VERBOSE_ANY,"as :TBD adding table %s to ghst2createtable",$tnam);
        $ghst2createtable{$tnam} = ':TBD';
    }
    $ghst2pkautoinc{$tnam} = 0;
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
    $tas = process_rseq('character_set');
    $tail .= " CHARACTER SET $tas" if ($tas ne $EMPTY);
    my $ncols = process_rseq('columns_total');
    my @lcols = ();
    foreach my $ncol (1..$ncols) {
        my $frm = process_rseq("column_name_format");
        my $colsn = sprintf($frm,$ncol);
        my $colnam = "$tnam.$colsn";
        push(@lcols,$colsn);
    }
    $pgneedvcols = process_rseq('virtual_columns_per_table');
    $pgneedvcols = scalar(@lcols)-1 if ($pgneedvcols >= scalar(@lcols));
    $ghst2cols{$tnam} = \@lcols;
    foreach my $cnam (@lcols) {
        # each column in table
        my $colnam = "$tnam.$cnam";
        my $coldef = generate_column_def('create_table',$colnam);
        # small chance there will be no keys after the last column
        $coldef .= ',' unless ($ghst2pkautoinc{$tnam} == 1 and $cnam eq $lcols[scalar(@lcols)-1]);
        $tsql .= $coldef;
    }
    while ($tsql =~ /AS_PEXPRP_COL([^\s]+)\s/) {
        my $col = $1;
        my $vir = new_generate_virtual($tnam,$col);
        $tsql =~ s/AS_PEXPRP_COL([^\s]+)/GENERATED ALWAYS AS ($vir)/;
    }
    foreach my $inum (1..$needind) {
        my $iline = generate_index_clause($tnam,$inum);
        $tsql .= ", $iline" if ($iline ne '');
    }
    foreach my $col (@{$ghst2cols{$tnam}}) {
        if ($ghstc2isautoinc{"$tnam.$col"} == 2) {
            $tsql .= ", KEY($col)";
        }
    }
    $tsql .= $tail;
    $tsql =~ s/,\s*,/,/g;
    $tsql =~ s/,\s*\)/)/g;
    return $tsql;
}

# returns RC_OK if all SQL is executed successfully, othrwise RC_WARNING
sub db_create {
    my $rc = $RC_OK;

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
        my $subrc = runreport($stmt,$gdbh,$gabsport,$VERBOSE_ANY);
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
            my $frm = process_rseq("table_name_format");
            my $tnam = "$snam.".sprintf($frm,$ntab);
            my $tsql = generate_create_table($tnam,1);
            runreport("DROP TABLE IF EXISTS $tnam",$gdbh,$gabsport,$VERBOSE_SOME);
            runreport($tsql,$gdbh,$gabsport,$VERBOSE_ANY);
        }
    }

    if (not $ghasopt{$DRYRUN}) {
        # clean up records for tables that failed to create
        dosayif($VERBOSE_ANY,"remove records for tables that failed to create");
        my $badtables = 0;
        foreach my $tnam (sort(keys(%ghst2createtable))) {
            my $plcre = getarrayref("SHOW CREATE TABLE $tnam",$gdbh,$gabsport,$VERBOSE_SOME);
            if (not defined($plcre)) {
                ++$badtables;
                dosayif($VERBOSE_ANY," table %s does not exist, forgetting it",$tnam);
                forget_table($tnam);
            } else {
                table_add($tnam,$gdbh,$gabsport,1);
            }
        }
        dosayif($VERBOSE_ANY," we have %s good tables, forgot %s bad tables",scalar(my @l=sort(keys(%ghst2createtable))),$badtables);
        docroak("Cannot proceed, no good tables. CROAK.") if (scalar(my @lgoo=sort(keys(%ghst2createtable))) == 0);
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

# 1: superclass 2: ref array eligible columns 3: where or group
sub new_generate_simple {
    my ($tnam,$suc,$pluse,$kind) = @ARG;
    my $suval = '';
    my $pref = $kind eq 'where'? 'where': 'group_having';
    my $parmdtc = $pref."_term_${suc}_datatype_class";
    my $tlen = process_rseq($suc eq 'numeral'? $pref.'_term_numeral_len' : $pref.'_term_non_numeral_len');
    my $parmunop = $pref."_term_unary_${suc}_operator";
    my $parmop = $pref."_term_${suc}_operator";
    my $parmfun = $pref."_functions_$suc";
    for my $termnum (1..$tlen) {
        my $tdtc = process_rseq($parmdtc);
        my $tdt = $tdtc eq 'json'? $tdtc : process_rseq("datatype_$tdtc");
        my $tkind = process_rseq($pref.'_term_item_kind');
        my $tval = '';
        if ($tkind eq 'value') {
            $tval = new_generate_value("$tdtc:$tdt",0,'any');
        } elsif ($tkind eq 'column') {
            $tval = $pluse->[dorand()*scalar(@$pluse)];
            if ($kind eq 'group') {
                my $ga = process_rseq('group_aggregate_kind');
                $ga =~ s/NNN/M/g;
                $ga = "$ga($tval)";
                $ga =~ s/_DISTINCT\(/(DISTINCT /;
                $tval = $ga;
            }
        } else { # function
            my $tfun = process_rseq($parmfun);
            while ($tfun =~ /\@(SELF|COL)/) { #todo sub
                if ($tfun =~ /\@COL_([a-z]+)/) {
                    my $typ = $1;
                    my $tcol = new_get_column($tnam,$pluse,$typ);
                    $tfun =~ s/\@COL_([a-z]+)/$tcol/;
                } else {
                    my $tcol = $pluse->[dorand()*scalar(@$pluse)];
                    $tfun =~ s/\@(SELF|COL)/$tcol/;
                }
            } 
            $tfun =~ s/;/,/g;
            $tval = $tfun;
        }
        my $unop = process_rseq($parmunop);
        $unop =~ s/PREFNNN/-/g;
        $tval = "$unop$tval" if ($unop ne $EMPTY);
        if ($termnum < $tlen) {
            my $op = process_rseq($parmop);
            $op =~ s/NNN/-/g;
            $op =~ s/_/ /g;
            $tval = "$tval $op ";
        }
        $suval .= "$tval ";
    }
    return $suval;
}

# 1: schema.table # 2: parameter name for no where # returns WHERE clause with WHERE 3: where or group 4: joins
sub new_generate_where {
    my ($tnam,$parm,$kind,$havejoins) = @ARG;
    docroak("no havejoins") if (not defined($havejoins));
    my $rc = '';
    return $rc if (dorand() < $ghreal{$parm});
    my $pref = 'where';
    if ($kind eq 'where') {
        $rc = 'WHERE ';
    } else { # group
        $rc = ' HAVING ';
        $pref = 'group_having';
    }
    my $plcols = $ghst2cols{$tnam};
    my @lnumcols = grep {$ghstc2suc{"$tnam.$_"} eq $SUC_NUMERAL} @$plcols;
    push(@lnumcols,$plcols->[0]) if (scalar(@lnumcols) == 0);
    my @lcharcols = grep {$ghstc2suc{"$tnam.$_"} eq $SUC_CHARLIKE} @$plcols;
    push(@lcharcols,$plcols->[0]) if (scalar(@lcharcols) == 0);
    my $lolen = process_rseq($pref.'_logical_len');
    foreach my $lnum (1..$lolen) {
        my $suc = process_rseq($pref.'_term_overall_class');
        my $pluse = [];
        if ($suc eq 'numeral') {
            $pluse = \@lnumcols;
        } elsif ($suc eq 'charlike') {
            $pluse = \@lcharcols;
        } else {
            $pluse = $plcols;
        }
        if ($havejoins) {
            my @luse = map {"$tnam.$_"} @$pluse;
            $pluse = \@luse;
        }
        my $lun = process_rseq($pref.'_logical_unary_operator');
        $rc .= " $lun " if ($lun ne $EMPTY);
        my $suval = new_generate_simple($tnam,$suc,$pluse,$kind);
        $rc .= $suval;
        my $isnull = process_rseq($pref.'_term_final_operator');
        $isnull =~ s/_/ /g;
        if ($isnull ne $EMPTY) {
            $rc .= $isnull;
        } else {
            my $parmbin = $pref."_term_binary_${suc}_operator";
            my $lbop = process_rseq($parmbin);
            $lbop =~ s/EXCL/!/;
            $lbop =~ s/_/ /;
            $rc .= $lbop;
            $suval = new_generate_simple($tnam,$suc,$pluse,$kind);
            $rc .= " $suval";
        }
        if ($lnum < $lolen) {
            my $bin = process_rseq($pref.'_logical_binary_operator');
            $rc .= " $bin ";
        }
    }
    return $rc;
}

# 1: schema.table
sub get_table_key {
    my ($tnam) = @ARG;
    docroak("No table supplied") if (not defined($tnam) or $tnam eq '');
    if (not defined($ghst2ind{$tnam})) {
        dosayif($VERBOSE_ANY, "no indexes for %s, maybe dropped",$tnam);
        return 'PRIMARY';
    }
    return 'PRIMARY' if (scalar(@{$ghst2ind{$tnam}}) == 0);
    my $rc = $ghst2ind{$tnam}->[int(dorand()*scalar(@{$ghst2ind{$tnam}}))];
    return $rc;
}

sub stmt_lock_table_generate {
    my $stmt = 'LOCK TABLE';
    my $hom = process_rseq('load_lock_table_count');
    foreach my $i (1..$hom) {
        my $tnam = table_get();
        my $how = process_rseq('load_lock_table_kind');
        $stmt .= " $tnam $how,";
    }
    $stmt =~ s/,$//;
    return $stmt;
}

sub stmt_unlock_table_generate {
    return 'UNLOCK TABLE';
}

# returns statement, subkind
sub stmt_select_generate {
    my $stmt = 'SELECT';
    my $sub = 'SELECT';
    if (dorand() < $ghreal{'select_distinct_p'}) {
        $stmt .= ' DISTINCT';
        $sub .= 'D';
    }
    # determine schema.table
    my $tnam = table_get();
    my $hosel = process_rseq('select_how');
    my $ifgrp = $hosel eq 'all'? 0 : (dorand() < $ghreal{'select_group_by_p'});
    my $joins = process_rseq('select_join_len');
    my $havejoins = ($joins > 1);
    my $ltog = $ifgrp? table_columns_subset($tnam,'group_by_column_p','group',$havejoins) : [];
    my $tog = '';
    my $tosel = '';
    if ($hosel eq 'all') {
        $tosel = '*';
        $sub .= 'A';
    } elsif ($hosel eq 'count') {
        $tosel = 'COUNT(*)';
        $sub .= 'C';
    } else {
        if ($ifgrp) {
            my $ltosel = table_columns_subset($tnam,'group_by_column_p','group',$havejoins);
            foreach my $c (@$ltosel) {
                my @lin = grep {$c eq $_} @$ltog;
                if (scalar(@lin) == 0) {
                    my $ga = process_rseq('group_aggregate_kind');
                    $ga =~ s/NNN/M/g;
                    $ga = "$ga($c)";
                    $ga =~ s/_DISTINCT\(/(DISTINCT /;
                    $tosel .= ", $ga";
                } else {
                    $tosel .= ", $c";
                }
            }
            $tosel =~ s/^,//;
            $tog = join(',',@$ltog);
            $tog =~ s/^,//;
            $tog =~ s/,$//;
            $tog =~ s/,/, /g;
            $tog = " GROUP BY $tog";
            $sub .= 'G';
            my $rol = '';
            if (dorand() < $ghreal{'group_rollup_p'}) {
                $rol = ' WITH ROLLUP';
                $sub .= 'R';
            }
            $tog .= $rol;
            my $hav = new_generate_where($tnam,'group_having_none_p','group',$havejoins);
            if ($hav ne '') {
                $sub .= 'H';
                $tog .= $hav;
            }
        } else {
            $tosel = table_columns_subset($tnam,$SELECT_COLUMN_P,'select',$havejoins);
        }
    }
    $stmt .= " $tosel FROM $tnam";
    if ($joins > 1) {
        $sub .= 'J';
        foreach my $i (2..$joins) {
            my $jtable = table_get();
            my $jkind = process_rseq('select_join_kind_simple');
            $jkind .= ' JOIN' unless ($jkind eq 'COMMA' or $jkind eq 'STRAIGHT_JOIN');
            $jkind =~ s/COMMA/,/;
            $stmt .= " $jkind $jtable,"
        }
        $stmt =~ s/,$//;
    }
    my $wher = new_generate_where($tnam,'select_where_all_p','where',$havejoins);
    $stmt .= " $wher";
    my $hasun = 0;
    my $sbord = '';
    if (dorand() < $ghreal{'select_union_p'}) {
        $hasun = 1;
        $sbord = join(',',(1..scalar(split(/, */,$tosel))));
        my $hom = process_rseq('select_union_len');
        for my $num (1..$hom) {
            my $how = process_rseq('select_union_how');
            $stmt .= " $how SELECT $tosel FROM $tnam";
            $wher = new_generate_where($tnam,'select_where_all_p','where',$havejoins);
            $stmt .= " $wher";
        }
        $sub .= "U";
    }
    $stmt .= " $tog";
    if (dorand() < $ghreal{'select_order_by_p'}) {
        my $ord = '';
        if ($ifgrp) {
            my $plord = table_columns_subset($tnam,'select_order_by_column_p','group',$havejoins);
            foreach my $c (@$plord) {
                my @lin = grep {$c eq $_} @$ltog;
                if (scalar(@lin) == 0) {
                    my $ga = process_rseq('group_aggregate_kind'); #todo sub
                    $ga =~ s/NNN/M/g;
                    $ga = "$ga($c)";
                    $ga =~ s/_DISTINCT\(/(DISTINCT /;
                    $ord .= ", $ga";
                } else {
                    $ord .= ", $c";
                }
            }
            $ord =~ s/^,//;
        } else {
            if ($hasun) {
                $ord = join(',',grep {dorand() < $ghreal{'select_order_by_column_p'}} split(/, */,$sbord));
                $ord = '1' if ($ord eq '');
            } else {
                $ord = table_columns_subset($tnam,'select_order_by_column_p','select',$havejoins);
            }
        }
        $stmt .= " ORDER BY $ord";
        $sub .= 'O';
    }
    my $lim = process_rseq('load_select_limit');
    if ($lim ne $EMPTY) {
        $stmt .= " LIMIT $lim";
        $sub .= 'L';
    }
    my $fup = process_rseq('select_for_update');
    if ($fup ne $EMPTY) {
        $stmt .= " FOR $fup";
        $sub .= 'U';
    }
        #docroak("#debug+%s+",$stmt) if ($joins > 1);
    return $stmt,$sub;
}

# returns statement
sub stmt_insel_generate {
    # determine schema.table
    my $tnam = table_get();
    my $stmt .= " INSERT into $tnam SELECT * FROM $tnam";
    my $wher = new_generate_where($tnam,'select_where_all_p','where',0);
    $stmt .= " $wher";
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
        $value = -$value if ($kind ne 'default' and dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
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
        $value = -$value if ($kind ne 'default' and dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
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
        $value = -$value if ($kind ne 'default' and dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
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
        $value = -$value if ($kind ne 'default' and dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
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
    if (not defined($ghstc2unsigned{$col}) or $ghstc2unsigned{$col} == 1) {
        $value = -$value if ($kind ne 'default' and dorand() < $ghreal{$NUMBER_REVERSE_SIGN_ILLEGITIMATE_P});
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
    $value =~ s/e-?// if ($value =~ /e.*E/i);
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
    $value =~ s/e-?// if ($value =~ /e.*E/i);
    return $value;
}

# 1: schema.table.column
# returns: value as string suitable to add to VALUES
sub value_generate_str {
    my ($colnam,$adjlen,$kind) = @ARG;
    my $rc = substr($gstr,int(dorand()*$gstrlen),int(dorand()*256));
    $rc = substr($rc,0,$ghstc2len{$colnam}) if ($adjlen and $ghstc2len{$colnam} != -1);
    $rc = "'$rc'";
    return $rc;
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
    $value = "($value)" if ($kind eq 'default');
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
    $value = "($value)" if ($kind eq 'default');
    return $value;
}

# 1: schema.table.column # 2: kind e.g. default # returns: value as string suitable to add to VALUES
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

# 1: schema.table.column # 2: kind e.g. default # 3: return list # returns: value as string suitable to add to VALUES, if 2 is TRUE, returns list of h,m,s,ms as strings, including EMPTY for ms
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

# 1: schema.table.column # 2: kind e.g. default # returns: value as string suitable to add to VALUES
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
    $value = "($value)" if ($kind eq 'default');
    return $value;
}

# 1: schema.table.column # 2: kind e.g. default # returns: value as string suitable to add to VALUES
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
    $value = "($value)" if ($kind eq 'default');
    return $value;
}

# 1: schema.table.column # 2: kind e.g. default # 3: if TRUE return raw data
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
    $value = "($value)" if ($inkind eq 'default' and not $raw);
    return $value;
}

# 1: schema.table.column # 2: kind e.g. default # returns: value as string suitable to add to VALUES
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
    $value = "($value)" if ($kind eq 'default');
    return $value;
}

# 1: schema.table.column # 2: kind e.g. default # 3: if TRUE return raw data like (1 2, 3 4)
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
    $value = "($value)" if ($kind eq 'default' and not $raw);
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
    $value = "($value)" if ($kind eq 'default');
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
    $value = "($value)" if ($kind eq 'default');
    return $value;
}

sub value_generate_geomcollection {
    return value_generate_geometrycollection(@ARG);
}

# 1: schema.table.column # returns: value as string suitable to add to VALUES
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
        $value = encode_json(\%gh2json);
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
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 3;
    my $num = int(dorand()*$len)+1;
    my $value = "\"v$num\"";
    return $value;
}

# 1: schema.table.column # 2: kind e.g. default # returns: value as string suitable to add to VALUES
sub value_generate_varchar {
    my ($col,$kind) = @ARG;
    docroak("kind is not defined. CROAK.") if (not defined($kind));
    my $valen = process_rseq('value_varchar_len');
    my $len = defined($ghstc2len{$col})? $ghstc2len{$col} : 0;
    $valen = $len if (dorand() < process_rseq($VKCHAR) and $len >= 1 and $valen > $len);
    my $value = "REPEAT('b',$valen)";
    $value = "($value)" if ($kind eq 'default');
    return $value;
};

# 1: schema.table to create # returns statement, subtype
sub stmt_create_table_generate {
    my ($tnam) = @ARG;
    my $stmt = "CREATE TABLE $tnam";
    my $kup1 = process_rseq('load_create_table_kind');
    if ($kup1 eq 'like') {
        my $tal = table_get();
        $stmt = "$stmt LIKE $tal";
        $kup1 = 'CREATE_TABLE_LIKE';
    } elsif ($kup1 eq 'select') {
        my ($sel,$dummy) = stmt_select_generate();
        $stmt = "$stmt $sel";
        $kup1 = 'CREATE_TABLE_SELECT';
    } else {
        $stmt = generate_create_table($tnam,0);
        $kup1 = 'CREATE_TABLE_NEW';
    }
    return $stmt,$kup1;
}

# returns statement
sub stmt_delete_generate {
    my $stmt = '';
    # determine schema.table
    my $tnam = table_get();
    my $wher = new_generate_where($tnam,'delete_where_all_p','where',0);
    $stmt = "DELETE FROM $tnam $wher";
    return $stmt;
}

# returns statement
sub new_stmt_update_generate {
    my $stmt = '';
    my $tnam = table_get();
    $stmt = "UPDATE $tnam SET";
    my $plcols = table_columns_subset($tnam,'update_column_p','update',0);
    my $plvalues = new_generate_update_values($tnam,$plcols);
    my $set = '';
    my $n = 0;
    foreach my $col (@$plcols) {
        my $val = $plvalues->[$n];
        $set .= ", \`$col\` = $val";
        ++$n;
    }
    $set =~ s/^,//;
    $stmt .= $set;
    my $wher = new_generate_where($tnam,'update_where_all_p','where',0);
    $stmt .= " $wher";
    return $stmt;
}

# returns statement,kup1
sub stmt_insert_generate {
    my $stmt = 'INSERT into ';
    my $kup1 = 'INSERT';
    # determine schema.table
    my $tnam = table_get();
    # https://bugs.mysql.com/?id=113951&edit=2
    docroak("empty table name +%s+",$tnam) if (not defined($tnam) or $tnam eq '');
    if (not defined($ghst2nvcols{$tnam})) {
        docroak("no nvcols for %s, maybe dropped",$tnam);
    }
    my @lcols = @{$ghst2nvcols{$tnam}};
    my @lqcols = map {"\`$_\`"} @lcols;
    $stmt .= " $tnam (".join(',',@lqcols).')';
    my $values = new_generate_insert_values($tnam,\@lcols);
    $stmt .= " VALUES ($values)";
    if (dorand() < $ghreal{'insert_on_dup_update_p'}) {
        $kup1 .= '_U';
        $stmt .= " ON DUPLICATE KEY UPDATE";
        my $plcols = table_columns_subset($tnam,'update_column_p','update',0);
        my $plvalues = new_generate_update_values($tnam,$plcols);
        my $set = '';
        my $n = 0;
        foreach my $col (@$plcols) {
            my $val = $plvalues->[$n];
            $set .= ", \`$col\` = $val";
            ++$n;
        }
        $set =~ s/^,//;
        $stmt .= " $set";
    }
    return $stmt,$kup1;
}

# returns statement
sub stmt_replace_generate {
    my $stmt = 'REPLACE into ';
    # determine schema.table
    my $tnam = table_get();
    # https://bugs.mysql.com/?id=113951&edit=2
    docroak("empty table name +%s+",$tnam) if (not defined($tnam) or $tnam eq '');
    if (not defined($ghst2nvcols{$tnam})) {
        dosayif($VERBOSE_ANY, "no nvcols for %s, maybe dropped",$tnam);
        return '';
    }
    my @lcols = @{$ghst2nvcols{$tnam}};
    my @lqcols = map {"\`$_\`"} @lcols;
    $stmt .= " $tnam (".join(',',@lqcols).')';
    my $values = new_generate_insert_values($tnam,\@lcols);
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
# returns colname
sub get_table_column {
    my ($tnam) = @ARG;
    my $col = $ghst2cols{$tnam}->[int(dorand()*scalar(@{$ghst2cols{$tnam}}))];
    return $col;
}

# 1: schema.table
# returns statement, subtype
sub stmt_analyze_generate {
    my ($tnam) = @ARG;
    my $stmt = 'ANALYZE';
    my $kup1 = $stmt;
    my $how = process_rseq('load_analyze_kind');
    if (dorand() < $ghreal{'load_analyze_local_p'}) {
        $stmt .= ' LOCAL';
        $kup1 .= 'L';
    } else {
        $kup1 .= 'G';
    }
    $stmt = "$stmt TABLE $tnam";
            if ($how eq 'just') {
        $kup1 .= 'nH';
    } elsif ($how eq 'drop') {
        my $col = table_columns_subset($tnam,'analyze_column_p','analyze',0);
        $kup1 .= 'dH';
        $stmt .= " DROP HISTOGRAM ON $col"; 
    } else {
        my $col = table_columns_subset($tnam,'analyze_column_p','analyze',0);
        $kup1 .= 'uH';
        $stmt .= " UPDATE HISTOGRAM ON $col"; 
        my $bus = process_rseq('load_analyze_buckets');
        if ($bus != 0) {
            $kup1 .= 'B';
            $stmt .= " WITH $bus BUCKETS";
        }
    }
    return $stmt,$kup1;
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
            $stmt .= "DROP COLUMN \`$cnam\`, ";
            $subt .= 'dC';
        } elsif ($kind eq 'ADD_COL') {
            my $colnam = sprintf("%s.added_col_%s",$tnam,int(dorand()*10000+1000));
            my $coldef = generate_column_def('alter_table',$colnam);
            $stmt .= "ADD COLUMN $coldef, ";
            $subt .= 'aC';
        } elsif ($kind eq 'DROP_KEY') {
            my $key = get_table_key($tnam);
            $stmt .= $key eq 'PRIMARY'? "DROP PRIMARY KEY, " : "DROP KEY \`$key\`, ";
            $subt .= 'dK';
        } elsif ($kind eq 'ADD_KEY') {
            my $iline = generate_index_clause($tnam,int(dorand()*10000+1000));
            return '' if ($iline =~ /^\s*$/);
            $stmt .= "ADD $iline, ";
            $subt .= 'aK';
        } elsif ($kind eq 'TABLE_EB') {
            $stmt .= "ENGINE=InnoDB, ";
            $subt .= 'eB';
        } else {
            docroak("ALTER kind %s is not supported",$kind);
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

# 1: pdbh 2: absport 3: err 4: errstr
sub check_reconnect {
    my ($pdbh,$absport,$err,$errstr) = @ARG;
    return if ($err ne '1053' and $err ne '2013' and $err ne '1317');
    dosayif($VERBOSE_ANY,"reconnecting because of %s: %s",$err,$errstr);
    doconnect($pdbh,$absport,0,1);
}

# 1: thread number, absolute # 2: thread kind # 3: random seed
sub server_load_thread {
    my $tnum = $ARG[0];
    my $tkind = $ARG[1];
    my $rseed = $ARG[2];
    my $starttime = time();
    tie %gh2json, 'Tie::IxHash';
    my $serterm = ($ghreal{'server_terminate'} eq 'yes');
    my $gldbh;
    my $glabsport;

    my %hneed = (
        #'1054' => 10, #only for single load
        '1064' => 10,
        #'1091' => 10, #PRIMARY
        #'1210' => 10,
        '1674' => 10,
        '3105' => 10,
    );

    # get random schema
    sub schema_get {
        docroak("No schemas in glschemas") if (scalar(@glschemas) == 0);
        my $snam = $glschemas[int(dorand()*scalar(@glschemas))];
        return $snam;
    }

    # get random table
    sub table_get {
        my @lt = sort(keys(%ghst2createtable));
        my $slep = 1;
        while (scalar(@lt) == 0) {
            dosayif($VERBOSE_ANY,"No tables in ghst2createtable, sleep %s and rediscover",$slep);
            dosleep($slep);
            ++$slep;
            db_discover(\$gldbh,$glabsport,0);
            last if ($slep > 30);
        }
        @lt = sort(keys(%ghst2createtable));
        if (scalar(@lt) == 0) {
            my @lother = sort(keys(%ghst2cols));
            dosayif("no tables in ghst2createtable while ghst2cols is '%s', will try it","@lother");
            foreach my $t (@lother) {
                $ghst2createtable{$t} = $EMPTY;
            }
        }
        @lt = sort(keys(%ghst2createtable));
        if (scalar(@lt) == 0) {
            my @lother = sort(keys(%ghst2cols));
            docroak("Still no tables in ghst2createtable while ghst2cols is '%s'","@lother");
        }
        my $tnam = $lt[int(dorand()*scalar(@lt))];
        return $tnam;
    }

    # 1: schema.table # 2: test parameter to use for selection # 3: kind: if not 'select', do not use virtual columns #          if UPDATE, return ref array, same for GROUP # 4: if have joins
    sub table_columns_subset {
        my ($tnam, $parm, $kind,$havejoins) = @ARG;
        docroak("empty table name '%s'",$tnam) if (not defined($tnam) or $tnam eq '');
        docroak("no havejoins") if (not defined($havejoins));
        if (not defined($ghst2nvcols{$tnam})) {
            my $newtnam = table_get();
            dosayif($VERBOSE_ANY, "no nvcols for %s, maybe dropped, will try %s",$tnam,$newtnam);
            $tnam = $newtnam;
            docroak("still no nvcols for %s",$tnam) if (not defined($ghst2nvcols{$tnam}));
        }
        my @lcall = ($kind eq 'select' or $kind eq 'group' or $kind eq 'analyze')? @{$ghst2cols{$tnam}} : @{$ghst2nvcols{$tnam}};
        @lcall = @{$ghst2cols{$tnam}} if (scalar(@lcall) == 0);
        my @lc = grep {dorand() < $ghreal{$parm}} @lcall;
        push(@lc,$lcall[0]) if (scalar(@lc) == 0);
        @lc = map {"$tnam.$_"} @lc if ($havejoins);
        my $rc = ($kind eq 'update' or $kind eq 'group' or $kind eq 'having')? \@lc : join(',',@lc);
        return $rc;
    }

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
        $rc =~ s/Unknown thread id:\s*[0-9]*/Unknown thread id: N/g;
        $rc =~ s/at row\s[0-9]*/at row N/g;
        $rc =~ s/entry\s'[^']*'/entry CONST/g;
        $rc =~ s/functional index\s*'[^']*'/functional index IND/g;
        $rc =~ s/key\s'[^']*'/key KEYNAME/g;
        $rc =~ s/value:\s?'?[^']*'?/value VALUE/g;
        $rc =~ s/set\s+[^\s]+\s+cannot\s+be\s+used/set CHARSET cannot be used/g;
        $rc =~ s/convert string\s[^\s]+/ convert string STRING/g;
        $rc =~ s/[iI]ncorrect\s+[^\s]+\s+value/Incorrect TYPE value/g;
        $rc =~ s/cannot index the expression\s'?[^']*'?/cannot index the expression EXPR/g;
        $rc =~ s/column\s'[^']*'/column COLNAME/g;
        $rc =~ s/table.alias:\s*'[^']*'/table-alias TABNAME/g;
        $rc =~ s/for\s+CAST\s+to\s+[^\s]+\s+from\s+column\s+[^s]+/for CAST to TYPE from column COLNAME/g;
        $rc =~ s/[^\s]+\s+(UNSIGNED\s+)?value is out of range/TYPE value is out of range/g;
        $rc =~ s/in\s+\'[^\']*\'/in PLACE/g;
        $rc =~ s/from column [\s+] at /from column COLNAME at/g;
        $rc =~ s/Column\s'[^']*'/Column COLNAME/g;
        $rc =~ s/ariable\s'[^']*'/ariable VARNAME/g;
        $rc =~ s/conjunction\s+with\s*'?[^']*'?/conjunction with COLLATION/g;
        $rc =~ s/value\s+of\s+'?[^']*'?/value of VALUE/g;
        $rc =~ s/Duplicate\s+column\s+name\s+'[^']*'/Duplicate column COLNAME/g;
        $rc =~ s/Duplicate\s+key\s+name\s+'[^']*'/Duplicate key INDNAME/g;
        $rc =~ s/\s+DROP\s+'[^']*'/ DROP COLNAME/g;
        $rc =~ s/[tT]able\s+'[^']*'/Table TABNAME/g;
        $rc =~ s/arguments\s+to\s+[^\s]*/arguments to FUNC/g;
        $rc =~ s/Field\s'[^']*'/Field COLNAME/g;
        $rc =~ s/syntax to use near '.*$/syntax to use near HERE/g;
        $rc =~ s/Expression #\d+ of/Expression #N of/g;
        $rc =~ s/out of range in function [^ ]+\./out of range in function GEOFUNC/;
        $rc =~ s/(Longitude|Latitude)\s+[\d.-]+\s+/LONGLAT VALUE /;
        $rc =~ s/within\s+[\(\)\[\]\d,\s.-]+/within RANGE/;
        $rc =~ s/Truncated Incorrect TYPE value VALUE.*/Truncated Incorrect TYPE value VALUE/;
        $rc =~ s/check the manual that corresponds to your MySQL server version for the right syntax/RTFM/g;
        $rc =~ s/range in.*/range in EXPR/g;
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
        my ($how,$snum,$strt) = @ARG;
        my $hol = time() - $strt + 1;
        dosayif($VERBOSE_ANY, "=== %sLOAD THREAD %s STATISTICS %s/%s at %.1f/s: %s",$how,$tnum,$snum,$hol,$snum/$hol,hdump(\%ghsql2stats));
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
        $kup1 = uc($kup1) if (uc($kup1) eq $qsql);
        $kup1 = $kup1 eq $qsql? '' : "$kup1 ->";
        my $adjstmt = msg_adjust($stmt);
        my $adjsimple = msg_adjust_simple($errstr);
        foreach my $ksql ($qsql,$kup1) {
            next if ($ksql eq '');
            if (not defined($rc)) {
                ++$herr2count{"E$err"};
                ++$ghsql2stats{'EFAIL'};
                ++$ghsql2stats{'ETOTL'};
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
                ++$ghsql2stats{'EGOOD'};
                ++$ghsql2stats{'ETOTL'};
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
    my $dosql = ($ghreal{'load_execute_sql'} eq $YES);
    dosayif($VERBOSE_ANY, "-see also %s and %s and %s",$outto,$errto,$sqlto);
    open(my $msql, ">$sqlto") or docroak("failed to open >%s: $ERRNO. CROAK.",$sqlto);
    $msql->autoflush();
    my $shel = '';
    my $shelkind = $ghreal{'load_thread_execute_with'};
    my $dsn;
    if ($shelkind eq 'perl') {
        $SIG{'__WARN__'} = sub {1;};
        close(STDOUT);
        open (STDOUT, '>>', $outto);      # do append since the name does not have process id
        tee (STDERR, '>>', $errto);
        STDOUT->autoflush();
        STDERR->autoflush();
        dosayif($VERBOSE_ANY, "-random seed is %s for this %s load thread #%s", $rseed, $tkind, $tnum);
        $glabsport = $ghtest{'port_load'} + $ghtest{'mportoffset'};
        $gldbh = doconnect(\$gldbh,$glabsport,0,1);
    }
    my $snum = 0;
    my $dlast = time();
    my $relast = time();
    my $dwait = process_rseq('rediscover_every_seconds');
    my $rewait = $ghreal{'report_every_seconds'};
    my $hosleep = 1;
    while (1) {
        my $thistime = time();
        if ($thistime >= $lasttime) {
            dosayif($VERBOSE_ANY,"load thread %s %s pid %s goes away by time",$tnum,$tkind,$PID);
            last;
        }
        if ($maxcount > 0 and $snum >= $maxcount) {
            dosayif($VERBOSE_ANY,"load thread %s %s pid %s goes away by stmt %s",$tnum,$tkind,$PID,$snum);
            last;
        }
        if ($thistime - $dlast > $dwait) {
            dosayif($VERBOSE_ANY,"load thread %s pid %s will rediscover after having waited %s seconds",$tkind,$PID,$dwait);
            my $drc = db_discover(\$gldbh,$glabsport,0);
            $dlast = time();
            $dwait = $drc == $RC_OK? process_rseq('rediscover_every_seconds') : 10;
            dosayif($VERBOSE_ANY,"load thread %s pid %s rediscovery complete drc=%s, next in %s seconds",$tkind,$PID,$drc,$dwait);
        }
        $thistime = time();
        last if ($thistime >= $lasttime);
        if (-f $finfile) {
            dosayif($VERBOSE_ANY,"load thread %s pid %s exits after %s statements because of %s",$tkind,$PID,$snum,$finfile);
            load_report('FINAL BY FILE ',$snum,$starttime);
            exit($ec);
        }
        if ($thistime - $relast > $rewait) {
            dosayif($VERBOSE_ANY,"load thread %s pid %s will report after having waited %s seconds, stmt %s",$tkind,$PID,$rewait,$snum);
            load_report('INTERIM BY TIME ',$snum,$starttime);
            $relast = time();
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
        if ($ksql eq 'drop_table' and scalar(my @l=sort(keys(%ghst2createtable))) < 2) {
            dosayif($VERBOSE_ANY,"Will create table instead of dropping last one +%s+",scalar(my @l=sort(keys(%ghst2createtable))));
            $ksql = $kup1 = 'create_table';
        }
        if ($ksql eq 'select') {
            ($stmt,$kup1) = stmt_select_generate();
            $canexp = 1;
        } elsif ($ksql eq 'lock_instance_for_backup') {
            $stmt = 'LOCK INSTANCE FOR BACKUP';
        } elsif ($ksql eq 'unlock_instance') {
            $stmt = 'UNLOCK INSTANCE';
        } elsif ($ksql eq 'show_parse_tree') {
            ($stmt,$kup1) = stmt_select_generate();
            $stmt = "SHOW PARSE_TREE $stmt";
            $kup1 = $ksql;
        } elsif ($ksql eq 'create_table') {
            my $frm = process_rseq("table_name_format");
            my $schema = $glschemas[int(dorand()*scalar(@glschemas))];
            $tnam = "$schema.".sprintf($frm,int(dorand()*10000+1000));
            ($stmt,$kup1) = stmt_create_table_generate($tnam);
        } elsif ($ksql eq 'insert') {
            ($stmt,$kup1) = stmt_insert_generate();
            $canexp = 1;
        } elsif ($ksql eq 'unlock_table') {
            $stmt = stmt_unlock_table_generate();
        } elsif ($ksql eq 'lock_table') {
            $stmt = stmt_lock_table_generate();
        } elsif ($ksql eq 'replace') {
            $stmt = stmt_replace_generate();
            $canexp = 1;
        } elsif ($ksql eq 'insel') {
            $stmt = stmt_insel_generate();
            $canexp = 1;
        } elsif ($ksql eq 'update') {
            $stmt = new_stmt_update_generate();
            $canexp = 1;
        } elsif ($ksql eq 'delete') {
            $stmt = stmt_delete_generate();
            $canexp = 1;
        } elsif ($ksql eq 'show_open_tables') {
            $stmt = 'SHOW OPEN TABLES';
        } elsif ($ksql eq 'checksum') {
            $tnam = table_get();
            $stmt = "CHECKSUM TABLE $tnam";
        } elsif ($ksql eq 'drop_table') {
            $tnam = table_get();
            $stmt = "DROP TABLE $tnam";
        } elsif ($ksql eq 'check') {
            $tnam = table_get();
            $stmt = "$ksql TABLE $tnam";
            if (dorand() < $ghreal{'load_check_quick_p'}) {
                $stmt .= ' QUICK';
                $kup1 = 'CHECKQ';
            } else {
                $kup1 = 'CHECKS';
            }
        } elsif ($ksql eq 'flush_tables') {
            $stmt = 'FLUSH';
            $kup1 = 'FLUSH_TABLES';
            my $loc = '';
            if (dorand() < $ghreal{'load_flush_local_p'}) {
                $loc = ' LOCAL';
                $kup1 .= '_L_';
            } else {
                $kup1 .= '_G_';
            }
            my $how = process_rseq('load_flush_tables_how');
            $how =~ s/_/ /g;
            if ($how eq $EMPTY) {
                $how = '';
                $kup1 .= '_E';
            }
            my $tables = '';
            my $nt = process_rseq('load_flush_tables_n');
            $nt = 1 if ($nt == 0 and $how eq 'FOR EXPORT');
            for my $i (1..$nt) {
                $tnam = table_get();
                $tables .= ", $tnam";
            }
            $tables =~ s/^ *, *//;
            $stmt = "$stmt$loc TABLES $tables $how";
        } elsif ($ksql eq 'flush') {
            my $how = process_rseq('load_flush_how');
            $stmt = 'FLUSH';
            $kup1 = 'FLUSH';
            my $loc = '';
            if ($how ne 'HOSTS' and dorand() < $ghreal{'load_flush_local_p'}) {
                $loc = "LOCAL ";
                $kup1 .= '_L_';
            } else {
                $kup1 .= '_G_';
            }
            $stmt = "$stmt $loc$how";
            $kup1 .= $how;
        } elsif ($ksql eq 'optimize') {
            $tnam = table_get();
            $stmt = 'OPTIMIZE';
            $kup1 = 'OPTIMIZE';
            if (dorand() < $ghreal{'load_optimize_local_p'}) {
                $stmt .= ' LOCAL';
                $kup1 .= 'L';
            } else {
                $kup1 .= 'G';
            }
            $stmt = "$stmt TABLE $tnam";
        } elsif ($ksql eq 'show_tables') {
            my $snam = schema_get();
            my $how = process_rseq('load_show_tables_kind');
            $stmt = 'SHOW ';
            if ($how eq 'EXTENDED') {
                $stmt .= " $how";
                $kup1 .= "_E";
            } elsif ($how eq 'BOTH') {
                $stmt .= " EXTENDED FULL";
                $kup1 .= "_EF";
            } elsif ($how eq 'FULL') {
                $stmt .= " $how";
                $kup1 .= "_F";
            }
            $stmt .= " TABLES FROM $snam";
        } elsif ($ksql eq 'show_columns') {
            $tnam = table_get();
            my $how = process_rseq('load_show_columns_kind');
            $stmt = 'SHOW ';
            if ($how eq 'EXTENDED') {
                $stmt .= " $how";
                $kup1 .= "_E";
            } elsif ($how eq 'BOTH') {
                $stmt .= " EXTENDED FULL";
                $kup1 .= "_EF";
            } elsif ($how eq 'FULL') {
                $stmt .= " $how";
                $kup1 .= "_F";
            }
            $stmt .= " COLUMNS FROM $tnam";
        } elsif ($ksql eq 'analyze') {
            $tnam = table_get();
            ($stmt,$kup1) = stmt_analyze_generate($tnam);
        } elsif ($ksql eq 'show_status') {
            $stmt = 'SHOW';
            my $glo = process_rseq('load_show_status_how');
            if ($glo eq 'GLOBAL') {
                $kup1 .= '_G';
                $stmt .= ' GLOBAL';
            } elsif ($glo eq 'SESSION') {
                $kup1 .= '_S';
                $stmt .= ' SESSION';
            } else {
                $kup1 .= '_E';
            }
            $stmt .= ' STATUS';
        } elsif ($ksql eq 'kill_connection') {
            $stmt = 'KILL CONNECTION';
            $kup1 = 'KILL_CONNECTION';
            my $qn = process_rseq('load_kill_n');
            $stmt .= " $qn";
        } elsif ($ksql eq 'kill_query') {
            $stmt = 'KILL QUERY';
            $kup1 = 'KILL_CQUERY';
            my $qn = process_rseq('load_kill_n');
            $stmt .= " $qn";
        } elsif ($ksql eq 'show_variables') {
            $stmt = 'SHOW';
            my $glo = process_rseq('load_show_variables_how');
            if ($glo eq 'GLOBAL') {
                $kup1 .= '_G';
                $stmt .= ' GLOBAL';
            } elsif ($glo eq 'SESSION') {
                $kup1 .= '_S';
                $stmt .= ' SESSION';
            } else {
                $kup1 .= '_E';
            }
            $stmt .= ' VARIABLES';
        } elsif ($ksql eq 'recreate_schema') {
            my $schema = schema_get();
            $stmt = $schema;
        } elsif ($ksql eq 'set_txn_isolation') {
            $stmt = 'SET';
            my $how = process_rseq('txn_isolation_kind');
            $kup1 .= "_$how";
            my $glo = process_rseq('txn_isolation_how');
            if ($glo eq 'GLOBAL') {
                $kup1 .= '_G';
                $stmt .= ' GLOBAL';
            } elsif ($glo eq 'SESSION') {
                $kup1 .= '_S';
                $stmt .= ' SESSION';
            } else {
                $kup1 .= '_S';
            }
            $kup1 = uc($kup1);
            $how =~ s/_/ /g;
            $how = uc($how);
            $stmt .= " TRANSACTION ISOLATION LEVEL $how";
        } elsif ($ksql eq 'BEGIN') {
            my $how = process_rseq('txn_begin_how');
            $kup1 = "BEGIN_$how";
            $stmt = 'BEGIN WORK';
            if ($how eq 'ro' or $how eq 'rw') {
                my $glo = process_rseq('txn_ro_rw_how');
                $glo = $glo eq $EMPTY? ' ' : " $glo";
                $kup1 .= 'G' if ($glo eq 'GLOBAL');
                $stmt = "SET$glo TRANSACTION READ ONLY" if ($how eq 'ro');
                $stmt = "SET$glo TRANSACTION READ WRITE" if ($how eq 'rw');
            }
            $txnin = 1;
            $txnstmt = $snum;
            $txnstart = mstime();
        } elsif ($ksql eq 'commit' or $ksql eq 'rollback') {
            $stmt = uc($ksql);
            $txnin = 0;
            # now sleep after txn
            my $ms = process_rseq('txn_sleep_after_ms',1);
            dosleepms($ms);
        } elsif ($ksql eq 'show_table_status') {
            my $snam = schema_get();
            $stmt = "SHOW TABLE STATUS FROM $snam";
        } elsif ($ksql eq 'alter') {
            $tnam = table_get();
            ($stmt,$kup1) = stmt_alter_generate($tnam);
        } elsif ($ksql eq 'set') {
            my $setkind = process_rseq('set_kind');
            $kup1 = 'SET_'.substr($setkind,0,1);
            $kup1 .= 'O' if ($setkind =~ /_/);
            $setkind = '' if ($setkind eq $EMPTY);
            my $setg = process_rseq('set_group');
            my $setname = '';
            my $setval = '';
            if ($setg eq 'g8opt') {
                my $len = process_rseq("set_variable_len_${setg}");
                $setname = 'optimizer_switch';
                foreach my $i (1..$len) {
                    my $subname = process_rseq("set_variable_name_$setg");
                    if ($subname eq 'default') {
                        $setval .= "$subname,";
                    } else {
                        my $subval = process_rseq("set_variable_value_$setg");
                        $setval .= "$subname=$subval,";
                    }
                }
                $setval =~ s/,$//;
                $setval = "'$setval'";
            } else {
                $setname = process_rseq("set_variable_name_${setg}");
                $setval = process_rseq("set_variable_value_${setg}");
            }
            $stmt = "SET $setkind $setname=$setval";
        } elsif ($ksql eq 'savepoint') {
            my $spn = process_rseq('txn_savepoints');
            my $spname = "s$spn";
            my $spkind = process_rseq('txn_savepoint_how');
            if ($spkind eq 'SET') {
                $stmt = "SAVEPOINT $spname";
                $kup1 .= '_S';
            } elsif ($spkind eq 'ROLLBACK') {
                $stmt = "ROLLBACK TO SAVEPOINT $spname";
                $kup1 .= '_R';
            } else { # release
                $stmt = "RELEASE SAVEPOINT $spname";
                $kup1 .= '_L';
            }
        } else {
            docroak("load_sql_class=%s is not supported yet. CROAK.",$ksql);
        }
        $kup1 = uc($kup1);
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
        if ($stmt eq '') {
            dosayif($VERBOSE_ANY,"empty stmt, sleep %s and try next",$hosleep);
            dosleep($hosleep);
            ++$hosleep;
            next;
        } else {
            $hosleep = 1;
        }

        # now send statement for execution
        dosayif($VERBOSE_MORE, "send ksql: %s",$ksql);
        if ($snum % $ghreal{'report_every_stmt'} == 0) {
            dosayif($VERBOSE_ANY, "sending to execute stmt %s and report",$snum);
            load_report('INTERIM BY STMT ',$snum,$starttime);
        }
        dosayif($VERBOSE_MORE, "do ksql: %s",$ksql);
        my $err;
        my $errstr;
        my $rows;
        if ($dosql) {
            dosayif($VERBOSE_MORE, "perl ksql: %s",$ksql);
            my @lstmt = $ksql eq 'recreate_schema'? ("DROP SCHEMA $stmt", "SELECT SLEEP(5)", "CREATE SCHEMA $stmt") : ($stmt);
            my $rc;
            foreach my $sstmt (@lstmt) {
                $rc = $gldbh->do($sstmt); #debug
                #my $sth = $gldbh->prepare($sstmt);
                #$rc = $sth->execute();
                $err = $gldbh->err();
                $errstr = $gldbh->errstr();
                #$rows = $sth->rows;
                #docroak("#debug+%s+%s+",$rows,$stmt) if $rows > 1 and $stmt =~ /^SELECT/;
                printf($msql "%s; %s: %s\n", $sstmt,$err,$errstr);
            }
            dosayif($VERBOSE_MORE, "done perl ksql: %s",$ksql);
            if (defined($hneed{$err}) and $hneed{$err} > 0) {
                $stmt =~ s/[a-z0-9]{1000}/LONG1000_/gi;
                $stmt =~ s/(LONG1000_)+/MANYLONG1000_/gi;
                dosayif($VERBOSE_ANY,"needed #%s %s %s: %s",$hneed{$err},$err,$errstr,$stmt);
                --$hneed{$err};
            }
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
        dosayif($VERBOSE_MORE, "done ksql %s %s %s",$snum,$ksql,$stmt);
        ++$ghsql2stats{$ksql};

        check_reconnect(\$gldbh,$glabsport,$err,$errstr);
        # now reflect the results in internal structures
        if ($ksql eq 'alter' or $ksql eq 'drop_table' or $ksql eq 'create_table') {
		my $arc = table_add($tnam,$gldbh,$glabsport,0);
		dosayif($VERBOSE_ANY,"%s %s add %s err %s %s for %s",$ksql,$tnam,$arc,$err,$errstr,$stmt) if ($ksql ne 'alter');
        }

        # now sleep after stmt
        my $ms = process_rseq('load_sleep_after_stmt_ms',1);
        dosleepms($ms);
    }
    close $msql;
    dosayif($VERBOSE_ANY, "load thread %s exiting at %s with exit code %s after executing %s statements",$tnum,time(),$ec,$snum);
    load_report('FINAL BY COUNT ',$snum,$starttime);
    dosayif($VERBOSE_ANY, "- see also %s and %s and %s",$outto,$errto,$sqlto);
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
    my $wastime = time();
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
            my $nowtime = time();
            if ($wasstate ne '') {
                dosayif($VERBOSE_ANY,"CHECK_THREAD_STATE_CHANGE was: %s now: %s after %s",$wasstate,$nowstate,$nowtime-$wastime);
                my $howex = '';
                foreach my $port (sort(keys(%hbyport))) {
                    $howex .= $hbyport{$port} eq $hwasbyport{$port}?
                      " $port stays $hbyport{$port}" : "$port goes $hwasbyport{$port}->$hbyport{$port}";
                }
                dosayif($VERBOSE_ANY,"CHECK_THREAD_STATE_CHANGE_HOW %s after %s",$howex,$nowtime-$wastime);
            }
            %hwasbyport = %hbyport;
            $wasstate = $nowstate;
            $wastime = $nowtime;
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

# 1: ref dbh # 2: absolute port # 3: strict # 4: reconnect # returns dbh
sub doconnect {
    my ($pdbh,$absport,$strict,$reconnect) = @ARG;
    my $dsn = "DBI:mysql:host=127.0.0.1;port=$absport";
    my $dbh = ${$pdbh};
    $dbh->disconnect() if ($reconnect and defined($dbh));
    my $maxwait = $ghreal{'reconnect_timeout'};
    my $strt = time();
    my $slep = 5;
    CONN:
    $dbh = DBI->connect($dsn,$ghreal{'user'},$ghreal{'password'},{'PrintWarn' => 0,
      'TraceLevel' => 0, 'RaiseError' => 0, 'mysql_server_prepare' => 0, 'mysql_auto_reconnect' => 0});
    if (not defined($dbh)) {
        my $err = DBI->err();
        my $errstr = DBI->errstr();
        if ($strict) {
            docroak("failed to connect to %s: err %s errstr %s",$dsn,$err,$errstr);
        } else {
            dosayif($VERBOSE_ANY,"failed to connect to %s: err %s errstr %s. Will sleep %s seconds and retry",$dsn,$err,$errstr,$slep);
            if (time() - $strt > $maxwait) {
                docroak("still no connection to %s after %s seconds: err %s errstr %s",$dsn,$maxwait,$err,$errstr);
            }
            dosleep($slep);
            goto CONN;
        }
    } else {
        dosayif($VERBOSE_ANY, "connected to port %s dsn is %s",$absport,$dsn);
    }
    #DBI->trace(0);
    #$dbh->trace(0);
    $pdbh = \$dbh;
    return $dbh;
}

# rc RC_OK: initialised successfully
#    RC_ZERO: nothing to do
sub init_db {
    my $rc = $RC_OK;
    my $subrc;
    dosayif($VERBOSE_ANY,"invoked");
    $rc = $RC_ZERO if $ghasopt{$DRYRUN};
    my $absport = $ghtest{'port_writer'} + $ghtest{'mportoffset'};
    $gdbh = doconnect(\$gdbh, $absport,1,0);
    $gabsport = $absport;
    $ghdbh{$absport} = $gdbh;

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
            my $absport = $relport + $ghtest{'mportoffset'};
            if (not defined($ghdbh{$absport})) {
                my $adbh;
                $ghdbh{$absport} = doconnect(\$adbh,$absport,1,0);
            }
            my @lcnf = map {"SET PERSIST $_"} split("\n",$ghreal{$confarg});
            foreach my $sets (@lcnf) {
                dosayif($VERBOSE_ANY,"port %s handle %s for %s",$absport,$ghdbh{$absport},$sets);
                runreport($sets,$ghdbh{$absport},$absport,$VERBOSE_ANY);
            }
        }
    }

    if ($ghreal{'create_db'} eq 'yes') {
        $subrc = db_create();
    } else {
        $subrc = db_discover(\$gdbh,$absport,1);
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
exists($ghasopt{'testyaml'}) or usage("--testyaml must be supplied",__LINE__);

my $test_script =  $ghasopt{'testyaml'};
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

generate_glstrings();

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
