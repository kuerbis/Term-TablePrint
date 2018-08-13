package # hide from PAUSE
Term::TablePrint::ProgressBar;

use strict;
use warnings;
use 5.008003;

use Term::Choose::LineFold  qw( print_columns cut_to_printwidth );

use constant DEFAULTS => {
    fh         => \*STDERR,
    name       => undef,
    term_width => undef,
    count      => undef,
    remove     => 0,
    #silent     => 0,
};


sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init( @_ );
    return $self;
}


sub init {
    my ( $self, $config ) = @_;
    my $target = delete $config->{count};
    my $term_w = $config->{term_width};
    die if ! defined $target;
    die if ! defined $term_w;
    for ( keys %{DEFAULTS()} ) {
        $self->{$_} = exists $config->{$_} ? $config->{$_} : DEFAULTS->{$_};
    }
    $self->{bar_width} = $term_w - 7; # for the  "100% ["  and the  "]"
    if ( defined $self->{name} ) {
        my $name = $self->{name};
        my $name_w = print_columns( $self->{name} );
        my $max_name_w = int( $term_w / 3 );
        if ( $name_w > $max_name_w ) {
            $name = cut_to_printwidth( $name, $max_name_w );
            $name_w = $max_name_w;
        }
        $self->{bar_width} -= $name_w;
        $self->{bar_width} -= 2; # for the ': '
    }
    $self->{short_print_fmt} = 0;
    if ( $self->{bar_width} < 8 ) {
        $self->{bar_width} = $term_w - 7;
        $self->{short_print_fmt} = 1;
        if ( $self->{bar_width} < 5 ) {
            $self->{bar_width} = $term_w;
            $self->{short_print_fmt} = 2;
        }
    }
    $self->{major_units} = $self->{bar_width} / $target;
    my $prev_fh = select( $self->{fh} );
    local $| = 1;
    select( $prev_fh );
    $self->{last_update} = 0;
    $self->{target} = $target;
    $self->update( 0 ); # Initialize the progress bar

}


sub update {
    my ( $self, $so_far ) = @_;
    $self->{last_update} = $so_far;
    #if ( $self->{silent} ) {
    #    # returning target + 1 as next value should avoid calling update
    #    # method in the smooth form of using the progress bar
    #    return $self->{target} + 1;
    #}
    my $target = my $next = $self->{target};
    my @chars = ( ' ' ) x $self->{bar_width};
    my $biggies = $self->{major_units} * $so_far;
    for ( 0 .. $biggies - 1 ) {
        $chars[$_] = '=';
    }
    $next *= ( $self->{major_units} * $so_far + 1 ) / $self->{bar_width};
    local $\ = undef;
    my $to_print = "\r";
    if ( $self->{short_print_fmt} == 2 ) {
        $to_print .= join '', @chars;
    }
    else {
        if ( defined $self->{name} && ! $self->{short_print_fmt} ) {
            $to_print .= $self->{name} . ': ';
        }
        my $ratio = $so_far / $target;
        # Rounds down %
        $to_print .= sprintf "%3d%% [%s]", $ratio * 100, join '', @chars;
    }
    my $fh = $self->{fh};
    print $fh $to_print;
    if ( $so_far >= $target && $self->{remove} && ! $self->{pb_ended} ) {
        print $fh "\r", ' ' x $self->{term_width}, "\r";
        $self->{pb_ended} = 1;
    }
    if ( $next > $target ) {
        $next = $target;
    }
    return $next;
}



1;

__END__
