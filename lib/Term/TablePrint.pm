package Term::TablePrint;

use warnings;
use strict;
use 5.008003;

our $VERSION = '0.101';
use Exporter 'import';
our @EXPORT_OK = qw( print_table );

use Carp         qw( croak );
use List::Util   qw( sum );
use Scalar::Util qw( looks_like_number );

use Term::Choose                  qw( choose );
use Term::Choose::Constants       qw( :screen );
use Term::Choose::LineFold        qw( line_fold cut_to_printwidth print_columns );
use Term::Choose::Util            qw( term_width insert_sep unicode_sprintf );
use Term::TablePrint::ProgressBar qw();


my $Plugin;
BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Term::Choose::Win32;
        $Plugin = 'Term::Choose::Win32';
    }
    else {
        require Term::Choose::Linux;
        $Plugin = 'Term::Choose::Linux';
    }
}


sub new {
    # 'print_table' as a function uses its own implicit new
    my $class = shift;
    croak "new: called with " . @_ . " arguments - 0 or 1 arguments expected." if @_ > 1;
    my ( $opt ) = @_;
    my $self = bless {}, $class;
    if ( defined $opt ) {
        croak "new: The (optional) argument is not a HASH reference." if ref $opt ne 'HASH';
        $self->__validate_options( $opt );
    }
    $self->{backup_opt} = { defined $opt ? %$opt : () };
    $self->{plugin} = $Plugin->new();
    return $self;
}


sub DESTROY {
    my ( $self ) = @_;
    $self->{plugin}->__show_cursor();
}


sub __validate_options {
    my ( $self, $opt ) = @_;
    my $valid = {
        max_rows         => '[ 0-9 ]+',
        min_col_width    => '[ 0-9 ]+',
        progress_bar     => '[ 0-9 ]+',
        tab_width        => '[ 0-9 ]+',
        choose_columns   => '[ 0 1 ]',
        binary_filter    => '[ 0 1 ]',
        codepage_mapping => '[ 0 1 ]',
        color            => '[ 0 1 ]',
        grid             => '[ 0 1 ]',
        keep_header      => '[ 0 1 ]',
        squash_spaces    => '[ 0 1 ]',
        table_expand     => '[ 0 1 2 ]',
        mouse            => '[ 0 1 2 3 4 ]',
        binary_string    => '',
        prompt           => '',
        undef            => '',
        #thsd_sep        => '',
    };
    for my $key ( keys %$opt ) {
        if ( ! exists $valid->{$key} ) {
            croak "print_table: '$key' is not a valid option name.";
        }
        next if ! defined $opt->{$key};
        if ( $valid->{$key} eq '' ) {
            $self->{$key} = $opt->{$key};
        }
        elsif ( $opt->{$key} =~ /^$valid->{$key}\z/x ) {
            $self->{$key} = $opt->{$key};
        }
        else {
            croak "print_table: '$opt->{$key}' is not a valid value for option '$key'.";
        }
    }
}

sub __set_defaults {
    my ( $self ) = @_;
    $self->{binary_filter}    = 0      if ! defined $self->{binary_filter};
    $self->{binary_string}    = 'BNRY' if ! defined $self->{binary_string};
    $self->{choose_columns}   = 0      if ! defined $self->{choose_columns};
    $self->{codepage_mapping} = 0      if ! defined $self->{codepage_mapping};
    $self->{color}            = 0      if ! defined $self->{color};
    $self->{grid}             = 0      if ! defined $self->{grid};
    $self->{keep_header}      = 1      if ! defined $self->{keep_header};
    $self->{squash_spaces}    = 0      if ! defined $self->{squash_spaces};
    $self->{max_rows}         = 200000 if ! defined $self->{max_rows};
    $self->{min_col_width}    = 30     if ! defined $self->{min_col_width};
    $self->{mouse}            = 0      if ! defined $self->{mouse};
    $self->{progress_bar}     = 40000  if ! defined $self->{progress_bar};
    $self->{prompt}           = ''     if ! defined $self->{prompt};
    $self->{tab_width}        = 2      if ! defined $self->{tab_width};
    $self->{table_expand}     = 1      if ! defined $self->{table_expand};
    $self->{undef}            = ''     if ! defined $self->{undef};
    $self->{thsd_sep} = ',';
    $self->{tab_w}    = $self->{tab_width};
    $self->{tab_w}++    if $self->{grid} && ! ( $self->{tab_width} % 2 );
}


sub print_table {
    if ( ref $_[0] ne 'Term::TablePrint' ) {
        return print_table( bless( { plugin => $Plugin->new() }, 'Term::TablePrint' ), @_ );
    }
    my $self = shift;
    my ( $table_ref, $opt ) = @_;
    croak "print_table: called with " . @_ . " arguments - 1 or 2 arguments expected." if @_ < 1 || @_ > 2;
    croak "print_table: requires an ARRAY reference as its first argument."            if ref $table_ref  ne 'ARRAY';
    if ( defined $opt ) {
        croak "print_table: the (optional) second argument is not a HASH reference."   if ref $opt ne 'HASH';
        $self->__validate_options( $opt );
    }
    if ( ! @$table_ref ) {
        choose( [ 'Close with ENTER' ], { prompt => "'print_table': empty table without header row!" } );
        return;
    }
    $self->__set_defaults();
    my $table_rows = @$table_ref - 1;
    if ( $self->{max_rows} && $table_rows >= $self->{max_rows} ) {
        $self->{info_row} = sprintf( 'Reached the row LIMIT %s', insert_sep( $self->{max_rows}, $self->{thsd_sep} ) );
        if ( $table_rows > $self->{max_rows} ) { # because for App::DBBrowser adding "(Total %d)" would be wrong
            $self->{info_row} .= sprintf( '  (total %s)', insert_sep( $table_rows, $self->{thsd_sep} ) );
        }
        $self->{idx_last_row} = $self->{max_rows}; # -1 for index and +1 for header row
    }
    else {
        $self->{idx_last_row} = $#$table_ref;
    }
    local $| = 1;
    $self->{plugin}->__hide_cursor();
    if ( $self->{choose_columns}  ) {
        $self->{orig_col_idxs} = $self->__choose_columns( $table_ref->[0] );
        return if ! defined $self->{orig_col_idxs};
    }
    else {
        $self->{orig_col_idxs} = [ 0 .. $#{$table_ref->[0]} ];
    }
    $self->{row_idxs} = [ 0 .. $self->{idx_last_row} ];
    $self->{orig_table} = $table_ref;
    $self->__recursive_code();
    if ( exists $self->{backup_opt} ) {
        my $backup_opt = $self->{backup_opt};
        for my $key ( keys %$self ) {
            if ( $key eq 'plugin' || $key eq 'backup_opt' ) {
                next;
            }
            elsif ( exists $backup_opt->{$key} ) {
                $self->{$key} = $backup_opt->{$key};
            }
            else {
                delete $self->{$key};
            }
        }
    }
    $self->{plugin}->__show_cursor();
}


sub __print_single_row {
    my ( $self, $row, $len_key ) = @_;
    my $orig_tbl = $self->{orig_table};
    my $term_w = term_width();
    $len_key = int( $term_w / 100 * 33 ) if $len_key > int( $term_w / 100 * 33 );
    my $separator = ' : ';
    my $len_sep = print_columns( $separator );
    my $col_max = $term_w - ( $len_key + $len_sep + 1 );
    my $row_data = [ ' Close with ENTER' ];

    for my $col ( @{$self->{orig_col_idxs}} ) {
        push @{$row_data}, ' ';
        my $key = $orig_tbl->[0][$col];
        if ( ! defined $key ) {
            $key = $self->{undef};
        }
        if ( $self->{color} ) {
            $key =~ s/\e\[[\d;]*m//msg;
        }
        $key =~ s/\t/ /g;
        $key =~ s/[\x{000a}-\x{000d}\x{0085}\x{2028}\x{2029}]+/\ \ /g;
        $key =~ s/[\p{Cc}\p{Noncharacter_Code_Point}\p{Cs}]//g;
        $key = cut_to_printwidth( $key, $len_key );
        my $sep = $separator;
        my $value = $orig_tbl->[$row][$col];
        if ( ! defined $value || $value eq '' ) {
            push @{$row_data}, sprintf "%*.*s%*s%s", $len_key, $len_key, $key, $len_sep, $sep, '';
        }
        else {
            if ( $self->{color} ) {
                $value =~ s/\e\[[\d;]*m//msg;
            }
            if ( ref $value ) {
                $value = _handle_reference( $value );
            }
            for my $line ( split /\n+/, line_fold( $value, $col_max, '', '' ) ) {
                push @{$row_data}, sprintf "%*.*s%*s%s", $len_key, $len_key, $key, $len_sep, $sep, $line;
                $key = '' if $key;
                $sep = '' if $sep;
            }
        }
    }
    choose(
        $row_data,
        { prompt => '', layout => 3, clear_screen => 1, mouse => $self->{mouse}, hide_cursor => 0 }
    );
}


sub __recursive_code {
    my ( $self ) = @_;
    my $count_cells = ( $self->{idx_last_row} + 1 ) * @{$self->{orig_col_idxs}};
    if ( $self->{progress_bar} && $self->{progress_bar} < $count_cells ) {
        $self->{plugin}->__clear_screen();
        print 'Computing:';
        my ( $type, $total, $name );
        if ( ( $count_cells / $self->{progress_bar} ) > 50 ) {
            $type = 'multi';
            $total = $self->{idx_last_row} + 1;
        }
        else {
            $type = 'single';
            $total = ( $self->{idx_last_row} + 1 ) * 3;
            $name = 'Computing: ';
        }
        $self->{progress} = Term::TablePrint::ProgressBar->new( { count => $total, name => $name } );
        $self->{progress_status} = [ $type, $total, 0, 0 ];
    }
    $self->{table_copy} = [];
    $self->__copy_table();
    $self->__calc_col_width();
    my $term_w = term_width();
    my $w_cols = $self->__calc_avail_col_width( $term_w );
    if ( ! defined $w_cols ) {
        return;
    }
    my $list = $self->__cols_to_string( $w_cols );
    my $table_w = sum( @$w_cols, $self->{tab_w} * $#{$w_cols} );
    my @header;
    if ( length $self->{prompt} ) {
        @header = ( $self->{prompt} );
    }
    if ( $self->{keep_header} ) {
        my $col_names = shift @$list;
        push @header, $col_names;
        push @header, $self->__header_sep( $w_cols ) if $self->{grid};
    }
    else {
        splice( @$list, 1, 0, $self->__header_sep( $w_cols ) ) if $self->{grid};
    }
    if ( $self->{info_row} ) {
        if ( print_columns( $self->{info_row} ) > $table_w ) {
            push @$list, cut_to_printwidth( $self->{info_row}, $table_w - 3 ) . '...';
        }
        else {
            push @$list, $self->{info_row};
        }
    }
    my $prompt = join( "\n", @header );
    my $old_row = 0;
    my $auto_jumped_to_first_row = 2;
    my $row_is_expanded = 0;

    while ( 1 ) {
        if ( term_width() != $term_w ) {
            $term_w = term_width();
            $self->__recursive_code();
            return;
        }
        if ( ( $self->{keep_header} && ! @$list ) || ( ! $self->{keep_header} && @$list == 1 ) ) {
            push @$list, '';
        }
        $ENV{TC_RESET_AUTO_UP} = 0;
        my $row = choose(
            $list,
            { prompt => $prompt, index => 1, default => $old_row, ll => $table_w, layout => 3,
              clear_screen => 1, mouse => $self->{mouse}, hide_cursor => 0,
              color => $self->{color}, codepage_mapping => $self->{codepage_mapping} }
        );
        if ( ! defined $row ) {
            return;
        }
        elsif ( $row < 0 ) { # -1 -2
            next;
        }
        if ( ! $self->{table_expand} ) {
            return if $row == 0;
            next;
        }
        else {
            if ( $old_row == $row ) {
                if ( $row == 0 ) {
                    if ( ! $self->{keep_header} ) {
                        return;
                    }
                    elsif ( $self->{table_expand} == 1 ) {
                        return if $row_is_expanded;
                        return if $auto_jumped_to_first_row == 1;
                    }
                    elsif ( $self->{table_expand} == 2 ) {
                        return if $row_is_expanded;
                    }
                    $auto_jumped_to_first_row = 0;
                }
                elsif ( $ENV{TC_RESET_AUTO_UP} ) {
                    $auto_jumped_to_first_row = 0;
                }
                else {
                    $old_row = 0;
                    $auto_jumped_to_first_row = 1;
                    $row_is_expanded = 0;
                    next;
                }
            }
            $old_row = $row;
            $row_is_expanded = 1;
            if ( $self->{info_row} && $row == $#$list ) {
                choose(
                    [ 'Close' ],
                    { prompt => $self->{info_row}, clear_screen => 1, mouse => $self->{mouse}, hide_cursor => 0 }
                );
                next;
            }
            if ( $self->{keep_header} ) {
                $row++;
            }
            else {
                if ( $self->{grid} ) {
                    next   if $row == 1;
                    $row-- if $row > 1;
                }
            }
            $self->__print_single_row( $row, $self->{longest_col_name} + 1 );
        }
        delete $ENV{TC_RESET_AUTO_UP};
    }
}


sub __copy_table {
    my ( $self ) = @_;
    my ( $type, $total, $next_update, $count );                                 #
    if ( $self->{progress_status} ) {                                           #
        ( $type, $total, $next_update, $count ) = @{$self->{progress_status}};  #
        $self->{progress}->init(                                                #
            $type eq 'multi' ? { name => 'Computing: (3) ' }                    #
                             : { so_far => $count }                             #
        );                                                                      #
    }                                                                           #
    for my $row ( @{$self->{orig_table}}[@{$self->{row_idxs}}] ) {
        my $tmp = [];
        for ( @{$row}[@{$self->{orig_col_idxs}}] ) {
            my $str = $_;
            $str = $self->{undef}            if ! defined $str;
            $str = _handle_reference( $str ) if ref $str;
            if ( $self->{squash_spaces} ) {
                $str =~ s/^\p{Space}+//;
                $str =~ s/\p{Space}+\z//;
                $str =~ s/\p{Space}+/ /g;
            }
            if ( $self->{color} ) {
                $str =~ s/\x{feff}//g;
                $str =~ s/\e\[[\d;]*m/\x{feff}/msg;
            }
            if ( $self->{binary_filter} && substr( $str, 0, 100 ) =~ /[\x00-\x08\x0B-\x0C\x0E-\x1F]/ ) {
                $str = $self->{binary_string};
            }
            $str =~ s/\t/ /g;
            $str =~ s/[\x{000a}-\x{000d}\x{0085}\x{2028}\x{2029}]+/\ \ /g;
            $str =~ s/[\p{Cc}\p{Noncharacter_Code_Point}\p{Cs}]//g;
            push @$tmp, $str;
        }
        push @{$self->{table_copy}}, $tmp;
        if ( $self->{progress_status} ) {                                       #
            if ( $count >= $next_update ) {                                     #
                $next_update = $self->{progress}->update( $count );             #
            }                                                                   #
            ++$count;                                                           #
        }                                                                       #
    }
    if ( $self->{progress_status} ) {                                           #
        if ( $type eq 'single' ) {                                              #
            $self->{progress_status}[2] = $next_update;                         #
            $self->{progress_status}[3] = $count;                               #
        }                                                                       #
        elsif ( $total >= $next_update ) {                                      #
            $self->{progress}->update( $total );                                #
        }                                                                       #
    }
}


sub __calc_col_width {
    my ( $self ) = @_;
    my ( $type, $total, $next_update, $count );                                 #
    if ( $self->{progress_status} ) {                                           #
        ( $type, $total, $next_update, $count ) = @{$self->{progress_status}};  #
        $self->{progress}->init(                                                #
            $type eq 'multi' ? { name => 'Computing: (2) ' }                    #
                             : { so_far => $count }                             #
        );                                                                      #
    }                                                                           #
    $self->{longest_col_name} = 0;
    $self->{w_cols} = [ ( 1 ) x @{$self->{table_copy}[0]} ];
    my $normal_row = 0;
    my @col_idx = ( 0 .. $#{$self->{table_copy}[0]} );

    for my $row ( @{$self->{table_copy}}[@{$self->{row_idxs}}] ) {
        for my $i ( @col_idx ) {
            my $width = print_columns( $row->[$i] );
            if ( $normal_row ) {
                if ( $width > $self->{w_cols}[$i] ) {
                    $self->{w_cols}[$i] = $width;
                }
                if ( $row->[$i] && ! looks_like_number $row->[$i] ) {
                    ++$self->{not_a_number}[$i];
                }
            }
            else {
                # col name
                $self->{w_head}[$i] = $width;
                if ( $width > $self->{longest_col_name} ) {
                    $self->{longest_col_name} = $width;
                }
                if ( $i == $#$row ) {
                    $normal_row = 1;
                }
            }
        }
        if ( $self->{progress_status} ) {                                       #
            if ( $count >= $next_update ) {                                     #
                $next_update = $self->{progress}->update( $count );             #
            }                                                                   #
            ++$count;                                                           #
        }                                                                       #
    }
    if ( $self->{progress_status} ) {                                           #
        if ( $type eq 'single' ) {                                              #
            $self->{progress_status}[2] = $next_update;                         #
            $self->{progress_status}[3] = $count;                               #
        }                                                                       #
        elsif ( $total >= $next_update ) {                                      #
            $self->{progress}->update( $total );                                #
        }                                                                       #
    }                                                                           #
}


sub __calc_avail_col_width {
    my ( $self, $term_w ) = @_;
    my $w_head = [ @{$self->{w_head}} ];
    my $w_cols = [ @{$self->{w_cols}} ];
    my $avail_w = $term_w - $self->{tab_w} * $#$w_cols;
    my $sum = sum( @$w_cols );
    if ( $sum < $avail_w ) {
        # auto cut
        HEAD: while ( 1 ) {
            my $count = 0;
            for my $i ( 0 .. $#$w_head ) {
                if ( $w_head->[$i] > $w_cols->[$i] ) {
                    ++$w_cols->[$i];
                    ++$count;
                    last HEAD if ( $sum + $count ) == $avail_w;
                }
            }
            last HEAD if $count == 0;
            $sum += $count;
        }
        return $w_cols;
    }
    elsif ( $sum > $avail_w ) {
        my $min_width = $self->{min_col_width} || 1;
        if ( @$w_head > $avail_w ) {
            $self->__print_term_not_wide_enough_message();
            return;
        }
        my @w_cols_tmp = @$w_cols;
        my $percent = 0;

        MIN: while ( $sum > $avail_w ) {
            ++$percent;
            my $count = 0;
            for my $i ( 0 .. $#w_cols_tmp ) {
                if ( $min_width >= $w_cols_tmp[$i] ) {
                    next;
                }
                if ( $min_width >= _minus_x_percent( $w_cols_tmp[$i], $percent ) ) {
                    $w_cols_tmp[$i] = $min_width;
                }
                else {
                    $w_cols_tmp[$i] = _minus_x_percent( $w_cols_tmp[$i], $percent );
                }
                ++$count;
            }
            $sum = sum( @w_cols_tmp );
            $min_width-- if $count == 0;
            #last MIN if $min_width == 0;
        }
        my $rest = $avail_w - $sum;
        if ( $rest ) {

            REST: while ( 1 ) {
                my $count = 0;
                for my $i ( 0 .. $#w_cols_tmp ) {
                    if ( $w_cols_tmp[$i] < $w_cols->[$i] ) {
                        $w_cols_tmp[$i]++;
                        $rest--;
                        $count++;
                        last REST if $rest == 0;
                    }
                }
                last REST if $count == 0;
            }
        }
        $w_cols = [ @w_cols_tmp ] if @w_cols_tmp;
    }
    return $w_cols;
}


sub __cols_to_string {
    my ( $self, $w_cols ) = @_;
    my ( $type, $total, $next_update, $count );                                 #
    if ( $self->{progress_status} ) {                                           #
        ( $type, $total, $next_update, $count ) = @{$self->{progress_status}};  #
        $self->{progress}->init(                                                #
            $type eq 'multi' ? { name => 'Computing: (1) ' }                    #
                             : { so_far => $count }                             #
        );                                                                      #
    }                                                                           #
    my $tab;
    if ( $self->{grid} ) {
        $tab = ( ' ' x int( $self->{tab_w} / 2 ) ) . '|' . ( ' ' x int( $self->{tab_w} / 2 ) );
    }
    else {
        $tab = ' ' x $self->{tab_w};
    }
    for my $row ( @{$self->{row_idxs}} ) {
        my $str = '';
        for my $col ( 0 .. $#$w_cols ) {
            $str .= unicode_sprintf(
                $self->{table_copy}[$row][$col],
                $w_cols->[$col],
                $self->{not_a_number}[$col] ? 0 : 1
            );
            if ( $self->{color} && defined $self->{orig_table}[$row][$col] ) { ##
                my @color = $self->{orig_table}[$row][$col] =~ /(\e\[[\d;]*m)/msg;
                $str =~ s/\x{feff}/shift @color/ge;
                $str .= $color[-1] if @color;
            }
            $str .= $tab if $col != $#$w_cols;
        }
        $str .= RESET if $self->{color};
        $self->{table_copy}[$row] = $str;   # overwrite table_copy to save memory
        if ( $self->{progress_status} ) {                                       #
            if ( $count >= $next_update ) {                                     #
                $next_update = $self->{progress}->update( $count );             #
            }                                                                   #
            ++$count;                                                           #
        }                                                                       #
    }
    if ( $self->{progress_status} && $total >= $next_update ) {                 #
        $self->{progress}->update( $total );                                    #
    }                                                                           #
    return $self->{table_copy}; # now $list
}



sub __choose_columns {
    my ( $self, $avail_cols ) = @_;
    my $col_idxs = [];
    my $ok = '-ok-';
    my @pre = ( undef, $ok );
    my $init_prompt = 'Columns: ';
    my $s_tab = print_columns( $init_prompt );
    my @cols = map { defined $_ ? $_ : '<UNDEF>' } @$avail_cols;

    while ( 1 ) {
        my @chosen_cols = @$col_idxs ?  @cols[@$col_idxs] : '*';
        my $prompt = $init_prompt . join( ', ', @chosen_cols );
        my $choices = [ @pre, @cols ];
        my @idx = choose(
            $choices,
            { prompt => $prompt, lf => [ 0, $s_tab ], clear_screen => 1, undef => '<<', meta_items => [ 0 .. $#pre ],
              index => 1, mouse => $self->{mouse}, include_highlighted => 2, hide_cursor => 0 }
        );
        if ( ! @idx || $idx[0] == 0 ) {
            if ( @$col_idxs ) {
                $col_idxs = [];
                next;
            }
            return;
        }
        elsif ( defined $choices->[$idx[0]] && $choices->[$idx[0]] eq $ok ) {
            shift @idx;
            push @$col_idxs, map { $_ -= @pre; $_ } @idx;
            return $col_idxs;
        }
        push @$col_idxs, map { $_ -= @pre; $_ } @idx;
    }
}


sub __header_sep {
    my ( $self, $w_cols ) = @_;
    my $tab = ( '-' x int( $self->{tab_w} / 2 ) ) . '|' . ( '-' x int( $self->{tab_w} / 2 ) );
    my $header_sep = '';
    for my $i ( 0 .. $#$w_cols ) {
        $header_sep .= '-' x $w_cols->[$i];
        $header_sep .= $tab if $i != $#$w_cols;
    }
    return $header_sep;
}


sub _handle_reference {
    require Data::Dumper;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Maxdepth = 2;
    return 'ref: ' . Data::Dumper::Dumper( $_[0] );
}


sub __print_term_not_wide_enough_message {
    my ( $self ) = @_;
    my $prompt_1 = 'To many columns - terminal window is not wide enough.';
    choose(
        [ 'Press ENTER to show the column names.' ],
        { prompt => $prompt_1, clear_screen => 1, mouse => $self->{mouse}, hide_cursor => 0 }
    );
    my $prompt_2 = 'Column names (close with ENTER).';
    choose(
        $self->{table_copy}[0],
        { prompt => $prompt_2, clear_screen => 1, mouse => $self->{mouse}, hide_cursor => 0 }
    );
}


sub _minus_x_percent {
    my ( $value, $percent ) = @_;
    my $new = int( $value - ( $value / 100 * $percent ) );
    return $new > 0 ? $new : 1;
}








1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Term::TablePrint - Print a table to the terminal and browse it interactively.

=head1 VERSION

Version 0.101

=cut

=head1 SYNOPSIS

    my $table = [ [ 'id', 'name' ],
                  [    1, 'Ruth' ],
                  [    2, 'John' ],
                  [    3, 'Mark' ],
                  [    4, 'Nena' ], ];

    use Term::TablePrint qw( print_table );

    print_table( $table );

    # or OO style:

    use Term::TablePrint;

    my $pt = Term::TablePrint->new();
    $pt->print_table( $table );

=head1 DESCRIPTION

C<print_table> shows a table and lets the user interactively browse it. It provides a cursor which highlights the row
on which it is located. The user can scroll through the table with the different cursor keys - see L</KEYS>.

If the table has more rows than the terminal, the table is divided up on as many pages as needed automatically. If the
cursor reaches the end of a page, the next page is shown automatically until the last page is reached. Also if the
cursor reaches the topmost line, the previous page is shown automatically if it is not already the first one.

If the terminal is too narrow to print the table, the columns are adjusted to the available width automatically.

If the option table_expand is enabled and a row is selected with Return, each column of that row is output in its own
line preceded by the column name. This might be useful if the columns were cut due to the too low terminal width.

The following modifications are made (at a copy of the original data) to the table elements before the output.

Tab characters (C<\t>) are replaces with a space.

Vertical spaces C<\v>) are squashed to two spaces

Control characters, code points of the surrogate ranges and non-characters are removed.

If the option I<squash_spaces> is enabled leading and trailing spaces are removed from the array elements and spaces
are squashed to a single space.

The elements in a column are right-justified if one or more elements of that column do not look like a number, else they
are left-justified.

=head1 METHODS

=head2 new

The C<new> method returns a C<Term::TablePrint> object. As an argument it can be passed a reference to a hash which
holds the options - the available options are listed in L</OPTIONS>.

    my $tp = Term::TablePrint->new( [ \%options ] );

=head2 print_table

The C<print_table> method prints the table passed with the first argument.

    $tp->print_table( $array_ref, [ \%options ] );

The first argument is a reference to an array of arrays. The first array of these arrays holds the column names. The
following arrays are the table rows where the elements are the field values.

As a second and optional argument a hash reference can be passed which holds the options - the available options are
listed in L</OPTIONS>.

=head1 SUBROUTINES

=head2 print_table

The C<print_table> subroutine prints the table passed with the first argument.

    print_table( $array_ref, [ \%options ] );

The subroutine C<print_table> takes the same arguments as the method L</print_table>.

=head1 USAGE

=head2 KEYS

Keys to move around:

=over

=item *

the C<ArrowDown> key (or the C<j> key) to move down and  the C<ArrowUp> key (or the C<k> key) to move up.

=item *

the C<PageUp> key (or C<Ctrl-B>) to go back one page, the C<PageDown> key (or C<Ctrl-F>) to go forward one page.

=item *

the C<Insert> key to go back 25 pages, the C<Delete> key to go forward 25 pages.

=item *

the C<Home> key (or C<Ctrl-A>) to jump to the first row of the table, the C<End> key (or C<Ctrl-E>) to jump to the last
row of the table.

=back

With I<keep_header> disabled the C<Return> key closes the table if the cursor is on the header row.

If I<keep_header> is enabled and I<table_expand> is set to C<0>, the C<Return> key closes the table if the cursor is on
the first row.

If I<keep_header> and I<table_expand> are enabled and the cursor is on the first row, pressing C<Return> three times in
succession closes the table. If I<table_expand> is set to C<1> and the cursor is auto-jumped to the first row, it is
required only one C<Return> to close the table.

If the cursor is not on the first row:

=over

=item *

with the option I<table_expand> disabled the cursor jumps to the table head if C<Return> is pressed.

=item *

with the option I<table_expand> enabled each column of the selected row is output in its own line preceded by the
column name if C<Return> is pressed. Another C<Return> closes this output and goes back to the table output. If a row is
selected twice in succession, the pointer jumps to the head of the table or to the first row if I<keep_header> is
enabled.

=back

If the size of the window is changed, the screen is rewritten as soon as the user presses a key.

If the option I<choose_columns> is enabled, the C<SpaceBar> key (or the right mouse key) can be used to select columns -
see option L</choose_columns>.

=head2 OPTIONS

Defaults may change in a future release.

=head3 prompt

String displayed above the table.

=head3 binary_filter

If I<binary_filter> is set to 1, "BNRY" is printed instead of arbitrary binary data.

If the data matches the repexp C</[\x00-\x08\x0B-\x0C\x0E-\x1F]/>, it is considered arbitrary binary data.

Printing arbitrary binary data could break the output.

Default: 0

=head3 choose_columns

If I<choose_columns> is set to 1, the user can choose which columns to print. Columns can be added (with the
C<SpaceBar> and the C<Return> key) until the user confirms with the I<-ok-> menu entry.

Default: 0

=head3 codepage_mapping

This option has only meaning if the operating system is MSWin32 and the option I<color> is enabled.

By setting this option to C<1> one can enable the codepage mapping offered by L<Win32::Console::ANSI>.

0 - disable automatic codepage mapping

1 - keep automatic codepage mapping

Default: 0

=head3 color

Setting this option to C<1> enables the support for color and text formatting escape sequences.

If the OS is MSWin32 and this option is enabled, C<Term::Choose> loads L<Win32::Console::ANSI>. C<Win32::Console::ANSI>
emulates an ANSI console. See also the option L</codepage_mapping>.

Default: 0

=head3 grid

If enabled, columns are separated from each other with lines and the header row is separated with a line from the rest
of the table.

Default: 0

=head3 keep_header

If I<keep_header> is set to 1, the table header is shown on top of each page.

If I<keep_header> is set to 0, the table header is shown on top of the first page.

Default: 1

=head3 squash_spaces

If I<squash_spaces> is enabled, consecutive spaces are squashed to one space and leading and trailing spaces are
removed.

Default: 0

=head3 max_rows

Set the maximum number of used table rows. The used table rows are kept in memory.

To disable the automatic limit set I<max_rows> to 0.

If the number of table rows is equal to or higher than I<max_rows>, the last row of the output tells that the limit has
been reached.

Default: 200_000

=head3 min_col_width

The columns with a width below or equal I<min_col_width> are only trimmed if it is still required to lower the row width
despite all columns wider than I<min_col_width> have been trimmed to I<min_col_width>.

Default: 30

=head3 mouse

Set the I<mouse> mode (see option C<mouse> in L<Term::Choose/OPTIONS>).

Default: 0

=head3 progress_bar

Set the progress bar threshold. If the number of fields (rows x columns) is higher than the threshold, a progress bar is
shown while preparing the data for the output.

Default: 40_000

=head3 tab_width

Set the number of spaces between columns.

Default: 2

=head3 table_expand

If the option I<table_expand> is set to C<1> or C<2> and C<Return> is pressed, the selected table row is printed with
each column in its own line. Exception: if I<table_expand> is set to C<1> and the cursor auto-jumped to the first row,
the first row will not be expanded.

If I<table_expand> is set to 0, the cursor jumps to the to first row (if not already there) when C<Return> is pressed.

Default: 1

=head3 undef

Set the string that will be shown on the screen instead of an undefined field.

Default: "" (empty string)

=head1 ERROR HANDLING

C<print_table> dies

=over

=item

if an invalid number of arguments is passed.

=item

if an invalid argument is passed.

=item

if an unknown option name is passed.

=item

if an invalid option value is passed.

=back

=head1 REQUIREMENTS

=head2 Perl version

Requires Perl version 5.8.3 or greater.

=head2 Decoded strings

C<print_table> expects decoded strings.

=head2 Encoding layer for STDOUT

For a correct output it is required to set an encoding layer for C<STDOUT> matching the terminal's character set.

=head2 Monospaced font

It is required a terminal that uses a monospaced font which supports the printed characters.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::TablePrint

=head1 SEE ALSO

L<App::DBBrowser>

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright 2013-2018 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
