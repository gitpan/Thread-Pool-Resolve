BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use strict;
use Test::More tests => 12 + 38;

BEGIN { use_ok('Thread::Pool::Resolve') }

our $optimize = 'memory';
my $require = 'resolveit';
$require = "t/$require" unless $ENV{PERL_CORE};
require $require;
