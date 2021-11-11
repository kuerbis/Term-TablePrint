use 5.10.0;
use strict;
use warnings;
use Test::More tests => 1;

my $file = 'lib/Term/TablePrint.pm';

my $test_env = 0;
open my $fh1, '<', $file or die $!;
while ( my $line = <$fh1> ) {
    if ( $line =~ /\$\s*SIG\s*{\s*__WARN__\s*}/ ) {
        $test_env++;
    }
    if ( $line =~ /^\s*use\s+warnings\s+FATAL/s ) {
        $test_env++;
    }
    if ( $line =~ /(?:^\s*|\s+)use\s+Log::Log4perl/ ) {
        $test_env++;
    }
    if ( $line =~ /(?:^\s*|\s+)use\s+Data::Dumper/ ) {
        $test_env++;
    }
}
close $fh1;
is( $test_env, 0, "OK - test environment in $file disabled." );
