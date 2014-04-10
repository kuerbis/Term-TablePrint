use 5.010001;
use strict;
use warnings;
use Test::More;

use Test::Spelling;


add_stopwords( <DATA> );

all_pod_files_spelling_ok( 'lib' );



__DATA__
BNRY
Kiem
Matthäus
repexp
stackoverflow