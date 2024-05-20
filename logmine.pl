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

my @L2IGNORE = ('\.sql$', 'check1sa\.sh\.out', '[/]?test\.out$');
my @LMSG2IGNORE = qw(MY-010048 MY-012203 MY-010949 MY-010050 MY-010051 MY-010054 MY-010006 MY-010043 MY-010117 MY-010120 MY-010252 MY-011089
 MY-011944 MY-011946 MY-011951 MY-011980 MY-012204 MY-012208 MY-012255 MY-012265 MY-012330 MY-012357 MY-012533 MY-012560 MY-012910 MY-012923
 MY-012932 MY-012937 MY-012944 MY-012945 MY-012948 MY-012951 MY-012955 MY-012957 MY-012976 MY-013018 MY-013083 MY-013084 MY-013086 MY-013252
 MY-010252 MY-013012 MY-010182 MY-010067 MY-010118 MY-011953 MY-012356 MY-012366 MY-012398 MY-012487 MY-012488 MY-012532 MY-012535 MY-012550
 MY-012922 MY-013532 MY-013546 MY-013546 MY-013546 MY-013627 MY-013565 MY-013566 MY-013627 MY-013776 MY-013854 MY-013883 MY-013911 MY-013952
 MY-010116 MY-010747 MY-012266 MY-013932 MY-015015 MY-015019 MY-011323 MY-011332 MY-010182 MY-010304 MY-010068 MY-013602 MY-010308 MY-010253
 MY-010264 MY-010251 MY-011240 MY-011243 MY-010733 MY-010101 MY-013953 MY-013954 MY-015020 MY-015021 NY-015022 MY-015023 MY-015024 MY-012980
 MY-015022 MY-013576 MY-013577 MY-015016 MY-010161 MY-010918 MY-011069 MY-011070 MY-013360 MY-013011 MY-013014 MY-013014 MY-013023 MY-013024
 MY-013177 MY-014016 MY-014017 MY-014018 MY-014019 MY-014021 MY-014022 MY-014023 MY-013015 MY-013777 MY-012050 MY-012230 MY-012233 MY-012234
 MY-012235 MY-012236 MY-013550 MY-015025 MY-015026 MY-010909 MY-012551 MY-012552 MY-013072 MY-010910 MY-010931 MY-013172
                    );
my %ghmsg2ignore = ();
my $GDATA = '^(ALTER|BEGIN|CHECK|Table\s+Op\s|.*\scheck\s+status\s+OK|COMMIT|EXPLAIN|->|id\s+select_type|[0-9]+\s+INSERT|INSERT|SELECT|UPDATE|pk[0-9]+|col[0-9]+|.?\s?[\s0-9a-zA-Z_]+\s?) ?';
my $GSQL = '^(ALTER|BEGIN|CHECK|COMMIT|EXPLAIN|INSERT|SELECT|UPDATE) ?';

my %ghasopt = ();
my $gdosayoff = 2;

my $gloadthreads = 0;
my %ghloadec2count = ();     # cumulative load thread error code -> count
my %ghloadmsg2count = ();    # cumulative load thread error code stmt kind stmt -> count

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

    open(my $fh, $fil) or croak("failed to open $fil. CROAK.");
    foreach my $lin (@$pltext) {
        printf $fh "%s\n", $lin;
    }
    close($fh);

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
my @l2mine = ();
    FIL:
foreach my $fil (@l2see) {
    if (-d $fil) {
        dosayif($VERBOSE_ANY, "=== %s is directory, ignore", $fil);
        next;
    }
    if (not -f $fil) {
        dosayif($VERBOSE_ANY, "=== %s is not a file, ignore", $fil);
        next;
    }
    foreach my $rign (@L2IGNORE) {
        next unless ($fil =~ /$rign/);
        dosayif($VERBOSE_ANY, "=== %s is %s, ignore", $fil, $rign);
        next FIL;
    }
    push(@l2mine,$fil);
}
dosayif($VERBOSE_ANY, "");

# 1: file name
# 2: ref array contents
sub getkind {
    my ($fil,$plfil) = @ARG;
    return 'mysqld_error_log' if ($fil =~ /\/?error\.log$/);
    return 'check_thread_out' if ($fil =~ /\/?check_thread\.out$/);
    return 'destructive_thread_out' if ($fil =~ /\/?destructive_thread_[0-9]+\.out$/);
    return 'mysql_load_out' if ($fil =~ /\/?load_thread_[0-9]+\.out$/);
    return 'master_thread_log' if ($fil =~ /\/?master_thread\.log$/);
    return 'imatest_pl_out' if ($fil =~ /\/?imatest\.pl\.out$/);
    return 'UNKNOWN';
}

my %ghprocess = (
    'mysqld_error_log' => \&process_mysqld_error_log,
    'master_thread_log' => \&process_master_thread_log,
    'mysql_load_out' => \&process_load_thread_out,
    'check_thread_out' => \&process_check_thread_out,
    'destructive_thread_out' => \&process_destructive_thread_out,
    'imatest_pl_out' => \&process_imatest_pl_out,
    'UNKNOWN' => \&process_unknown,
);

my $ec = 0;

foreach my $fil (@l2mine) {
    my $plfil = readfile($fil);
    my $kind = getkind($fil,$plfil);
    dosayif($VERBOSE_ANY, "=== %s is %s\n", $fil, $kind);
    $ghprocess{$kind}->($fil,$kind,$plfil);
}

dosayif($VERBOSE_ANY, "CUMULATIVE FOR %s LOAD THREADS:\n",$gloadthreads);
my $ec2count = '';
foreach my $key (sort(keys(%ghloadec2count))) {
    $ec2count .= ", $key: $ghloadec2count{$key}";
}
$ec2count =~ s/, //;

foreach my $key (sort(keys(%ghloadmsg2count))) {
    my $nl = ($key =~ /TOTL/ and not $key =~ /ETOTL/)? "\n" : '';
    dosayif($VERBOSE_ANY, "%s%s: %s", $nl, $key, $ghloadmsg2count{$key});
}
dosayif($VERBOSE_ANY, "\n%s\n", $ec2count);

dosayif($VERBOSE_ANY, "+Done\n");
exit($ec);

# 1: file name
# 2: kind
# 3: ref array log
sub process_mysqld_error_log {
    my ($fil, $kind, $plfil) = @ARG;
    my @l2dump = sort(keys(%ghmsg2ignore));
    dosayif($VERBOSE_ANY, "Will ignore messages %s\n", join(' ',sort(@l2dump)));
    dosayif($VERBOSE_ANY, "End ignore messages list\n");
    my %hkind2cnt = ();
    my %hkind2first = ();
    my %hkind2all = ();
    my %hkind2phdistinct = ();
    my $nlins = 0;
    my $nign = 0;
    my $ndifnum = 0;
    LIN:
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        if ($lin eq "") {
            ++$nign;
            next;
        }
        $lin =~ /([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) (.*)/;
        my ($ts,$num,$lev,$msgnum,$from,$msg) = ($1,$2,$3,$4,$5,$6);
        $msgnum = 'NOMSGNUM' if (not defined($msgnum));
        $lev = 'NOLEV' if (not defined($lev));
        $msg = "+$lin+" if (not defined($msg));
        $from = 'NOFROM' if (not defined($from));
        $msgnum =~ s/[[\]]//g;
        if (defined($ghmsg2ignore{$msgnum})) {
            ++$nign;
            next;
        }
        foreach my $mnum (@l2dump) {
            if ($lin =~ /$mnum/) {
                ++$nign;
                next LIN;
            }
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
sub process_master_thread_log {
    my ($fil, $filekind, $plfil) = @ARG;
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
        my $msgkind = 'UNKNOWN';
        ($msgkind,$msg) = ($1,$2) if ($msg =~ /^ *([^ ]+ +[^ ]+ +[^ ]+) *(.*)$/);
        $msgkind =~ s/ +/_/g;
        $msgkind =~ s/(\.\.\.|:)//g;
        $msgkind =~ s/tid=[0-9]+/tid=N/g;
        $msgkind = $msg if ($msgkind eq 'UNKNOWN' or $msg =~ /mysqlx_ssl_cipher/ or $msgkind eq 'Info');
        if ($msg=~ /(Loading.plugins|select...sql_mode|mysqlx_ssl_cipher)/) {
            ++$nign;
            next;
        }
        if ($msgkind =~ /^(Connecting_to_MySQL|Loading.plugins|Loading_startup_files|Using_credential_store|main_tid=N_CONNECTED|Using_a_password)$/) {
            ++$nign;
            next;
        }
        $msgkind = "$lev:$msgkind";
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
    my @ltoignore = qw (
  replacing.([a-z_]+).of
  (start_destructive_thread|start_load_thread):.random
  refused,connecting
  line.[0-9]+.$
  main.*invoked
  main.*letting
  main.*eliminating
  main.*process
  main.*starting
  main.*Options
  checkscript
  sandbox.as.root
  can.be.insecure
  Killing.MySQL
  forgetting.it
  (start|server)_check_thread
  init_db
  for.db.init
  startup.files
  to.MySQL.at
  tid=[0-9]+:.(SQL|CONNECTED):
  (gethashref|getarrayref|runreport).*(SUCCESS|ERROR.*(1070|1008|1064|1118|1167|1146|1071))
  db_create.will.create
  db_create.*(returning|remove)
  start_destructive_thread
  server_destructive_thread
  start_load_thread
  server_load_thread
  and.*and.*and
  Starting.MySQL.instance
  Connection.refused
  in.dba.startSandboxInstance
  file.matches
  main.*exit.code.0
  main.*new.*load.thread
  main.*See.also
                       );
    LIN:
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        foreach my $toign (@ltoignore) {
            if ($lin =~ /$toign/) {
                ++$nign;
                next LIN;
            }
        }
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
        if ($msgkind eq 'UNKNOWN') {
            ++$nign;
            next;
        }
        $msgkind =~ s/tid=[0-9]+/tid=N/g;
        dosayif($VERBOSE_ANY, "%s",$lin);
    }
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored, %s output, %s statements, %s good, %s bad, %s distinct msg numbers\n", $filekind,
      $fil,$nlins,$nign,$areout,$areall,($areall-$arebad),$arebad,$ndifnum);
}
#===

# 1: file name
# 2: kind
# 3: ref array log
sub process_unknown {
    my ($fil, $kind, $plfil) = @ARG;
    dosayif($VERBOSE_ANY, "%s %s: %s\n", $kind, $fil, $plfil->[0]);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_check_thread_out {
    my ($fil, $filekind, $plfil) = @ARG;
    my $nlins = 0;
    my $nign = 0;
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        if (not $lin =~ /CHECK_THREAD_STATE_CHANGE_HOW/) {
            ++$nign;
            next;
        }
        if ($lin =~ /^\s*$/) {
            ++$nign;
            next;
        }
        dosayif($VERBOSE_ANY, "%s",$lin);
    }
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored\n", $filekind,$fil,$nlins,$nign);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_destructive_thread_out {
    my ($fil, $filekind, $plfil) = @ARG;
    my $nlins = 0;
    my $nign = 0;
    my @LDESTR2IGNORE = qw (
  (check|start|wait|stop|kill)(1sa|ms).sh.:.(found|starting|executing|exiting|exit|finished|started|instance)
  server_destructive_thread:..?(exiting|sleeping|destructive|started|random|will.sleep|terminating|execution|starting|restarting)
  (Starting|Killing).MySQL.instance
  Instance.[^:]+:[0-9]+ successfully.(killed|started)
  Using.a.password
  wait1sa.sh.:.(root|timeout)
  check1sa.sh.*(binary.file.matches|will.wait)
  kill:.not.enough.arguments
  Unable.to.lock.sandbox.directory
  at.*command.line
  in.dba.startSandboxInstance
  ^\s*\^\s*$
  Dba.startSandboxInstance.*(port.*is.already.in.use|Starting.*as.root.is.not.recommended)
  Error.starting.sandbox:.Timeout.waiting
  checkms.sh.:.0.signals.or.assertions
                           );

    dosayif($VERBOSE_ANY,"will ignore the following patterns: %s\n","@LDESTR2IGNORE");
    LIN:
    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        if ($lin =~ /^\s*$/) {
            ++$nign;
            next;
        }
        foreach my $ig (@LDESTR2IGNORE) {
            if ($lin =~ /$ig/) {
                ++$nign;
                next LIN;
            }
        }
        dosayif($VERBOSE_ANY, "%s",$lin);
    }
    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored\n", $filekind,$fil,$nlins,$nign);
}

# 1: file name
# 2: kind
# 3: ref array log
sub process_load_thread_out {
    my ($fil, $filekind, $plfil) = @ARG;
    my $nlins = 0;
    my $nign = 0;
    my $interim = 0;
    my $final = 0;
    my @lrep = ();
    ++$gloadthreads;
    my @lmust = qw(
      CROAK
                  );

    foreach my $lin (@$plfil) {
        ++$nlins;
        chomp($lin);
        foreach my $must (@lmust) {
            if ($lin =~ /$must/) {
                dosayif($VERBOSE_ANY, "%s", $lin);
                last;
            }
        }
        if ($lin =~ /=== INTERIM LOAD THREAD/) {
            $interim = $nlins;
            @lrep = ();
            next;
        }
        if ($lin =~ /=== FINAL BY /) {
            $final = $nlins;
            @lrep = ();
            next;
        }
        push(@lrep,$lin);
    }

    if ($interim == 0 and $final == 0) {
        dosayif($VERBOSE_ANY, "=== PROBLEM: no load reports in %s", $fil);
    } elsif ($final == 0) {
        dosayif($VERBOSE_ANY, "=== PROBLEM: no FINAL load report in %s, will use last INTERIM with %s lines", $fil,scalar(@lrep));
    } else {
        dosayif($VERBOSE_ANY, "(accumulating) FINAL load report in %s, %s lines: ", $fil,scalar(@lrep));
    }
    my $dosay = 0;
    $nign = $nlins - scalar(@lrep);
    foreach my $lin (@lrep) {
        $dosay = 0 if ($lin =~ /ERROR TO LAST MSG/);
        $dosay = 0 if ($lin =~ /see also/);
        $dosay = 1 if ($lin =~ /ERROR STMT KIND COUNTS/);
        $dosay = 1 if ($lin =~ /ERROR COUNTS/);
        if ($dosay) {
            dosayif($VERBOSE_MORE, "%s",$lin) if ($dosay);
            if ($lin =~ /ERROR COUNTS/) {
                my $top = $lin;
                $top =~ s/.*ERROR COUNTS://;
                my @lot = split(/,/,$top);
                foreach my $suc (@lot) {
                    $suc =~ s/ //g;
                    my @lsu = split(/:/,$suc);
                    $ghloadec2count{$lsu[0]} += $lsu[1];
                }
            }
            if ($lin =~ /^ *E([0-9]+|FAIL|GOOD|TOTL) /) {
                my $top = $lin;
                $top =~ /^ *(E[0-9]+|EFAIL|EGOOD|ETOTL) +(.*): +([0-9]+),? *$/;
                $ghloadmsg2count{"$1 $2"} += $3;
            }
        } else {
            ++$nign;
        }
    }

    dosayif($VERBOSE_ANY, "END %s %s: %s lines, %s ignored\n", $filekind,$fil,$nlins,$nign);
}
