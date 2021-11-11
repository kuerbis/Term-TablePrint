use 5.10.0;
use warnings;
use strict;

use Test::More;
use Test::Prereq;
prereq_ok( undef, [
    'Win32::Console::ANSI',
    'Term::Choose::Constants',
    'Term::Choose::LineFold',
    'Term::Choose::Linux',
    'Term::Choose::Screen',
    'Term::Choose::ValidateOptions',
    'Term::Choose::Win32',
 ] );
