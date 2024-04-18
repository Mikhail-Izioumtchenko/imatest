use strict;
use warnings;
use English;

require 5.032;

#
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

$Data::Dumper::Sortkeys = 1;

my $HELP = 'help';
my $USAGE_ERROR_EC = 1;
my $VERBOSE = 'verbose';
my $VERBOSE_ANY = 0;
my $VERBOSE_SOME = 1;
my $VERBOSE_MORE = 2;
my $VERBOSE_DEV = 3;
my $VERBOSE_NEVER = 4;

my $RC_OK = 1;      # not 0
my $EC_OK = 0;

my @LOPT = ("$HELP!", "$VERBOSE=i");
my %HDEFOPT = ($HELP => 0, $VERBOSE => 0);      # option defaults

my @L2IGNORE = ('\.sql$', '[/]?imatest\.out$');
my @LMSG2IGNORE = qw(MY-010048
     MY-012203
     MY-010949
     MY-010050
     MY-010051
     MY-010054
 MY-010116 MY-010747 MY-012266 MY-013932 MY-015015 MY-015019 MY-011323 MY-011332 MY-010182 MY-010304 MY-010068 MY-013602 MY-010308 MY-010253 MY-010264 MY-010251 MY-011240 MY-011243 MY-010733 MY-010101);
my %ghmsg2ignore = ();
my $GDATA = '^(ALTER|BEGIN|CHECK|Table\s+Op\s|.*\scheck\s+status\s+OK|COMMIT|EXPLAIN|->|id\s+select_type|[0-9]+\s+INSERT|INSERT|SELECT|UPDATE|pk[0-9]+|col[0-9]+|.?\s?[\s0-9a-zA-Z_]+\s?) ?';
my $GSQL = '^(ALTER|BEGIN|CHECK|COMMIT|EXPLAIN|INSERT|SELECT|UPDATE) ?';

my %ghasopt = ();
my $gdosayoff = 2;

sub usage {
    my $msg = $ARG[0];
    $msg = "line $ARG[1]: $msg" if (defined($ARG[1]));
    my $usage = <<EOF
  $msg
  Usage: $EXECUTABLE_NAME $PROGRAM_NAME [option...] input_file...
    Look at test logs.
    Example:
        $EXECUTABLE_NAME $PROGRAM_NAME /root/mysql-sandboxes/*/*/error.log /tmp/*
    --$HELP show this message and exit
EOF
    ;
    dosayif($VERBOSE_ANY, "%s", $usage);
    if ($ghasopt{$HELP}) {
        exit($USAGE_ERROR_EC);
    } else {
        docroak("usage() called. CROAK.");
    }
}

# 1: text file pathname
# returns file contents as ref array
# dies on error
sub readfile {
    my $fn = $ARG[0];
    open(my $fh, '<', $fn) or docroak("failed to open $fn for reading. CROAK.");
    my @lrc = ();
    while (my $lin = <$fh>) {
        push(@lrc,$lin);
    }
    return \@lrc;
}

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
    if ($format =~ /^\+/) {
        $format =~ s/^.//;
        my $doformat = "#P %s %s %s %s: $format\n";
        my $dt = DateTime->now(time_zone => 'UTC');
        my ($sec, $mks) = gettimeofday();
        my $dout = sprintf("%s %s.%06d %s", $dt->ymd(), $dt->hms(), $mks, $dt->time_zone_short_name());
        printf($doformat, $PID, $dout, $PROGRAM_NAME, $res, @largs);
    } else {
        printf("$format\n", @largs);
    }
}

# format, arguments
sub docroak {
    my ($format,@larg) = @ARG;
    dosayif($VERBOSE_ANY,"+$format",@larg);
    my $msg = sprintf("Now we CROAK. ".$format,@larg);
    croak($msg);
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

# return time in ms
sub mstime {
    my ($sec, $mks) = gettimeofday();
    my $rc = $sec*1000 + $mks / 1000;
    return $rc;
}

# 

# start execution. Execution starts HERE.
GetOptions(\%ghasopt, @LOPT) or usage("invalid options supplied",__LINE__);
usage("invoked with --help",__LINE__) if ($ghasopt{$HELP});
scalar(@ARGV) != 0 or usage("At least one argument is needed",__LINE__);
foreach my $soname (keys(%HDEFOPT)) {
    $ghasopt{$soname} = $HDEFOPT{$soname} if (not defined($ghasopt{$soname}));
}

foreach my $m (@LMSG2IGNORE) {
    ++$ghmsg2ignore{$m};

}
# start processing. Processing starts HERE.
dosayif($VERBOSE_ANY, "+Invoked with %s\n", "@ARGV");
my @l2see = glob("@ARGV");
dosayif($VERBOSE_ANY, "To look at %s\n", "@l2see");
my @l2mine = ();
    FIL:
foreach my $fil (@l2see) {
    if (-d $fil) {
        dosayif($VERBOSE_ANY, "%s is directory, ignore", $fil);
        next;
    }
    if (not -f $fil) {
        dosayif($VERBOSE_ANY, "%s is not a file, ignore", $fil);
        next;
    }
    foreach my $rign (@L2IGNORE) {
        next unless ($fil =~ /$rign/);
        dosayif($VERBOSE_ANY, "%s is %s, ignore", $fil, $rign);
        next FIL;
    }
    push(@l2mine,$fil);
}
dosayif($VERBOSE_ANY, "To mine: %s\n", "@l2mine");

# 1: file name
# 2: ref array contents
sub getkind {
    my ($fil,$plfil) = @ARG;
    return 'mysqld_error_log' if ($fil =~ /\/?error\.log$/);
    return 'mysql_load_out' if ($fil =~ /\/?load_thread_[0-9]+\.out$/);
    return 'master_thread_log' if ($fil =~ /\/?master_thread\.log$/);
    return 'imatest_pl_out' if ($fil =~ /\/?imatest\.pl\.out$/);
    return 'UNKNOWN';
}

my %ghprocess = (
    'mysqld_error_log' => \&process_mysqld_error_log,
    'master_thread_log' => \&process_master_thread_log,
    'mysql_load_out' => \&process_mysql_load_out,
    'imatest_pl_out' => \&process_imatest_pl_out,
    'UNKNOWN' => \&process_unknown,
);

my $ec = 0;

foreach my $fil (@l2mine) {
    my $plfil = readfile($fil);
    my $kind = getkind($fil,$plfil);
    dosayif($VERBOSE_ANY, "%s is %s\n", $fil, $kind);
    $ghprocess{$kind}->($fil,$kind,$plfil);
}

dosayif($VERBOSE_ANY, "+Done\n");
exit($ec);

# 1: file name
# 2: kind
# 3: ref array log
sub process_mysqld_error_log {
    my ($fil, $kind, $plfil) = @ARG;
    dosayif($VERBOSE_ANY, "+START %s %s\n", $kind, $fil);
    my @l2dump = sort(keys(%ghmsg2ignore));
    dosayif($VERBOSE_ANY, "Will ignore messages %s\n", Dumper(\@l2dump));
    dosayif($VERBOSE_ANY, "End ignore messages list\n");
    my %hkind2cnt = ();
    my %hkind2first = ();
    my %hkind2all = ();
    my %hkind2phdistinct = ();
    my $nlins = 0;
    my $nign = 0;
    my $ndifnum = 0;
    foreach my $lin (@$plfil) {
        ++$nlins;
        $lin =~ /([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) (.*)/;
        my ($ts,$num,$lev,$msgnum,$from,$msg) = ($1,$2,$3,$4,$5,$6);
        $msgnum =~ s/[[\]]//g;
        if (defined($ghmsg2ignore{$msgnum})) {
            ++$nign;
            next;
        }
        chomp($msg);
        $lev = "Y!$lev" if ($lev =~ /(error|fatal)/i);
        $lev = "Y!signal$lev" if ($lin =~ / signal /);
        my $kind = "$lev:$msgnum:$from";
        $kind =~ s/[[\]]//g;
        ++$hkind2cnt{$kind};
        ++$ndifnum if ($hkind2cnt{$kind} == 1);
        $hkind2first{$kind} = $msg if (not defined($hkind2first{$kind}));
        $hkind2all{$kind} = [] if (not defined($hkind2first{$kind}));
        $hkind2phdistinct{$kind} = {} if (not defined($hkind2phdistinct{$kind}));
        ++$hkind2phdistinct{$kind}->{$msg};
        push(@{$hkind2all{$kind}},$msg);
        #last;#debug
    }
    foreach my $kind (sort(keys(%hkind2cnt))) {
        dosayif($VERBOSE_ANY, "  %s %s (%s distinct) %s", $kind, $hkind2cnt{$kind}, scalar(keys(%{$hkind2phdistinct{$kind}})),
          $hkind2first{$kind});
    }
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored, %s distinct msg numbers\n", $kind, $fil,$nlins,$nign,$ndifnum);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_mysql_load_out {
    my ($fil, $filekind, $plfil) = @ARG;
    dosayif($VERBOSE_ANY, "%s %s: %s\n", $filekind, $fil, $plfil->[0]);
    dosayif($VERBOSE_ANY, "+START %s %s\n", $filekind, $fil);
    #dosayif($VERBOSE_ANY, "Will ignore messages %s\n", Dumper(\%ghmsg2ignore));
    #dosayif($VERBOSE_ANY, "End ignore messages list\n");
    my %hkind2cnt = ();
    my %hstmtkind2cnt = ();
    my %hkind2first = ();
    my %hkind2firststmt = ();
    my %hkind2all = ();
    my %hkind2phdistinct = ();
    my $nlins = 0;
    my $nign = 0;
    my $ndifnum = 0;
    my $stmtkind = 'NOT_YET';
    my $stmt = 'NOT_YET';
    my $isgood = 1;
    my $areall = 0;
    my $arebad = 0;
    my $areout = 0;
    my $kind = 'UNKNOWN';
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        if ($lin =~ /^------/) {
            ++$nign;
            next;
        }
        if ($lin =~ /^\s*$/) {
            ++$nign;
            next;
        }
        my $msg = 'NONE';
        if ($lin =~ /^mysql: \[Warning\]/) {
            $kind = 'mysql_warning';
        } elsif ($lin =~ /^ERROR ([0-9]+) \(([0-9HYD]+)\) at line [0-9]+: (.*)/) {
            ++$arebad;
            $kind = "ERROR-${1}_${2}-$stmtkind";
            $msg = $3;
    #dosayif($VERBOSE_ANY, "#debug +%s+%s+for+%s+\n", $kind, $msg,$lin);exit(0);
        } elsif ($lin =~ /$GSQL/) {
            ++$areall;
            $lin =~ /^([^ ]+) /;
            $stmtkind = $1;
            ++$hstmtkind2cnt{$stmtkind};
            $stmt = $lin;
            $isgood = 1;
        } elsif ($lin =~ /$GDATA/) {
            ++$areout;
        } else {
            ++$areout;
            #docroak("Line $fil:$nlins: $lin");
        }
        ++$hkind2cnt{$kind};
        ++$ndifnum if ($hkind2cnt{$kind} == 1);
        $hkind2first{$kind} = $msg if (not defined($hkind2first{$kind}));
        $hkind2firststmt{$kind} = $stmt if (not defined($hkind2firststmt{$kind}));
        $hkind2all{$kind} = [] if (not defined($hkind2first{$kind}));
        $hkind2phdistinct{$kind} = {} if (not defined($hkind2phdistinct{$kind}));
        ++$hkind2phdistinct{$kind}->{$msg};
        push(@{$hkind2all{$kind}},$msg);
        #last;#debug
    }
    foreach my $kind (sort(keys(%hkind2cnt))) {
        dosayif($VERBOSE_ANY, "  %s %s (%s distinct) %s : %s", $kind, $hkind2cnt{$kind}, scalar(keys(%{$hkind2phdistinct{$kind}})),
          $hkind2first{$kind}, $hkind2firststmt{$kind});
    }
    dosayif($VERBOSE_ANY, "statement by kind: %s",Dumper(\%hstmtkind2cnt));
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored, %s output, %s statements, %s good, %s bad, %s distinct msg numbers\n", $filekind,
      $fil,$nlins,$nign,$areout,$areall,($areall-$arebad),$arebad,$ndifnum);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_master_thread_log {
    my ($fil, $filekind, $plfil) = @ARG;
    dosayif($VERBOSE_ANY, "%s %s: %s\n", $filekind, $fil, $plfil->[0]);
    dosayif($VERBOSE_ANY, "+START %s %s\n", $filekind, $fil);
    #dosayif($VERBOSE_ANY, "Will ignore messages %s\n", Dumper(\%ghmsg2ignore));
    #dosayif($VERBOSE_ANY, "End ignore messages list\n");
    my %hkind2cnt = ();
    my %hstmtkind2cnt = ();
    my %hkind2first = ();
    my %hkind2firststmt = ();
    my %hkind2all = ();
    my %hkind2phdistinct = ();
    my $nlins = 0;
    my $nign = 0;
    my $ndifnum = 0;
    my $stmtkind = 'NOT_YET';
    my $stmt = 'NOT_YET';
    my $isgood = 1;
    my $areall = 0;
    my $arebad = 0;
    my $areout = 0;
    my $kind = 'UNKNOWN';
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        my ($ts,$lev,$msg) = ('UNKNOWN','UNKNOWN','UNKNOWN');
        ($ts,$lev,$msg) = ($1,$2,$3) if ($lin =~ /^([^ ]+ +[^ ]+) +([^ ]+) +(.*)$/);
        $lev =~ s/://g;
        if (not $lev =~ /^(Info|Warning)$/) {
            docroak("$fil line $nlins: lev '$lev' is not expected: $lin") if ($ts =~ /^[0-9 :-]+$/);
            ++$nign;
            next;
        }
        #dosayif($VERBOSE_ANY, "#debug +%s+%s+for+%s+\n", $lev, $msg,$lin);exit(0);
        my $msgkind = 'UNKNOWN';
        ($msgkind,$msg) = ($1,$2) if ($msg =~ /^ *([^ ]+ +[^ ]+ +[^ ]+) *(.*)$/);
        $msgkind =~ s/ +/_/g;
        $msgkind =~ s/(\.\.\.|:)//g;
        $msgkind =~ s/tid=[0-9]+/tid=N/g;
        $msgkind = "$lev:$msgkind";
        #dosayif($VERBOSE_ANY, "#debug +%s+for+%s+lin+%s+\n", $msgkind, $msg,$lin);exit(0);
        ++$hkind2cnt{$msgkind};
        ++$ndifnum if ($hkind2cnt{$msgkind} == 1);
        $hkind2first{$msgkind} = $msg if (not defined($hkind2first{$msgkind}));
        $hkind2all{$msgkind} = [] if (not defined($hkind2first{$msgkind}));
        $hkind2phdistinct{$msgkind} = {} if (not defined($hkind2phdistinct{$msgkind}));
        ++$hkind2phdistinct{$msgkind}->{$msg};
        push(@{$hkind2all{$msgkind}},$msg);
        #last;#debug
    }
    foreach my $kind (sort(keys(%hkind2cnt))) {
        dosayif($VERBOSE_ANY, "  %s %s (%s distinct) %s", $kind, $hkind2cnt{$kind}, scalar(keys(%{$hkind2phdistinct{$kind}})),
          $hkind2first{$kind});
    }
    dosayif($VERBOSE_ANY, "statement by kind: %s",Dumper(\%hstmtkind2cnt));
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored, %s output, %s statements, %s good, %s bad, %s distinct msg numbers\n", $filekind,
      $fil,$nlins,$nign,$areout,$areall,($areall-$arebad),$arebad,$ndifnum);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_imatest_pl_out {
    my ($fil, $filekind, $plfil) = @ARG;
    dosayif($VERBOSE_ANY, "%s %s: %s\n", $filekind, $fil, $plfil->[0]);
    dosayif($VERBOSE_ANY, "+START %s %s\n", $filekind, $fil);
    #dosayif($VERBOSE_ANY, "Will ignore messages %s\n", Dumper(\%ghmsg2ignore));
    #dosayif($VERBOSE_ANY, "End ignore messages list\n");
    my %hkind2cnt = ();
    my %hstmtkind2cnt = ();
    my %hkind2first = ();
    my %hkind2firststmt = ();
    my %hkind2all = ();
    my %hkind2phdistinct = ();
    my $nlins = 0;
    my $nign = 0;
    my $ndifnum = 0;
    my $stmtkind = 'NOT_YET';
    my $stmt = 'NOT_YET';
    my $isgood = 1;
    my $areall = 0;
    my $arebad = 0;
    my $areout = 0;
    my $kind = 'UNKNOWN';
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        my $waslin = $lin;
        # eliminate prefixes
        # #P 963 2024-03-28 22:33:55.286011 UTC /mnt/c/ima/mud/imatest/imatest.pl  main: random seed is 4201879857 for this script version 2.84
        if ($lin =~ /imatest\.pl /) {
            $lin =~ s/^.*imatest\.pl +//;
            $lin =~ s/:+ +/ /;
        } else {
        # #S 965 20240328223355.383341046 stopms.sh : starting as /mnt/c/ima/mud/imatest/stopms.sh 2 wait 60
            $lin =~ s/^ *[^ ]+ +[^ ]+ +[^ ]+ +//;
            $lin =~ s/ +:+ +/ /;
        }
        # mysql: [Warning] Using a password on the command line interface can be insecure.
        my ($msgkind,$msg) = ('UNKNOWN','UNKNOWN');
        ($msgkind,$msg) = ($1,$2) if ($lin =~ /^([^ ]+) +(.*)$/);
        ($msgkind,$msg) = ("yUse_of_uninitialized_value_line_$nlins",$waslin) if ($waslin =~ /Use of uninitialized value/);
        ($msgkind,$msg) = ("yCROAK_line_$nlins",$waslin) if ($waslin =~ /CROAK/);
        ($msgkind,$msg) = ("yrandom_seed_line_$nlins",$waslin) if ($waslin =~ / random seed is /);
        #docroak("+$msgkind+$msg+for+$waslin+$nlins+") if ($waslin =~ /CROAK/);
        if ($msgkind eq 'UNKNOWN') {
            ++$nign;
            next;
        }
        #dosayif($VERBOSE_ANY, "#debug +%s+and+%s+for+%s+\n", $msgkind,$msg,$lin);next;
        $msgkind =~ s/tid=[0-9]+/tid=N/g;
        ++$hkind2cnt{$msgkind};
        ++$ndifnum if ($hkind2cnt{$msgkind} == 1);
        $hkind2first{$msgkind} = $msg if (not defined($hkind2first{$msgkind}));
        $hkind2all{$msgkind} = [] if (not defined($hkind2first{$msgkind}));
        $hkind2phdistinct{$msgkind} = {} if (not defined($hkind2phdistinct{$msgkind}));
        ++$hkind2phdistinct{$msgkind}->{$msg};
        push(@{$hkind2all{$msgkind}},$msg);
        #last;#debug
    }
    foreach my $kind (sort(keys(%hkind2cnt))) {
        dosayif($VERBOSE_ANY, "  %s %s (%s distinct) %s", $kind, $hkind2cnt{$kind}, scalar(keys(%{$hkind2phdistinct{$kind}})),
          $hkind2first{$kind});
    }
    dosayif($VERBOSE_ANY, "statement by kind: %s",Dumper(\%hstmtkind2cnt));
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored, %s output, %s statements, %s good, %s bad, %s distinct msg numbers\n", $filekind,
      $fil,$nlins,$nign,$areout,$areall,($areall-$arebad),$arebad,$ndifnum);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_unknown {
    my ($fil, $kind, $plfil) = @ARG;
    dosayif($VERBOSE_ANY, "%s %s: %s\n", $kind, $fil, $plfil->[0]);
}
