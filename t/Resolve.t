BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use strict;
use Test::More tests => 50;

BEGIN { use_ok('Thread::Pool::Resolve') }
BEGIN { use_ok('IO::File') }
BEGIN { use_ok('Storable',qw(store retrieve)) }
BEGIN { use_ok('Thread::Queue') }

can_ok( 'Thread::Pool::Resolve',qw(
 add
 autoshutdown
 line
 lines
 maxjobs
 minjobs
 new
 rand_domain
 rand_ip
 read
 remove
 resolved
 resolver
 self
 shutdown
 todo
 workers
) );

my $unresolved = 'unresolved';
my $resolved = 'resolved';
my $filter = 'filter';
my $filtered = 'filtered';
my $ip2domain = 'ip2domain';

diag( "Creating test log files" );

my @ip;
my %ip2domain;
my %domain2ip;

my $domainref = Thread::Pool::Resolve->can( 'rand_domain' );
my $ipref = Thread::Pool::Resolve->can( 'rand_ip' );

for (my $i = 1; $i <= 100; $i++) {
  my ($ip,$domain) = (&$ipref,&$domainref);
  push( @ip,$ip );
  $ip2domain{$ip} = $domain;
  $domain2ip{$domain} = $ip;
}

for (my $i = 1; $i <= 30; $i++) {
  my $ip = &$ipref;
  push( @ip,$ip );
  $ip2domain{$ip} = '';
}

ok( store( \%ip2domain,$ip2domain ),	'save ip2domain hash with Storable' );

ok( open( my $out1,'>',$unresolved ),	'create unresolved log file' );
ok( open( my $out2,'>',$resolved ),	'create resolved log file' );
for (my $i = 1; $i <= 1000; $i++) {
  my $ip = $ip[int(rand(@ip))];
  my $domain = $ip2domain{$ip} || $ip;
  my $hits = 1+int(rand(10));
  foreach (1..$hits) {
    print $out1 "$ip $i\n";
    print $out2 "$domain $i\n";
    $i++;
  }
  $i--;
}
ok( close( $out1 ),			'close unresolved log file' );
ok( close( $out2 ),			'close resolved log file' );

diag( "Test simple external log resolve filter" );

ok( open( my $script,'>',$filter ),	'create script file' );
print $script <<EOD;
\@INC = qw(@INC);

use Storable qw(retrieve);
my \$ip2domain = retrieve( '$ip2domain' );

sub gethostbyaddr { sleep( rand(2) ); \$ip2domain->{\$_[0]} }

use Thread::Pool::Resolve;
my \$r = Thread::Pool::Resolve->new( {resolver => 'gethostbyaddr'} )->read;
EOD
ok( close( $script ),			'close script file' );

ok( !system( "$^X $filter <$unresolved >$filtered" ), 'filter unresolved' );

ok( check( $resolved,$filtered ),	'check result of script filter' );

diag( "Test resolving from a file" );
my $resolve =
 Thread::Pool::Resolve->new( {resolver => 'gethostbyaddr'}, $filtered );
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->read( $unresolved ),	'read from file' );
$resolve->shutdown;
ok( check( $resolved,$filtered ),	'check result of file' );

diag( "Test resolving from an open()ed handle" );
ok( open( my $log,'<',$unresolved ),	'open GLOB log file' );
my $resolve =
 Thread::Pool::Resolve->new( {resolver => 'gethostbyaddr'}, $filtered );
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->read( $log ),		'read from opened GLOB' );
$resolve->shutdown;
ok( check( $resolved,$filtered ),	'check result of opened GLOB' );
ok( close( $log ),			'close GLOB log file' );

diag( "Test resolving from an IO::File->new handle" );
$log = IO::File->new( $unresolved,'<' );
isa_ok( $log,'IO::Handle', 		'check IO::File handle' );
$resolve = Thread::Pool::Resolve->new(
 {
  open => sub { IO::File->new( @_ ) },
  resolver => 'gethostbyaddr',
 },
 $filtered
);
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->read( $log ),		'read from opened IO::File' );
$resolve->shutdown;
ok( check( $resolved,$filtered ),	'check result of opened IO::File' );
ok( close( $log ),			'close IO::File log file' );

diag( "Test resolving from a SCALAR handle" );
ok( open( $log,'<',$unresolved ),	'check opening unresolved file' );
my $scalar;
{local $/; $scalar = <$log>}
ok( close( $log ),			'check closing unresolved file' );

ok( open( $log,'<',\$scalar ),		'check SCALAR handle' );
my $output;
$resolve = Thread::Pool::Resolve->new(
 {
  pre => sub { open( $output,'>',$filtered ) or die "$filtered: $!" },
  monitor => sub { print $output $_[0] },
  post => sub { close( $output ) },
  resolver => 'gethostbyaddr',
 }
);
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->read( $log ),		'read from opened SCALAR' );
$resolve->shutdown;
ok( check( $resolved,$filtered ),	'check result of opened SCALAR' );
ok( close( $log ),			'close IO::File log file' );

diag( "Test resolving from a list" );
ok( open( $log,'<',$unresolved ),	'check opening unresolved file' );
my @array = <$log>;
ok( close( $log ),			'check closing unresolved file' );
$resolve = Thread::Pool::Resolve->new( {resolver => 'gethostbyaddr'},$filtered);
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->lines( @array ),		'check object returned from lines' );
$resolve->shutdown;
ok( check( $resolved,$filtered ),	'check result from lines' );

diag( "Test resolving from different threads" );
my @shared : shared = @array;
$resolve = Thread::Pool::Resolve->new( {resolver => 'gethostbyaddr'},$filtered);
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
my @thread;
push( @thread,threads->new( \&bythread ) ) foreach 1..10;
$_->join foreach @thread;
$resolve = undef;
ok( check( $resolved,$filtered ),	'check result different threads' );

diag( "Test resolving from Thread::Queue" );
@shared = (@array,undef);
my $queue = bless \@shared,'Thread::Queue';
isa_ok( $queue,'Thread::Queue',		'check object type' );
$resolve = Thread::Pool::Resolve->new( {resolver => 'gethostbyaddr'},$filtered);
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->read( $queue ),		'check result of reading with queue' );
$resolve = undef;
ok( check( $resolved,$filtered ),	'check result Thread::Queue' );

diag( "Test resolving using Thread::Conveyor" );
my $belt = Thread::Conveyor->new;
isa_ok( $belt,'Thread::Conveyor',	'check object type' );
$belt->put( $_ ) foreach @array,undef;
$resolve = Thread::Pool::Resolve->new(
 {
  resolved => retrieve( $ip2domain ),
  resolver => 'gethostbyaddr',
 },
 $filtered
);
isa_ok( $resolve,'Thread::Pool::Resolve', 'check object type' );
ok( $resolve->read( $belt ),		'check result of reading with belt' );
$resolve = undef;
ok( check( $resolved,$filtered ),	'check result Thread::Conveyor' );

ok( unlink( $unresolved,$resolved,$filter,$filtered ), 'remove created files' );

#=======================================================================

# necessary subroutines

# adding resolve lines by shared array per thread

sub bythread {
  local ($_);
  READ: while (1) {
    {lock( @shared );
     my $line = shift( @shared );
     last READ unless defined( $line );
     $resolve->line( $line );
    }
  }
}

# resolve from the dummy hash

sub gethostbyaddr { sleep( rand(2) ); $ip2domain{$_[0]} }

# check two files and return true if they are the same

sub check {

  my ($file1,$file2) = @_;
  open( my $handle1,'<',$file1 ) or return 0;
  open( my $handle2,'<',$file2 ) or return 0;

  while (readline( $handle1 )) {
    my $line = readline( $handle2 );
    return 0 unless defined($line);
    next if $line eq $_;
    return 0;
  }
  my $line = readline( $handle2 );
  return !defined($line);
}
