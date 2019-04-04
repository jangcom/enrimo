#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use autodie;
use feature        qw(say state);
use Cwd            qw(getcwd);
use Data::Dump     qw(dump);
use List::Util     qw(first shuffle);
use Carp           qw(croak);
use File::Basename qw(basename);
use DateTime;
use constant SCALAR => ref \$0;
use constant ARRAY  => ref [];
use constant HASH   => ref {};


our $VERSION = '1.05';
our $LAST    = '2019-04-04';
our $FIRST   = '2018-09-21';


#----------------------------------My::Toolset----------------------------------
sub show_front_matter {
    # """Display the front matter."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $prog_info_href = shift;
    croak "The 1st arg of [$sub_name] must be a hash ref!"
        unless ref $prog_info_href eq HASH;
    
    # Subroutine optional arguments
    my(
        $is_prog,
        $is_auth,
        $is_usage,
        $is_timestamp,
        $is_no_trailing_blkline,
        $is_no_newline,
        $is_copy,
    );
    my $lead_symb    = '';
    foreach (@_) {
        $is_prog                = 1  if /prog/i;
        $is_auth                = 1  if /auth/i;
        $is_usage               = 1  if /usage/i;
        $is_timestamp           = 1  if /timestamp/i;
        $is_no_trailing_blkline = 1  if /no_trailing_blkline/i;
        $is_no_newline          = 1  if /no_newline/i;
        $is_copy                = 1  if /copy/i;
        # A single non-alphanumeric character
        $lead_symb              = $_ if /^[^a-zA-Z0-9]$/;
    }
    my $newline = $is_no_newline ? "" : "\n";
    
    #
    # Fill in the front matter array.
    #
    my @fm;
    my $k = 0;
    my $border_len = $lead_symb ? 69 : 70;
    my %borders = (
        '+' => $lead_symb.('+' x $border_len).$newline,
        '*' => $lead_symb.('*' x $border_len).$newline,
    );
    
    # Top rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }
    
    # Program info, except the usage
    if ($is_prog) {
        $fm[$k++] = sprintf(
            "%s%s - %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{titl},
            $prog_info_href->{expl},
            $newline,
        );
        $fm[$k++] = sprintf(
            "%sVersion %s (%s)%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{vers},
            $prog_info_href->{date_last},
            $newline,
        );
    }
    
    # Timestamp
    if ($is_timestamp) {
        my %datetimes = construct_timestamps('-');
        $fm[$k++] = sprintf(
            "%sCurrent time: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $datetimes{ymdhms},
            $newline
        );
    }
    
    # Author info
    if ($is_auth) {
        $fm[$k++] = $lead_symb.$newline if $is_prog;
        $fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{auth}{$_},
            $newline
        ) for qw(name posi affi mail);
    }
    
    # Bottom rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }
    
    # Program usage: Leading symbols are not used.
    if ($is_usage) {
        $fm[$k++] = $newline if $is_prog or $is_auth;
        $fm[$k++] = $prog_info_href->{usage};
    }
    
    # Feed a blank line at the end of the front matter.
    if (not $is_no_trailing_blkline) {
        $fm[$k++] = $newline;
    }
    
    #
    # Print the front matter.
    #
    if ($is_copy) {
        return @fm;
    }
    else {
        print for @fm;
        return;
    }
}


sub validate_argv {
    # """Validate @ARGV against %cmd_opts."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $argv_aref     = shift;
    my $cmd_opts_href = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $argv_aref eq ARRAY;
    croak "The 2nd arg of [$sub_name] must be a hash ref!"
        unless ref $cmd_opts_href eq HASH;
    
    # For yn prompts
    my $the_prog = (caller(0))[1];
    my $yn;
    my $yn_msg = "    | Want to see the usage of $the_prog? [y/n]> ";
    
    #
    # Terminate the program if the number of required arguments passed
    # is not sufficient.
    #
    my $argv_req_num = shift; # (OPTIONAL) Number of required args
    if (defined $argv_req_num) {
        my $argv_req_num_passed = grep $_ !~ /-/, @$argv_aref;
        if ($argv_req_num_passed < $argv_req_num) {
            printf(
                "\n    | You have input %s nondash args,".
                " but we need %s nondash args.\n",
                $argv_req_num_passed,
                $argv_req_num,
            );
            print $yn_msg;
            while ($yn = <STDIN>) {
                system "perldoc $the_prog" if $yn =~ /\by\b/i;
                exit if $yn =~ /\b[yn]\b/i;
                print $yn_msg;
            }
        }
    }
    
    #
    # Count the number of correctly passed command-line options.
    #
    
    # Non-fnames
    my $num_corr_cmd_opts = 0;
    foreach my $arg (@$argv_aref) {
        foreach my $v (values %$cmd_opts_href) {
            if ($arg =~ /$v/i) {
                $num_corr_cmd_opts++;
                next;
            }
        }
    }
    
    # Fname-likes
    my $num_corr_fnames = 0;
    $num_corr_fnames = grep $_ !~ /^-/, @$argv_aref;
    $num_corr_cmd_opts += $num_corr_fnames;
    
    # Warn if "no" correct command-line options have been passed.
    if (not $num_corr_cmd_opts) {
        print "\n    | None of the command-line options was correct.\n";
        print $yn_msg;
        while ($yn = <STDIN>) {
            system "perldoc $the_prog" if $yn =~ /\by\b/i;
            exit if $yn =~ /\b[yn]\b/i;
            print $yn_msg;
        }
    }
    
    return;
}


sub reduce_data {
    # """Reduce data and generate reporting files."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $sets_href = shift;
    my $cols_href = shift;
    croak "The 1st arg of [$sub_name] must be a hash ref!"
        unless ref $sets_href eq HASH;
    croak "The 2nd arg of [$sub_name] must be a hash ref!"
        unless ref $cols_href eq HASH;
    
    #
    # Available formats
    # [1] dat
    #   - Plottable text file
    #   - Created by this routine's architecture
    # [2] tex
    #   - Wrapped in the LaTeX tabular environment
    #   - Created by this routine's architecture
    # [3] csv
    #   - Comma-separated values (sep char can however be changed)
    #   - Created by the Text::CSV module
    # [4] xlsx
    #   - MS Excel >2007
    #   - Created by the Excel::Writer::XLSX module "in binary"
    # [5] json
    #   - Arguably the most popular data interchange language
    #   - Created by the JSON module
    # [6] yaml
    #   - An increasingly popular data interchange language
    #   - Created by the YAML module
    #
    # Accordingly, the lines of code for
    # > [1] and [2] are almost the same.
    # > [3] and [4] are essentially their modules' interfaces.
    # > [5] and [6] are a simple chunk of their modules' data dumping commands.
    #
    
    #
    # Default attributes
    #
    my %flags = ( # Available data formats
        dat  => qr/^dat$/i,
        tex  => qr/^tex$/i,
        csv  => qr/^csv$/i,
        xlsx => qr/^xlsx$/i,
        json => qr/^json$/i,
        yaml => qr/^yaml$/i,
    );
    my %sets = (
        rpt_formats => ['dat', 'tex'],
        rpt_path    => "./",
        rpt_bname   => "rpt",
        begin_msg   => "generating data reduction reports...",
    );
    my %cols;
    my %rows;
    my %strs = ( # Not to be modified via the user arguments
        symbs    => {dat => "#",    tex => "%"   },
        eofs     => {dat => "#eof", tex => "%eof"},
        nan      => {
            dat  => "NaN",
            tex  => "{}",
            csv  => "",
            xlsx => "",
            json => "", # Not related to its 'null'
            yaml => "", # Not related to its '~'
        },
        newlines => {
            dat => "\n",
            tex => " \\\\\n",
            csv => "\n",
        },
        dataset_seps => {
            dat => "\n\n", # wrto gnuplot dataset structure
        },
        indents  => {dat => "", tex => "  "},
        rules    => {
            dat  => {}, # To be constructed
            tex  => {   # Commands of the booktabs package
                top => "\\toprule",
                mid => "\\midrule",
                bot => "\\bottomrule",
            },
            xlsx => {   # Border indices (not borders)
                # Refer to the following URL for the border indices:
                # https://metacpan.org/pod/Excel::Writer::XLSX#set_border()
                none    => 0,
                top     => 2,
                mid     => 2,
                bot     => 2,
                mid_bot => 2, # For single-rowed data
            },
        },
    );
    # Override the attributes of %sets and %cols for given keys.
    # (CAUTION: Not the whole hashes!)
    $sets{$_} = $sets_href->{$_} for keys %$sets_href;
    $cols{$_} = $cols_href->{$_} for keys %$cols_href;
    
    #
    # Data format validation
    #
    @{$sets{rpt_formats}} = (keys %flags)
        if first { /all/i } @{$sets{rpt_formats}}; # 'all' format
    foreach my $rpt_format (@{$sets{rpt_formats}}) {
        next if (first { $rpt_format =~ $_ } values %flags);
        croak "[$sub_name]: [$rpt_format]".
              " is not a valid element of rpt_formats.\n".
              "Available formats are: ".
              join(", ", sort keys %flags)."\n";
    }
    
    #
    # Column size validation
    #
    croak "[$sub_name]: Column size must be provided via the size key."
        unless defined $cols{size};
    croak "[$sub_name]: Column size must be a positive integer."
        if $cols{size} <= 0 or $cols{size} =~ /[.]/;
    foreach (qw(heads subheads data_arr_ref)) {
        unless (@{$cols{$_}} % $cols{size} == 0) {
            croak
                "[$sub_name]\nColumn size [$_] is found to be".
                " [".@{$cols{$_}}."].\n".
                "It must be [$cols{size}] or its integer multiple!";
        }
    }
    
    #
    # Create some default key-val pairs.
    #
    # > Needless to say, a hash ref argument, if given, replaces
    #   an original hash ref. If some key-val pairs were assigned
    #   in the "Default attributes" section at the beginning of
    #   this routine but were not specified by the user arguments,
    #   those pairs would be lost:
    #   Original: space_bef => {dat => " ", tex => " "}
    #   User-arg: space_bef => {dat => " "}
    #   Defined:  space_bef => {dat => " "}
    #   The tex => " " pair would not be available hereafter.
    # > To avoid such loss, default key-val pairs are defined
    #   altogether below.
    # > This also allows the TeX separators, which must be
    #   the ampersand (&), immutable. That is, even if the following
    #   arguments are passed, the TeX separators will remain unchanged:
    #   User-arg: heads_sep => {dat => "|", csv => ";", tex => "|"}
    #             data_sep  => {dat => " ", csv => ";", tex => " "}
    #   Defined:  heads_sep => {dat => "|", csv => ";", tex => "&"}
    #             data_sep  => {dat => " ", csv => ";", tex => "&"}
    # > Finally, the headings separators for DAT and TeX are
    #   enclosed with the designated space characters.
    #   (i.e. space_bef and space_aft)
    # > CSV separators can be set via the user arguments,
    #   as its module defines such a method,
    #   but are not surrounded by any space characters.
    # > XLSX, as written in binaries, has nothing to do here.
    #
    
    # dat
    $cols{space_bef}{dat} = " " unless exists $cols{space_bef}{dat};
    $cols{heads_sep}{dat} = "|" unless exists $cols{heads_sep}{dat};
    $cols{space_aft}{dat} = " " unless exists $cols{space_aft}{dat};
    $cols{data_sep}{dat}  = " " unless exists $cols{data_sep}{dat};
    # TeX
    $cols{space_bef}{tex} = " " unless exists $cols{space_bef}{tex};
    $cols{heads_sep}{tex} = "&"; # Immutable
    $cols{space_aft}{tex} = " " unless exists $cols{space_aft}{tex};
    $cols{data_sep}{tex}  = "&"; # Immutable
    # DAT, TeX
    foreach (qw(dat tex)) {
        next if $cols{heads_sep}{$_} =~ /\t/; # Don't add spaces around a tab.
        $cols{heads_sep}{$_} =
            $cols{space_bef}{$_}.$cols{heads_sep}{$_}.$cols{space_aft}{$_};
    }
    # CSV
    $cols{heads_sep}{csv} = "," unless exists $cols{heads_sep}{csv};
    $cols{data_sep}{csv}  = "," unless exists $cols{data_sep}{csv};
    #+++++debugging+++++#
#    dump(\%cols);
#    pause_shell();
    #+++++++++++++++++++#
    
    #
    # Convert the data array into a "rowwise" columnar structure.
    #
    my $i = 0;
    for (my $j=0; $j<=$#{$cols{data_arr_ref}}; $j++) {
        push @{$cols{data_rowwise}[$i]}, $cols{data_arr_ref}[$j];
        #+++++debugging+++++#
#        say "At [\$i: $i] and [\$j: $j]: the modulus is: ",
#            ($j + 1) % $cols{size};
        #+++++++++++++++++++#
        $i++ if ($j + 1) % $cols{size} == 0;
    }
    
    #
    # Define row and column indices to be used for iteration controls.
    #
    $rows{idx_last}     = $#{$cols{data_rowwise}};
    $cols{idx_multiple} = $cols{size} - 1;
    
    # Obtain columnar data sums.
    if (defined $cols{sum_idx_multiples}) {
        for (my $i=0; $i<=$rows{idx_last}; $i++) {
            for (my $j=0; $j<=$cols{idx_multiple}; $j++) {
                    if (first { $j == $_ } @{$cols{sum_idx_multiples}}) {
                        $cols{data_sums}[$j] +=
                            $cols{data_rowwise}[$i][$j] // 0;
                }
            }
        }
    }
    #+++++debugging+++++#
#    dump(\%cols);
#    pause_shell();
    #+++++++++++++++++++#
    
    #
    # Notify the beginning of the routine.
    #
    say "\n#".('=' x 69);
    say "#"." [$sub_name] $sets{begin_msg}";
    say "#".('=' x 69);
    
    #
    # Multiplex outputting
    # IO::Tee intentionally not used for avoiding its additional installation
    #
    
    # Define filehandle refs and corresponding filenames.
    my($dat_fh, $tex_fh, $csv_fh, $xlsx_fh);
    my %rpt_formats = (
        dat  => {fh => $dat_fh,  fname => $sets{rpt_bname}.".dat" },
        tex  => {fh => $tex_fh,  fname => $sets{rpt_bname}.".tex" },
        csv  => {fh => $csv_fh,  fname => $sets{rpt_bname}.".csv" },
        xlsx => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".xlsx"},
        json => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".json"},
        yaml => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".yaml"},
    );
    
    # Multiple invocations of the writing routine
    my $cwd = getcwd();
    mkdir $sets{rpt_path} if not -e $sets{rpt_path};
    chdir $sets{rpt_path};
    foreach (@{$sets{rpt_formats}}) {
        open $rpt_formats{$_}{fh}, '>:encoding(UTF-8)', $rpt_formats{$_}{fname};
        reduce_data_writing_part(
            $rpt_formats{$_}{fh},
            $_, # Flag
            \%flags,
            \%sets,
            \%strs,
            \%cols,
            \%rows,
        );
        say "[$sets{rpt_path}/$rpt_formats{$_}{fname}] generated.";
    }
    chdir $cwd;
    
    #
    # The writing routine (nested)
    #
    sub reduce_data_writing_part {
        my $_fh    = $_[0];
        my $_flag  = $_[1];
        my %_flags = %{$_[2]};
        my %_sets  = %{$_[3]};
        my %_strs  = %{$_[4]};
        my %_cols  = %{$_[5]};
        my %_rows  = %{$_[6]};
        
        #
        # [CSV][XLSX] Load modules and instantiate classes.
        #
        
        # [CSV]
        my $csv;
        if ($_flag =~ $_flags{csv}) {
            require Text::CSV; # vendor lib || cpanm
            $csv = Text::CSV->new( { binary => 1 } )
                or die "Cannot instantiate Text::CSV! ".Text::CSV->error_diag();
            
            $csv->eol($_strs{newlines}{$_flag});
        }
        
        # [XLSX]
        my($workbook, $worksheet, %xlsx_formats);
        my($xlsx_row, $xlsx_col, $xlsx_col_init, $xlsx_col_scale_factor);
        $xlsx_row                  = 1;   # Starting row number
        $xlsx_col = $xlsx_col_init = 1;   # Starting col number
        $xlsx_col_scale_factor     = 1.2; # Empirically determined
        if ($_flag =~ $_flags{xlsx}) {
            require Excel::Writer::XLSX; # vendor lib || cpanm
            binmode($_fh); # fh can now be R/W in binary as well as in text
            $workbook = Excel::Writer::XLSX->new($_fh);
            
            # Define the worksheet name using the bare filename of the report.
            # If the bare filename contains a character that is invalid
            # as an Excel worksheet name or lengthier than 32 characters,
            # the default worksheet name is used (i.e. Sheet1).
            eval {
                $worksheet = $workbook->add_worksheet(
                    (split /\/|\\/, $_sets{rpt_bname})[-1]
                )
            };
            $worksheet = $workbook->add_worksheet() if $@;
            
            # As of Excel::Writer::XLSX v0.98, a format property
            # can be added in the middle, but cannot be overridden.
            # The author of this routine therefore uses cellwise formats
            # to specify "ruled" and "aligned" cells.
            foreach my $rule (keys %{$_strs{rules}{$_flag}}) {
                foreach my $align (qw(none left right)) {
                    $xlsx_formats{$rule}{$align}= $workbook->add_format(
                        top    => $rule =~ /top|mid/i ?
                            $_strs{rules}{$_flag}{$rule} : 0,
                        bottom => $rule =~ /bot/i ?
                            $_strs{rules}{$_flag}{$rule} : 0,
                        align  => $align,
                    );
                }
            }
            #+++++debugging+++++#
#            dump(\%xlsx_formats);
#            pause_shell();
            #+++++++++++++++++++#
            
            # Panes freezing
            # Added on 2018-11-23
            if ($_cols{freeze_panes}) {
                $worksheet->freeze_panes(
                    ref $_cols{freeze_panes} eq HASH ?
                        ($_cols{freeze_panes}{row}, $_cols{freeze_panes}{col}) :
                        $_cols{freeze_panes}
                );
            }
        }
        
        #
        # Data construction
        #
        
        # [DAT] Prepend comment symbols to the first headings.
        if ($_flag =~ $_flags{dat}) {
            $_cols{heads}[0]    = $_strs{symbs}{$_flag}." ".$_cols{heads}[0];
            $_cols{subheads}[0] = $_strs{symbs}{$_flag}." ".$_cols{subheads}[0];
        }
        if ($_flag !~ $_flags{dat}) { # Make it unaffected by the prev dat call
            $_cols{heads}[0]    =~ s/^[^\w] //;
            $_cols{subheads}[0] =~ s/^[^\w] //;
        }
        
        #
        # Define widths for columnar alignment.
        # (1) Take the lengthier one between headings and subheadings.
        # (2) Take the lengthier one between (1) and the data.
        # (3) Take the lengthier one between (2) and the data sum.
        #
        
        # (1)
        for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
            $_cols{widths}[$j] =
                length($_cols{heads}[$j]) > length($_cols{subheads}[$j]) ?
                length($_cols{heads}[$j]) : length($_cols{subheads}[$j]);
        }
        # (2)
        for (my $i=0; $i<=$_rows{idx_last}; $i++) {
            for (my $j=0; $j<=$#{$_cols{widths}}; $j++) {
                $_cols{widths}[$j] =
                    length($_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag})
                    > $_cols{widths}[$j] ?
                    length($_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag})
                    : $_cols{widths}[$j];
            }
        }
        # (3)
        if (defined $_cols{sum_idx_multiples}) {
            foreach my $j (@{$_cols{sum_idx_multiples}}) {
                $_cols{widths}[$j] =
                    length($_cols{data_sums}[$j]) > $_cols{widths}[$j] ?
                    length($_cols{data_sums}[$j]) : $_cols{widths}[$j];
            }
        }
        
        #
        # [DAT] Border construction
        #
        if ($_flag =~ $_flags{dat}) {
            $_cols{border_widths}[0] = 0;
            $_cols{border_widths}[1] = 0;
            for (my $j=0; $j<=$#{$_cols{widths}}; $j++) {
                # Border width 1: Rules
                $_cols{border_widths}[0] += (
                    $_cols{widths}[$j] + length($_cols{heads_sep}{$_flag})
                );
                # Border width 2: Data sums label
                if (defined $_cols{sum_idx_multiples}) {
                    if ($j < $_cols{sum_idx_multiples}[0]) {
                        $_cols{border_widths}[1] += (
                                     $_cols{widths}[$j]
                            + length($_cols{heads_sep}{$_flag})
                        );
                    }
                }
            }
            $_cols{border_widths}[0] -=
                (
                      length($_strs{symbs}{$_flag})
                    + length($_cols{space_aft}{$_flag})
                );
            $_cols{border_widths}[1] -=
                (
                      length($_strs{symbs}{$_flag})
                    + length($_cols{space_aft}{$_flag})
                );
            $_strs{rules}{$_flag}{top} =
            $_strs{rules}{$_flag}{mid} =
            $_strs{rules}{$_flag}{bot} =
                $_strs{symbs}{$_flag}.('-' x $_cols{border_widths}[0]);
        }
        
        #
        # Begin writing.
        # [JSON][YAML]: Via their dumping commands.
        # [DAT][TeX]:   Via the output filehandle.
        # [CSV][XLSX]:  Via their output methods.
        #
        
        # [JSON][YAML][DAT][TeX] Change the output filehandle from STDOUT.
        select($_fh);
        
        #
        # [JSON][YAML] Load modules and dump the data.
        #
        
        # [JSON]
        if ($_flag =~ $_flags{json}) {
            use JSON; # vendor lib || cpanm
            print to_json(\%_cols, { pretty => 1 });
        }
        
        # [YAML]
        if ($_flag =~ $_flags{yaml}) {
            use YAML; # vendor lib || cpanm
            print Dump(\%_cols);
        }
        
        # [DAT][TeX] OPTIONAL blocks
        if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
            # Prepend the program information, if given.
            if ($_sets{prog_info}) {
                show_front_matter(
                    $_sets{prog_info},
                    'prog',
                    'auth',
                    'timestamp',
                    ($_strs{symbs}{$_flag} // $_strs{symbs}{dat}),
                );
            }
            
            # Prepend comments, if given.
            if ($_sets{cmt_arr}) {
                if (@{$_sets{cmt_arr}}) {
                    say $_strs{symbs}{$_flag}.$_ for @{$_sets{cmt_arr}};
                    print "\n";
                }
            }
        }
        
        # [TeX] Wrapping up - begin
        if ($_flag =~ $_flags{tex}) {
            # Document class
            say "\\documentclass{article}";
            
            # Package loading with kind notice
            say "%";
            say "% (1) The \...rule commands are defined by".
                " the booktabs package.";
            say "% (2) If an underscore character is included as text,";
            say "%     you may want to use the underscore package.";
            say "%";
            say "\\usepackage{booktabs,underscore}";
            
            # document env - begin
            print "\n";
            say "\\begin{document}";
            print "\n";
            
            # tabular env - begin
            print "\\begin{tabular}{";
            for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
                print(
                    (first { $j == $_ } @{$_cols{ragged_left_idx_multiples}}) ?
                        "r" : "l"
                );
            }
            print "}\n";
        }
        
        # [DAT][TeX] Top rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{top}, "\n"
            if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        #
        # Headings and subheadings
        #
        
        # [DAT][TeX]
        for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
            if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                print $_strs{indents}{$_flag} if $j == 0;
                $_cols{conv} = '%-'.$_cols{widths}[$j].'s';
                if ($_cols{heads_sep}{$_flag} !~ /\t/) {
                    printf(
                        "$_cols{conv}%s",
                        $_cols{heads}[$j],
                        $j == $#{$_cols{heads}} ? '' : $_cols{heads_sep}{$_flag}
                    );
                }
                elsif ($_cols{heads_sep}{$_flag} =~ /\t/) {
                    printf(
                        "%s%s",
                        $_cols{heads}[$j],
                        $j == $#{$_cols{heads}} ? '' : $_cols{heads_sep}{$_flag}
                    );
                }
                print $_strs{newlines}{$_flag} if $j == $#{$_cols{heads}};
            }
        }
        for (my $j=0; $j<=$#{$_cols{subheads}}; $j++) {
            if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                print $_strs{indents}{$_flag} if $j == 0;
                $_cols{conv} = '%-'.$_cols{widths}[$j].'s';
                if ($_cols{heads_sep}{$_flag} !~ /\t/) {
                    printf(
                        "$_cols{conv}%s",
                        $_cols{subheads}[$j],
                        $j == $#{$_cols{subheads}} ?
                            '' : $_cols{heads_sep}{$_flag}
                    );
                }
                elsif ($_cols{heads_sep}{$_flag} =~ /\t/) {
                    printf(
                        "%s%s",
                        $_cols{subheads}[$j],
                        $j == $#{$_cols{subheads}} ?
                            '' : $_cols{heads_sep}{$_flag}
                    );
                }
                print $_strs{newlines}{$_flag} if $j == $#{$_cols{subheads}};
            }
        }
        
        # [CSV][XLSX]
        if ($_flag =~ $_flags{csv}) {
            $csv->sep_char($_cols{heads_sep}{$_flag});
            $csv->print($_fh, $_cols{heads});
            $csv->print($_fh, $_cols{subheads});
        }
        if ($_flag =~ $_flags{xlsx}) {
            $worksheet->write_row(
                $xlsx_row++,
                $xlsx_col,
                $_cols{heads},
                $xlsx_formats{top}{none} # top rule formatted
            );
            $worksheet->write_row(
                $xlsx_row++,
                $xlsx_col,
                $_cols{subheads},
                $xlsx_formats{none}{none}
            );
        }
        
        # [DAT][TeX] Middle rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{mid}, "\n"
            if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        #
        # Data
        #
        # > [XLSX] is now handled together with [DAT][TeX]
        #   to allow columnwise alignment. That is, the write() method
        #   is used instead of the write_row() one.
        # > Although MS Excel by default aligns numbers ragged left,
        #   the author wanted to provide this routine with more flexibility.
        # > According to the Excel::Writer::XLSX manual,
        #   AutoFit can only be performed from within Excel.
        #   By the use of write(), however, pseudo-AutoFit is also realized:
        #   The author has created this routine initially for gnuplot-plottable
        #   text file and TeX tabular data, and for them he added an automatic
        #   conversion creation functionality. Utilizing the conversion width,
        #   approximate AutoFit can be performed.
        #   To see how it works, look up:
        #     - 'Define widths for columnar alignment.' and the resulting
        #       values of $_cols{widths}
        #     - $xlsx_col_scale_factor
        #
        for (my $i=0; $i<=$_rows{idx_last}; $i++) {
            # [CSV]
            if ($_flag =~ $_flags{csv}) {
                $csv->sep_char($_cols{data_sep}{$_flag});
                $csv->print(
                    $_fh,
                    $_cols{data_rowwise}[$i] // $_strs{nan}{$_flag}
                );
            }
            # [DAT] Dataset separator
            # > Optional
            # > If designated, gnuplot dataset separator, namely a pair of
            #   blank lines, is inserted before beginning the next dataset.
            if (
                $_flag =~ $_flags{dat} and
                $_sets{num_rows_per_dataset} and # Make this loop optional.
                $i != 0 and                      # Skip the first row.
                $i % $_sets{num_rows_per_dataset} == 0
            ) {
                print $_strs{dataset_seps}{$_flag};
            }
            # [DAT][TeX][XLSX]
            $xlsx_col = $xlsx_col_init;
            for (my $j=0; $j<=$_cols{idx_multiple}; $j++) {
                # [DAT][TeX]
                if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                    # Conversion (i): "Ragged right"
                    # > Default
                    # > length($_cols{space_bef}{$_flag})
                    #   is "included" in the conversion.
                    $_cols{conv} =
                        '%-'.
                        (
                                     $_cols{widths}[$j] 
                            + length($_cols{space_bef}{$_flag})
                        ).
                        's';
                    
                    # Conversion (ii): "Ragged left"
                    # > length($_cols{space_bef}{$_flag})
                    #   is "appended" to the conversion.
                    if (first { $j == $_ } @{$_cols{ragged_left_idx_multiples}})
                    {
                        $_cols{conv} =
                            '%'.
                            $_cols{widths}[$j].
                            's'.
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : ' ' x length($_cols{space_bef}{$_flag})
                            );
                    }
                    
                    # Columns
                    print $_strs{indents}{$_flag} if $j == 0;
                    if ($_cols{data_sep}{$_flag} !~ /\t/) {
                        printf(
                            "%s$_cols{conv}%s",
                            ($j == 0 ? '' : $_cols{space_aft}{$_flag}),
                            $_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    elsif ($_cols{data_sep}{$_flag} =~ /\t/) {
                        printf(
                            "%s%s",
                            $_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    print $_strs{newlines}{$_flag}
                        if $j == $_cols{idx_multiple};
                }
                # [XLSX]
                if ($_flag =~ $_flags{xlsx}) {
                    # Pseudo-AutoFit
                    $worksheet->set_column(
                        $xlsx_col,
                        $xlsx_col,
                        $_cols{widths}[$j] * $xlsx_col_scale_factor
                    );
                    
                    my $_align = (
                        first { $j == $_ } @{$_cols{ragged_left_idx_multiples}}
                    ) ? 'right' : 'left';
                    $worksheet->write(
                        $xlsx_row,
                        $xlsx_col,
                        $_cols{data_rowwise}[$i][$j] // $_strs{nan}{$_flag},
                        ($i == 0 and $i == $_rows{idx_last}) ?
                            $xlsx_formats{mid_bot}{$_align} : # For single-rowed
                        $i == 0 ?
                            $xlsx_formats{mid}{$_align} : # mid rule formatted
                        $i == $_rows{idx_last} ?
                            $xlsx_formats{bot}{$_align} : # bot rule formatted
                            $xlsx_formats{none}{$_align}  # Default: no rule
                    );
                    $xlsx_col++;
                    $xlsx_row++ if $j == $_cols{idx_multiple};
                }
            }
        }
        
        # [DAT][TeX] Bottom rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{bot}, "\n"
            if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        #
        # Append the data sums.
        #
        if (defined $_cols{sum_idx_multiples}) {
            #
            # [DAT] Columns "up to" the beginning of the data sums
            #
            if ($_flag =~ $_flags{dat}) {
                my $sum_lab         = "Sum: ";
                my $sum_lab_aligned = sprintf(
                    "%s%s%s%s",
                    $_strs{indents}{$_flag},
                    $_strs{symbs}{$_flag},
                    ' ' x ($_cols{border_widths}[1] - length($sum_lab)),
                    $sum_lab
                );
                print $sum_lab_aligned;
            }
            
            #
            # Columns "for" the data sums
            #
            
            # [DAT][TeX][XLSX]
            my $the_beginning = $_flag !~ $_flags{dat} ?
                0 : $_cols{sum_idx_multiples}[0];
            $xlsx_col = $xlsx_col_init;
            for (my $j=$the_beginning; $j<=$_cols{sum_idx_multiples}[-1]; $j++)
            {
                # [DAT][TeX]
                if ($_flag =~ /$_flags{dat}|$_flags{tex}/) {
                    # Conversion (i): "Ragged right"
                    # > Default
                    # > length($_cols{space_bef}{$_flag})
                    #   is "included" in the conversion.
                    $_cols{conv} =
                        '%-'.
                        (
                                     $_cols{widths}[$j] 
                            + length($_cols{space_bef}{$_flag})
                        ).
                        's';
                    
                    # Conversion (ii): "Ragged left"
                    # > length($_cols{space_bef}{$_flag})
                    #   is "appended" to the conversion.
                    if (first { $j == $_ } @{$_cols{ragged_left_idx_multiples}})
                    {
                        $_cols{conv} =
                            '%'.
                            $_cols{widths}[$j].
                            's'.
                            (
                                $j == $_cols{idx_multiple} ?
                                    '' : ' ' x length($_cols{space_bef}{$_flag})
                            );
                    }
                    
                    # Columns
                    print $_strs{indents}{$_flag} if $j == 0;
                    if ($_cols{data_sep}{$_flag} !~ /\t/) {
                        printf(
                            "%s$_cols{conv}%s",
                            ($j == 0 ? '' : $_cols{space_bef}{$_flag}),
                            $_cols{data_sums}[$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{sum_idx_multiples}[-1] ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    elsif ($_cols{data_sep}{$_flag} =~ /\t/) {
                        printf(
                            "%s%s",
                            $_cols{data_sums}[$j] // $_strs{nan}{$_flag},
                            (
                                $j == $_cols{sum_idx_multiples}[-1] ?
                                    '' : $_cols{data_sep}{$_flag}
                            )
                        );
                    }
                    print $_strs{newlines}{$_flag}
                        if $j == $_cols{sum_idx_multiples}[-1];
                }
                # [XLSX]
                if ($_flag =~ $_flags{xlsx}) {
                    my $_align = (
                        first { $j == $_ } @{$_cols{ragged_left_idx_multiples}}
                    ) ? 'right' : 'left';
                    
                    $worksheet->write(
                        $xlsx_row,
                        $xlsx_col,
                        $_cols{data_sums}[$j] // $_strs{nan}{$_flag},
                        $xlsx_formats{none}{$_align}
                    );
                    
                    $xlsx_col++;
                    $xlsx_row++ if $j == $_cols{sum_idx_multiples}[-1];
                }
            }
            
            # [CSV]
            if ($_flag =~ $_flags{csv}) {
                $csv->print(
                    $_fh,
                    $_cols{data_sums} // $_strs{nan}{$_flag}
                );
            }
        }
        
        # [TeX] Wrapping up - end
        if ($_flag =~ $_flags{tex}) {
            # tabular env - end
            say '\\end{tabular}';
            
            # document env - end
            print "\n";
            say "\\end{document}";
        }
        
        # [DAT][TeX] EOF
        print $_strs{eofs}{$_flag} if $_flag =~ /$_flags{dat}|$_flags{tex}/;
        
        # [JSON][YAML][DAT][TeX] Restore the output filehandle to STDOUT.
        select(STDOUT);
        
        # Close the filehandle.
        # the XLSX filehandle must be closed via its close method!
        close $_fh         if $_flag !~ $_flags{xlsx};
        $workbook->close() if $_flag =~ $_flags{xlsx};
    }
    
    return;
}


sub show_elapsed_real_time {
    # """Show the elapsed real time."""
    
    my @opts = @_ if @_;
    
    # Parse optional arguments.
    my $is_return_copy = 0;
    my @del; # Garbage can
    foreach (@opts) {
        if (/copy/i) {
            $is_return_copy = 1;
            # Discard the 'copy' string to exclude it from
            # the optional strings that are to be printed.
            push @del, $_;
        }
    }
    my %dels = map { $_ => 1 } @del;
    @opts = grep !$dels{$_}, @opts;
    
    # Optional strings printing
    print for @opts;
    
    # Elapsed real time printing
    my $elapsed_real_time = sprintf("Elapsed real time: [%s s]", time - $^T);
    
    # Return values
    if ($is_return_copy) {
        return $elapsed_real_time;
    }
    else {
        say $elapsed_real_time;
        return;
    }
}


sub pause_shell {
    # """Pause the shell."""
    
    my $notif = $_[0] ? $_[0] : "Press enter to exit...";
    
    print $notif;
    while (<STDIN>) { last; }
    
    return;
}


sub construct_timestamps {
    # """Construct timestamps."""
    
    # Optional setting for the date component separator
    my $date_sep  = '';
    
    # Terminate the program if the argument passed
    # is not allowed to be a delimiter.
    my @delims = ('-', '_');
    if ($_[0]) {
        $date_sep = $_[0];
        my $is_correct_delim = grep $date_sep eq $_, @delims;
        croak "The date delimiter must be one of: [".join(', ', @delims)."]"
            unless $is_correct_delim;
    }
    
    # Construct and return a datetime hash.
    my $dt  = DateTime->now(time_zone => 'local');
    my $ymd = $dt->ymd($date_sep);
    my $hms = $dt->hms($date_sep ? ':' : '');
    (my $hm = $hms) =~ s/[0-9]{2}$//;
    
    my %datetimes = (
        none   => '', # Used for timestamp suppressing
        ymd    => $ymd,
        hms    => $hms,
        hm     => $hm,
        ymdhms => sprintf("%s%s%s", $ymd, ($date_sep ? ' ' : '_'), $hms),
        ymdhm  => sprintf("%s%s%s", $ymd, ($date_sep ? ' ' : '_'), $hm),
    );
    
    return %datetimes;
}


sub construct_range {
    # """Construct a range for both a list of decimals
    # and a list of integers."""
    my $sub_name = join('::', (caller(0))[0, 3]);
    
    my $range_aref = shift;
    my $line_sref  = shift;
    
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $range_aref eq ARRAY;
    
    my $line;
    if ($line_sref and $$line_sref) {
        croak "The 2nd arg of [$sub_name] must be a scalar ref!"
            unless ref $line_sref eq SCALAR;
    }
    
    #
    # Terminate the program if more than one decimal point
    # has been passed for a single number.
    #
    foreach (@$range_aref) {
        if (/[.]{2,}/) {
            print $$line_sref ? "=> [$$line_sref]" : "";
            croak "More than one decimal point! Terminating";
        }
    }
    
    #
    # Check if the given list of numbers contains a decimal.
    # This affects many of the following statements.
    #
    my @num_of_decimals = grep /[.]/, @$range_aref;
    
    #
    # Pad "integer" 0 to the omitted for correct range construction.
    #
    if (@num_of_decimals) {
        foreach (@$range_aref) {
            s/(^[.][0-9]+)/0$1/ if /^[.][0-9]+/;
        }
    }
    
    #
    # Populate min, max, (and optionally) incre.
    # (Dependent on whether a decimal is involved)
    #
    my $range_num_input = @$range_aref;
    my($min, $incre, $max);
    
    if ($range_num_input == 3) {
        ($min, $incre, $max) = @$range_aref;
        #
        # Terminate the program if $max is zero.
        #
        if (not $max) {
            print $$line_sref ? "=> [$$line_sref]" : "";
            croak "The max entry must be \"nonzero\"! Terminating";
        }
        
        # Hooks to jump to the next conditional: For empty and zero $incre
        $incre = -1 if (
            not $incre               # For empty and 0
            or $incre =~ /^0{2,}$/   # For 00, 000, ...
            or $incre =~ /^0+[.]0+$/ # For 0.0, 0.00, 00.0, 00.00, ...
            or $incre =~ /^0+[.]$/   # For 0., 00., ...
                                     #  .0,  .00, ... were already converted to
                                     # 0.0, 0.00, ... at the "Pad integer 0".
        );
    }
    if ($range_num_input == 2 or $incre == -1) {
        ($min, $max) = @$range_aref[0, -1]; # Slicing for empty $incre
        
        # Define the increment.
        # (i)  For decimals, the longest decimal places are used.
        #      e.g. 0.1,  0.20 --> Increment: 0.01
        #           0.05, 0.2  --> Increment: 0.01
        #           0.3,  0.5  --> Increment: 0.1
        # (ii) For integers, the increment is 1.
        if (@num_of_decimals) {
            my $power_of_ten;
            my $power_of_ten_largest = 0;
            
            foreach (@$range_aref) {
                $power_of_ten = index((reverse $_), '.');
                $power_of_ten_largest = $power_of_ten > $power_of_ten_largest ?
                    $power_of_ten : $power_of_ten_largest;
            }
            $incre = 10**-$power_of_ten_largest;
        }
        elsif (not @num_of_decimals) {
            $incre = 1;
        }
    }
    unless ($range_num_input == 3 or $range_num_input == 2) {
        print $$line_sref ? "=> [$$line_sref]" : "";
        croak "We need 2 or 3 numbers to construct a range! Terminating";
    }
    
    #
    # Terminate the program if the number passed as the min
    # is bigger than the number passed as the max.
    #
    if ($min > $max) {
        print $$line_sref ? "=> [$$line_sref]" : "";
        croak "$min is bigger than $max! Terminating";
    }
    
    #
    # Find the lengthiest number to construct a convert.
    # (Dependent on whether a decimal is involved)
    #
    my $lengthiest = '';
    foreach (@$range_aref) {
        # If a decimal is contained, compare only the decimal places.
        s/[0-9]+[.]([0-9]+)/$1/ if @num_of_decimals;
        
        $lengthiest = $_ if length($_) > length($lengthiest);
    }
    
    #
    # Construct a zero-padded convert (in case the ranged numbers
    # are used as part of filenames).
    #
    my $conv = @num_of_decimals ? '%.'.length($lengthiest).'f' :
                                  '%0'.length($lengthiest).'d';
    
    #
    # Construct a range.
    #
    # > If a decimal is involved, increase the powers of 10 of the list of
    #   numbers by a equal factor such that the decimal with the largest decimal
    #   places becomes an integer.
    #   e.g. 0.10,0.001,0.11 => 100, 1, 110
    # > Also, make sure that the number becomes an integer.
    #   Just multiplying the power of 10 does not make the float
    #   an integer.
    # > The powers of 10 of the list of numbers will then be decreased
    #   to the original ones after range construction by a C-like for loop.
    #   This is done because floating numbers cannot be correctly compared.
    #
    if (@num_of_decimals) {
        foreach ($min, $incre, $max) {
            $_ *= 10**length($lengthiest);
            $_ = int $_;
        }
    }
    
    @$range_aref = (); # Empty the range array ref before its refilling.
    for (my $i=$min; $i<=$max; $i+=$incre) {
        push @$range_aref, sprintf(
            "$conv",
            (
                @num_of_decimals ?
                    $i / 10**length($lengthiest):
                    $i
            )
        );
    }
    
    return;
}
#-------------------------------------------------------------------------------


#----------------------------------My::Nuclear----------------------------------
sub calc_consti_elem_wgt_avg_molar_masses {
    # """Calculate the weighted-average molar masses of
    # the constituent elements of a material."""
    
    my(                  # e.g.
        $mat_href,       # \%moo3
        $weighting_frac, # 'amt_frac'
        $is_verbose      # 1 (boolean)
    ) = @_;
    
    # e.g. ('mo', 'o')
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        # Redirect the hash of the constituent element for clearer coding.
        my $elem_href = $mat_href->{$elem_str}{href}; # e.g. \%mo, \%o
        
        if ($is_verbose) {
            say "\n".("=" x 70);
            printf(
                "[%s]\n".
                "calculating the weighted-average molar mass of [%s]\n".
                "using [%s] as the weighting factor...\n",
                join('::', (caller(0))[3]),
                $elem_href->{label},
                $weighting_frac,
            );
            say "=" x 70;
        }
        
        #
        # Calculate the weighted-average molar mass of a constituent element
        # by adding up the "weighted" molar masses of its isotopes.
        #
        
        # Initializations
        #        $mo{wgt_avg_molar_mass}
        #         $o{wgt_avg_molar_mass}
        $elem_href->{wgt_avg_molar_mass} = 0; # Used for (i) and (ii) below
        #        $mo{mass_frac_sum}
        #         $o{mass_frac_sum}
        $elem_href->{mass_frac_sum} = 0; # Used for (ii) below
        
        # (i) Weight by amount fraction: Weighted "arithmetic" mean
        if ($weighting_frac eq 'amt_frac') {
            # e.g. ('92', '94', ... '100') for $elem_href == \%mo
            foreach my $mass_num (@{$elem_href->{mass_nums}}) {
                # (1) Weight the molar mass of an isotope by $weighting_frac.
                #     => Weight by "multiplication"
                #              $mo{100}{wgt_molar_mass}
                $elem_href->{$mass_num}{wgt_molar_mass} =
                    #              $mo{100}{amt_frac}
                    $elem_href->{$mass_num}{$weighting_frac}
                    #                $mo{100}{molar_mass}
                    * $elem_href->{$mass_num}{molar_mass};
                
                # (2) Cumulative sum of the weighted molar masses of
                #     the isotopes, which will in turn become the
                #     weighted-average molar mass of the constituent element.
                #        $mo{wgt_avg_molar_mass}
                $elem_href->{wgt_avg_molar_mass} +=
                    #              $mo{100}{wgt_molar_mass}
                    $elem_href->{$mass_num}{wgt_molar_mass};
                
                # No further step :)
            }
        }
        
        # (ii) Weight by mass fraction: Weighted "harmonic" mean
        elsif ($weighting_frac eq 'mass_frac') {
            foreach my $mass_num (@{$elem_href->{mass_nums}}) {
                # (1) Weight the molar mass of an isotope by $weighting_frac.
                #     => Weight by "division"
                $elem_href->{$mass_num}{wgt_molar_mass} =
                    $elem_href->{$mass_num}{$weighting_frac}
                    / $elem_href->{$mass_num}{molar_mass};
                
                # (2) Cumulative sum of the weighted molar masses of
                #     the isotopes
                #     => Will be the denominator in (4).
                $elem_href->{wgt_avg_molar_mass} +=
                    $elem_href->{$mass_num}{wgt_molar_mass};
                
                # (3) Cumulative sum of the mass fractions of the isotopes
                #     => Will be the numerator in (4).
                #     => The final value of the cumulative sum
                #        should be 1 in principle.
                $elem_href->{mass_frac_sum} +=
                    $elem_href->{$mass_num}{$weighting_frac};
            }
            # (4) Evaluate the fraction.
            $elem_href->{wgt_avg_molar_mass} =
                $elem_href->{mass_frac_sum} # Should be 1 in principle.
                / $elem_href->{wgt_avg_molar_mass};
        }
        
        else {
            croak "\n\n[$weighting_frac] ".
                  "is not an available weighting factor; terminating.\n";
        }
        
        if ($is_verbose) {
            dump($elem_href);
            pause_shell("Press enter to continue...");
        }
    }
    
    return;
}


sub convert_fracs {
    # """Convert the amount fractions of nuclides to mass fractions,
    # or vice versa."""
    
    my(              # e.g.
        $mat_href,   # \%moo3
        $conv_mode,  # 'amt_to_mass'
        $is_verbose, # 1 (boolean)
    ) = @_;
    
    # e.g. ['mo', 'o']
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        # Redirect the hash of the constituent element for clearer coding.
        my $elem_href = $mat_href->{$elem_str}{href}; # e.g. \%mo, \%o
        
        if ($is_verbose) {
            say "\n".("=" x 70);
            printf(
                "[%s]\n".
                "converting the fractional quantities of [%s] as [%s]...\n",
                join('::', (caller(0))[3]),
                $elem_href->{label},
                $conv_mode,
            );
            say "=" x 70;
        }
        
        # (i) Amount to mass fractions
        if ($conv_mode eq 'amt_to_mass') {
            foreach my $mass_num (@{$elem_href->{mass_nums}}) {
                $elem_href->{$mass_num}{mass_frac} =
                    $elem_href->{$mass_num}{amt_frac}
                    * $elem_href->{$mass_num}{molar_mass}
                    / $elem_href->{wgt_avg_molar_mass};
            }
        }
        
        # (ii) Mass to amount fractions
        elsif ($conv_mode eq 'mass_to_amt') {
            foreach my $mass_num (@{$elem_href->{mass_nums}}) {
                $elem_href->{$mass_num}{amt_frac} =
                    $elem_href->{$mass_num}{mass_frac}
                    * $elem_href->{wgt_avg_molar_mass}
                    / $elem_href->{$mass_num}{molar_mass};
            }
        }
        
        if ($is_verbose) {
            dump($elem_href);
            pause_shell("Press enter to continue...");
        }
    }
    
    return;
}


sub enrich_or_deplete {
    # """Redistribute the enrichment levels of nuclides with respect to
    # the enrichment level of the nuclide to be enriched/depleted."""
    
    my(                       # e.g.
        $enri_nucl_elem_href, # \%mo
        $enri_nucl_mass_num,  # '100'
        $enri_lev,            # 0.9739 (the goal enrichment level)
        $enri_lev_type,       # 'amt_frac'
        $depl_order,          # 'ascend'
        $is_verbose,          # 1 (boolean)
    ) = @_;
    my(
        $to_be_absorbed,      # Enri level for arithmetic operations
        $to_be_absorbed_goal, # Enri level to be given to the nuclide of int
        $donatable,           # Donatable enri level
        $remainder,           # New enri level of $to_be_absorbed
    );
    $to_be_absorbed      =
    $to_be_absorbed_goal = # Will be further modified after the loop run
        $enri_lev
        - $enri_nucl_elem_href->{$enri_nucl_mass_num}{$enri_lev_type};
    my $old_enri_lev; # Printing purposes only
    
    #
    # - If the goal enrichment level of the nuclide of interest is
    #   lower than its minimum depletion level, exit and return '1'
    #   that will in turn be used as a signal "not" to accumulate data.
    # - This separate hook is necessary because the nuclide of interest
    #   is handled separately after the loop run.
    #
    if (
        $enri_lev
        < $enri_nucl_elem_href->{$enri_nucl_mass_num}{min_depl_lev}
    ) {
        printf(
            "[%s %s: %s] is lower than".
            " its minimum depletion level [%s]. Skipping.\n",
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{label},
            $enri_lev_type,
            $enri_lev,
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{min_depl_lev},
        );
        return 1; # Which will in turn become an exit hook for enri()
    }
    
    #
    # Show the nuclide of interest and its planned enrichment level change.
    #
    if ($is_verbose) {
        say "\n".("=" x 70);
        printf(
            "[%s]\n".
            "redistributing the enrichment levels of [%s isotopes]...\n\n",
            join('::', (caller(0))[3]),
            $enri_nucl_elem_href->{label},
        );
        printf(
            "%-19s: [%s]\n".
            "%-19s: [%s]\n".
            "%-19s: [%f] --> [%f]\n",
            'Nuclide of interest',
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{label},
            '$enri_lev_type',
            $enri_lev_type,
            "Goal $enri_lev_type",
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{$enri_lev_type},
            $enri_lev,
        );
        printf(
            "%-19s: [%f]\n",
            '$to_be_absorbed',
            $to_be_absorbed,
        );
        say "=" x 70;
    }
    
    #
    # Collect enrichment levels from the nuclides other than the nuclide
    # of interest. The collected (donated) enrichment levels will then be
    # added to the nuclide of interest after the loop run.
    #
    # Memorandum:
    #   DO NOT exit this loop (but you can skip an iteration for a nuclide,
    #   for example when a nuclide has no more donatable enrichment level),
    #   otherwise all of the remaining nuclides will be skipped and thereby
    #   incorrect arithmetics will result. For example, the nuclide of interest
    #   may not be given the to-be-donated enrichment levels,
    #   even if that to-be-donated enrichment levels have already been
    #   subtracted from the previously iterated nuclides.
    #
    
    # Take out the nuclide of interest (to be enriched or depleted) from
    # the nuclides list. The nuclide of interest will be handled separately
    # after the loop run.
    my @mass_nums_wo_enri_nucl =
        grep !/$enri_nucl_mass_num/, @{$enri_nucl_elem_href->{mass_nums}};
    
    # Determine the order of nuclide depletion.
    if ($depl_order =~ /asc(end)?/i) {
        @mass_nums_wo_enri_nucl = sort { $a <=> $b } @mass_nums_wo_enri_nucl;
    }
    elsif ($depl_order =~ /desc(end)?/i) {
        @mass_nums_wo_enri_nucl = sort { $b <=> $a } @mass_nums_wo_enri_nucl;
    }
    elsif ($depl_order =~ /rand(om)?|shuffle/i) {
        @mass_nums_wo_enri_nucl = shuffle @mass_nums_wo_enri_nucl;
    }
    
    foreach my $mass_num (@mass_nums_wo_enri_nucl) {
        # (b-d) of the arithmetics below
        $donatable =
            $enri_nucl_elem_href->{$mass_num}{$enri_lev_type}
            - $enri_nucl_elem_href->{$mass_num}{min_depl_lev};
        
        # Show the current nuclide.
        if ($is_verbose) {
            say "-" x 70;
            printf(
                "%-22s: [%s]\n",
                'Nuclide',
                $enri_nucl_elem_href->{$mass_num}{label},
            );
            printf(
                "%-22s: [%s]\n",
                $enri_lev_type,
                $enri_nucl_elem_href->{$mass_num}{$enri_lev_type},
            );
            printf(
                "%-22s: [%s]\n",
                'Min depletion level',
                $enri_nucl_elem_href->{$mass_num}{min_depl_lev},
            );
            printf(
                "%-22s: [%s]\n",
                'Donatable',
                $donatable,
            );
            say "-" x 70;
        }
        
        #
        # Arithmetics for the nuclides other than the nuclide of interest
        # (whose enrichment levels are to be extracted)
        #
        # (i)  b -= a ... (a < 0), where (b > d) is boolean true
        # (ii) skip   ... (b = d)
        #   Note: b < d is not specifically examined. This is because b < d
        #   holds only when the predefined enrichment level of the nuclide
        #   is smaller than the later-set minimum depletion level.
        #   As both the (iii) and (iv) conditionals require b > d,
        #   the state of b < d works only for the (i) conditional above.
        #   (an nuclide of b < d cannot be depleted, but can be enriched)
        # (iii) c = a-(b-d) ... (b > d "and" a >= b-d)
        # (iv)  c = (b-d)-a ... (b > d "and" b-d > a "and" a != 0)
        # where
        # c
        #   - $remainder
        #   - The one that will be the value of $to_be_absorbed or 'a'
        #     at the next nuclide
        #   - Greater than or equal to 0
        # a
        #   - $to_be_absorbed
        #   - The amount of enrichment level to be transferred
        #     from the current nuclide to the nuclide of interest
        # b
        #   - $enri_nucl_elem_href->{$mass_num}{$enri_lev_type}
        #   - The current enrichment level of a nuclide
        # d
        #   - $enri_nucl_elem_href->{$mass_num}{min_depl_lev}
        #   - The minimum depletion level
        #
        
        # Remember the enrichment level of a nuclide
        # before its redistribution, for printing purposes.
        $old_enri_lev = $enri_nucl_elem_href->{$mass_num}{$enri_lev_type};
        
        # (i) b -= a ... (a < 0) where (b > d) is boolean true
        if ($to_be_absorbed < 0) {
            # Reporting (1/2)
            if ($is_verbose) {
                printf(
                    "%-14s: [%f]\n",
                    'To be absorbed',
                    $to_be_absorbed,
                );
            }
            
            # b -= a
            $enri_nucl_elem_href->{$mass_num}{$enri_lev_type} -=
                $to_be_absorbed;
            
            # a = 0
            $to_be_absorbed = 0;
            
            # Reporting (2/2)
            if ($is_verbose) {
                printf(
                    "%-14s: [%f]\n",
                    "Donatable",
                    $donatable,
                );
                printf(
                    "%-14s: [%f] --> [%f]\n",
                    "$enri_lev_type",
                    $old_enri_lev,
                    $enri_nucl_elem_href->{$mass_num}{$enri_lev_type},
                );
                printf(
                    "%-14s: [%f]\n",
                    'Remainder',
                    $to_be_absorbed,
                );
                print "\n";
            }
            
            # next must be used not to enter into the conditionals below.
            next;
        }
        
        # (ii) skip ... (b = d)
        # b = d means that no more enrichment level is available.
        if (not $donatable) {
            print "No more donatable [$enri_lev_type].\n\n" if $is_verbose;
            next;
        }
        
        # (iii) c = a-(b-d) ... (b > d "and" a >= b-d)
        if (
            $to_be_absorbed >= $donatable
            and (
                $enri_nucl_elem_href->{$mass_num}{$enri_lev_type}
                > $enri_nucl_elem_href->{$mass_num}{min_depl_lev}
            )
        ) {
            # Reporting (1/2)
            if ($is_verbose) {
                printf(
                    "%-14s: [%f]\n",
                    'To be absorbed',
                    $to_be_absorbed,
                );
            }
            
            # c = a-(b-d)
            $remainder = $to_be_absorbed - $donatable;
            
            # b = d
            $enri_nucl_elem_href->{$mass_num}{$enri_lev_type} =
                $enri_nucl_elem_href->{$mass_num}{min_depl_lev};
            
            # a = c
            $to_be_absorbed = $remainder;
            
            # Reporting (2/2)
            if ($is_verbose) {
                printf(
                    "%-14s: [%f]\n",
                    "Donatable",
                    $donatable,
                );
                printf(
                    "%-14s: [%f] --> [%f]\n",
                    "$enri_lev_type",
                    $old_enri_lev,
                    $enri_nucl_elem_href->{$mass_num}{$enri_lev_type},
                );
                printf(
                    "%-14s: [%f]\n",
                    'Remainder',
                    $to_be_absorbed,
                );
                print "\n";
            }
        }
        
        # (iv) c = (b-d)-a ... (b > d "and" b-d > a "and" a != 0)
        elsif (
            $donatable > $to_be_absorbed
            and (
                $enri_nucl_elem_href->{$mass_num}{$enri_lev_type}
                > $enri_nucl_elem_href->{$mass_num}{min_depl_lev}
            )
            # To prevent unnecessary zero addition and subtraction
            and $to_be_absorbed
        ) {
            if ($is_verbose) {
                printf(
                    "The nuclide has a larger enrichment level, [%f],\n".
                    "than the enrichment level to be absorbed,  [%f].\n".
                    "Hence, we now absorb [%f] from [%f].\n",
                    $enri_nucl_elem_href->{$mass_num}{$enri_lev_type},
                    $to_be_absorbed,
                    $to_be_absorbed,
                    $enri_nucl_elem_href->{$mass_num}{$enri_lev_type},
                );
            }
            # c = b-a
            $remainder =
                $enri_nucl_elem_href->{$mass_num}{$enri_lev_type}
                - $to_be_absorbed;
            
            # b = c
            $enri_nucl_elem_href->{$mass_num}{$enri_lev_type} = $remainder;
            
            # a = 0, meaning that no enrichment level
            # is left to be transferred.
            $to_be_absorbed = 0;
            
            # Reporting
            if ($is_verbose) {
                printf(
                    "%-14s: [%f] --> [%f]\n",
                    "$enri_lev_type",
                    $old_enri_lev,
                    $enri_nucl_elem_href->{$mass_num}{$enri_lev_type},
                );
                printf(
                    "%-14s: [%f]\n",
                    'To be absorbed',
                    $to_be_absorbed,
                );
                print "\n";
            }
        }
    }
    
    #
    # Provide the nuclide of interest with the actual total donated 
    # enrichment level, which is ($to_be_absorbed_goal - $to_be_absorbed
    # remaining after the loop run). For example:
    # > $to_be_absorbed_goal = 0.9021
    # > $to_be_absorbed remaining after the loop = 0.0025
    #   which resulted from the minimum depletion levels of
    #   the nuclides other than the nuclide of interest.
    # > Therefore, 0.9021 - 0.0025 = 0.8996 will be the actual total donated
    #   enrichment level.
    #
    $old_enri_lev = $enri_nucl_elem_href->{$enri_nucl_mass_num}{$enri_lev_type};
    if ($is_verbose) {
        say "-" x 70;
        printf(
            "%-22s: [%s]\n",
            'Nuclide',
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{label},
        );
        printf(
            "%-22s: [%s]\n",
            $enri_lev_type,
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{$enri_lev_type},
        );
        printf(
            "%-22s: [%s]\n",
            'Min depletion level',
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{min_depl_lev},
        );
        say "-" x 70;
        
        # Goal change of the enrichment level of the nuclide of interest
        printf(
            "%s: [%f] --> [%f]\n",
            "Goal $enri_lev_type",
            $old_enri_lev,
            $enri_lev,
        );
    }
    
    # The actual total donated enrichment level
    $to_be_absorbed_goal -= $to_be_absorbed;
    
    # Assign the actual total donated enrichment level
    # to the nuclide of interest.
    $enri_nucl_elem_href->{$enri_nucl_mass_num}{$enri_lev_type} +=
        $to_be_absorbed_goal;
    
    if ($is_verbose) {
        # Actual change of the enrichment level of the nuclide of interest
        printf(
            "%s: [%f] --> [%f]\n",
            "Actual $enri_lev_type",
            $old_enri_lev,
            $enri_nucl_elem_href->{$enri_nucl_mass_num}{$enri_lev_type},
        );
        
        # Notice if $to_be_absorbed is nonzero.
        if ($to_be_absorbed) {
            printf(
                "%s [%f] could not be collected".
                " because of the minimum depletion levels:\n",
                $enri_lev_type,
                $to_be_absorbed,
            );
            foreach my $mass_num (@{$enri_nucl_elem_href->{mass_nums}}) {
                next if $mass_num == $enri_nucl_mass_num;
                printf(
                    "[%s min_depl_lev] => [%f]\n",
                    $enri_nucl_elem_href->{$mass_num}{label},
                    $enri_nucl_elem_href->{$mass_num}{min_depl_lev},
                );
            }
            print "\n";
        }
    }
    
    pause_shell("Press enter to continue...") if $is_verbose;
    return;
}


sub calc_mat_molar_mass_and_subcomp_mass_fracs_and_dccs {
    # """Calculate the molar mass of a material,
    # mass fractions and masses of its constituent elements,
    # masses of the isotopes, and density change coefficients."""
    
    my(                 # e.g.
        $mat_href,      # %\moo3
        $enri_lev_type, # 'amt_frac'
        $is_verbose,    # 1 (boolean)
        $run_mode,      # 'dcc_preproc'
    ) = @_;
    state $memorized = {}; # Memorize 'mass_frac_bef' for DCC calculation
    
    if ($is_verbose) {
        say "\n".("=" x 70);
        printf(
            "[%s]\n".
            "calculating the molar mass of [%s],\n".
            "mass fractions and masses of [%s], and\n".
            "masses and DCCs of the isotopes of [%s]...\n",
            join('::', (caller(0))[3]),
            $mat_href->{label},
            join(', ', @{$mat_href->{consti_elems}}),
            join(', ', @{$mat_href->{consti_elems}}),
        );
        say "=" x 70;
    }
    
    #
    # (1) Calculate the molar mass of the material,
    #     which depends on
    #   - the amounts of substance of the consistent elements:
    #     0 oxygen atom  for metallic Mo => Mo material mass == Mo mass
    #     2 oxygen atoms for MoO2        => Mo material mass >  Mo mass
    #     3 oxygen atoms for MoO3        => Mo material mass >> Mo mass
    #   - the weighted-average molar masses of the constituent elements,
    #     which are functions of their isotopic compositions, and
    #
    
    # Initialization
    $mat_href->{molar_mass} = 0;
    
    # $moo3{consti_elems} == ['mo', 'o']
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        #     $moo3{molar_mass}
        $mat_href->{molar_mass} +=
            #            $moo3{mo}{amt_subs}
            #             $moo3{o}{amt_subs}
            $mat_href->{$elem_str}{amt_subs}
            #                          $mo{wgt_avg_molar_mass}
            #                           $o{wgt_avg_molar_mass}
            * $mat_href->{$elem_str}{href}{wgt_avg_molar_mass};
    }
    
    #
    # (2) Using the molar mass of the material obtained in (1), calculate
    #     the mass fraction and the mass of the constituent elements.
    #
    
    # $moo3{consti_elems} = ['mo', 'o']
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        # (i) Mass fraction
        #            $moo3{mo}{mass_frac}
        #             $moo3{o}{mass_frac}
        $mat_href->{$elem_str}{mass_frac} =
            #            $moo3{mo}{amt_subs}
            #             $moo3{o}{amt_subs}
            $mat_href->{$elem_str}{amt_subs}
            #                          $mo{wgt_avg_molar_mass}
            #                           $o{wgt_avg_molar_mass}
            * $mat_href->{$elem_str}{href}{wgt_avg_molar_mass}
            #       $moo3{molar_mass}
            / $mat_href->{molar_mass};
        # (ii) Mass
        #            $moo3{mo}{mass}
        #             $moo3{o}{mass}
        $mat_href->{$elem_str}{mass} =
            #            $moo3{mo}{mass_frac}
            #             $moo3{o}{mass_frac}
            $mat_href->{$elem_str}{mass_frac}
            #       $moo3{mass}
            * $mat_href->{mass};
    }
    
    # $moo3{consti_elems} = ['mo', 'o']
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        #
        # (3) Associate the fraction quantities of the isotopes
        #     to the material hash.
        #
        
        # $mo{mass_nums} = ['92', '94', '95', '96', '97', '98', '100']
        foreach my $mass_num (@{$mat_href->{$elem_str}{href}{mass_nums}}) {
            #                    $moo3{mo92}{amt_frac}
            $mat_href->{$elem_str.$mass_num}{amt_frac} = # Autovivified
                #                               $mo{92}{amt_frac}
                $mat_href->{$elem_str}{href}{$mass_num}{amt_frac};
            #                    $moo3{mo92}{mass_frac}
            $mat_href->{$elem_str.$mass_num}{mass_frac} = # Autovivified
                #                               $mo{92}{mass_frac}
                $mat_href->{$elem_str}{href}{$mass_num}{mass_frac};
            
            #***************************************************************
            #
            # (4) Calculate DCCs of the isotopes.
            #
            #***************************************************************
            
            # (a) If this routine was called as DCC preprocessing,
            #     create and memorize the 1st variable of an DCC.
            if ($run_mode and $run_mode =~ /dcc_preproc/i) {
                # (a-1) DCC in terms of amount fractions
                # $memorized{moo3}{mo92}{amt_frac_bef}
                $memorized->{$mat_href->{label}}
                            {$elem_str.$mass_num}
                            {amt_frac_bef} =
                    #                    $moo3{mo92}{amt_frac}
                    $mat_href->{$elem_str.$mass_num}{amt_frac};
                #               $memorized{moo3}{molar_mass_bef}
                $memorized->{$mat_href->{label}}{molar_mass_bef} =
                    #     $moo3{molar_mass}
                    $mat_href->{molar_mass};
                
                # (a-2) DCC in terms of mass fractions
                # $memorized{moo3}{mo92}{mass_frac_bef}
                $memorized->{$mat_href->{label}}
                            {$elem_str.$mass_num}
                            {mass_frac_bef} =
                    #                    $moo3{mo92}{mass_frac}
                    $mat_href->{$elem_str.$mass_num}{mass_frac};
                #                      $memorized{moo3}{mo}{mass_frac_bef}
                $memorized->{$mat_href->{label}}{$elem_str}{mass_frac_bef} =
                    #            $moo3{mo}{mass_frac}
                    $mat_href->{$elem_str}{mass_frac};
            }
            
            # (b) Assign the memorized 1st variable of the DCC.
            # (b-1) DCC in terms of amount fractions
            $mat_href->{$elem_str.$mass_num}{amt_frac_bef} =
                $memorized->{$mat_href->{label}}
                            {$elem_str.$mass_num}
                            {amt_frac_bef};
            $mat_href->{molar_mass_bef} =
                $memorized->{$mat_href->{label}}
                            {molar_mass_bef};
            
            # (b-2) DCC in terms of mass fractions
            $mat_href->{$elem_str.$mass_num}{mass_frac_bef} =
                $memorized->{$mat_href->{label}}
                            {$elem_str.$mass_num}
                            {mass_frac_bef};
            $mat_href->{$elem_str}{mass_frac_bef} =
                $memorized->{$mat_href->{label}}
                            {$elem_str}{mass_frac_bef};
            
            # (c) Assign the 2nd variable of the DCC.
            # (c-1) DCC in terms of amount fractions
            #                    $moo3{mo92}{amt_frac_aft}
            $mat_href->{$elem_str.$mass_num}{amt_frac_aft} =
                #                    $moo3{mo92}{amt_frac}
                $mat_href->{$elem_str.$mass_num}{amt_frac};
            #     $moo3{molar_mass_aft}
            $mat_href->{molar_mass_aft} =
                #     $moo3{molar_mass}
                $mat_href->{molar_mass};
            
            # (c-2) DCC in terms of mass fractions
            #                    $moo3{mo92}{mass_frac_aft}
            $mat_href->{$elem_str.$mass_num}{mass_frac_aft} =
                #                    $moo3{mo92}{mass_frac}
                $mat_href->{$elem_str.$mass_num}{mass_frac};
            #            $moo3{mo}{mass_frac_aft}
            $mat_href->{$elem_str}{mass_frac_aft} =
                #            $moo3{mo}{mass_frac}
                $mat_href->{$elem_str}{mass_frac};
            
            # (d) Calculate the DCC using (b) and (c) above.
            # (d-i) DCC in terms of amount fractions
            $mat_href->{$elem_str.$mass_num}{dcc} = (
                $mat_href->{$elem_str.$mass_num}{amt_frac_aft}
                / $mat_href->{$elem_str.$mass_num}{amt_frac_bef}
            ) * (
                $mat_href->{molar_mass_bef}
                / $mat_href->{molar_mass_aft}
            ) if $enri_lev_type eq 'amt_frac';
            
            # (d-ii) DCC in terms of mass fractions
            $mat_href->{$elem_str.$mass_num}{dcc} = (
                $mat_href->{$elem_str.$mass_num}{mass_frac_aft}
                / $mat_href->{$elem_str.$mass_num}{mass_frac_bef}
            ) * (
                $mat_href->{$elem_str}{mass_frac_aft}
                / $mat_href->{$elem_str}{mass_frac_bef}
            ) if $enri_lev_type eq 'mass_frac';
        }
    }
    
    if ($is_verbose) {
        dump($mat_href);
        pause_shell("Press enter to continue...");
    }
    
    return;
}


sub calc_mass_dens_and_num_dens {
    # """Calculate the number density of the material,
    # the mass and number densities of the constituent elements and
    # their isotopes."""
    
    my(                 # e.g.
        $mat_href,      # %\moo3
        $enri_lev_type, # 'amt_frac'
        $is_verbose,    # 1 (boolean)
    ) = @_;
    my $avogadro = 6.02214076e+23; # Number of substances per mole
    
    if ($is_verbose) {
        say "\n".("=" x 70);
        printf(
            "[%s]\n".
            "calculating the number density of [%s],\n".
            "the mass and number densities of [%s], and\n".
            "the mass and number densities of [%s] isotopes...\n",
            join('::', (caller(0))[3]),
            $mat_href->{label},
            join(', ', @{$mat_href->{consti_elems}}),
            join(', ', @{$mat_href->{consti_elems}}),
        );
        say "=" x 70;
    }
    
    #
    # (i) Material
    #
    
    # Number density
    $mat_href->{num_dens} =
        $mat_href->{mass_dens} # Tabulated value
        * $avogadro
        # Below had been calculated in:
        # calc_mat_molar_mass_and_subcomp_mass_fracs_and_dccs()
        / $mat_href->{molar_mass};
    
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        #
        # (ii) Constituent elements
        #
        
        # Mass density
        #            $moo3{mo}{mass_dens}
        #             $moo3{o}{mass_dens}
        $mat_href->{$elem_str}{mass_dens} =
            #            $moo3{mo}{mass_frac}
            #             $moo3{o}{mass_frac}
            $mat_href->{$elem_str}{mass_frac}
            #       $moo3{mass_dens}
            * $mat_href->{mass_dens};
        
        # Number density
        # (i) Using the amount fraction
        #            $moo3{mo}{num_dens}
        #             $moo3{o}{num_dens}
        $mat_href->{$elem_str}{num_dens} = (
            #            $moo3{mo}{amt_subs}
            #             $moo3{o}{amt_subs}
            $mat_href->{$elem_str}{amt_subs} # Caution: Not 'amt_frac'
            #       $moo3{num_dens}
            * $mat_href->{num_dens}
        ) if $enri_lev_type eq 'amt_frac';
        
        # (ii) Using the mass fraction
        #            $moo3{mo}{num_dens}
        #             $moo3{o}{num_dens}
        $mat_href->{$elem_str}{num_dens} = (
            #            $moo3{mo}{mass_dens}
            #             $moo3{o}{mass_dens}
            $mat_href->{$elem_str}{mass_dens}
            * $avogadro
            #                          $mo{wgt_avg_molar_mass}
            #                           $o{wgt_avg_molar_mass}
            / $mat_href->{$elem_str}{href}{wgt_avg_molar_mass}
        ) if $enri_lev_type eq 'mass_frac';
        
        #
        # (iii) Isotopes of the consistent elements
        #
        
        # $mo{mass_nums} = ['92', '94', '95', '96', '97', '98', '100']
        foreach my $mass_num (@{$mat_href->{$elem_str}{href}{mass_nums}}) {
            # Mass density
            #                    $moo3{mo92}{mass_dens}
            $mat_href->{$elem_str.$mass_num}{mass_dens} =
                #                    $moo3{mo92}{mass_frac}
                $mat_href->{$elem_str.$mass_num}{mass_frac}
                #              $moo3{mo}{mass_dens}
                * $mat_href->{$elem_str}{mass_dens};
            
            # Number density
            # (i) Using the amount fraction
            #                    $moo3{mo92}{num_dens}
            $mat_href->{$elem_str.$mass_num}{num_dens} = (
                #                    $moo3{mo92}{amt_frac}
                $mat_href->{$elem_str.$mass_num}{amt_frac}
                #              $moo3{mo}{num_dens}
                * $mat_href->{$elem_str}{num_dens}
            ) if $enri_lev_type eq 'amt_frac';
            
            # (ii) Using the mass fraction
            #                    $moo3{mo92}{num_dens}
            $mat_href->{$elem_str.$mass_num}{num_dens} = (
                #                    $moo3{mo92}{mass_dens}
                $mat_href->{$elem_str.$mass_num}{mass_dens}
                * $avogadro
                #                                 $mo{92}{molar_mass}
                / $mat_href->{$elem_str}{href}{$mass_num}{molar_mass}
            ) if $enri_lev_type eq 'mass_frac';
        }
    }
    
    if ($is_verbose) {
        dump($mat_href);
        pause_shell("Press enter to continue...");
    }
    
    return;
}


sub adjust_num_of_decimal_places {
    # """Adjust the number of decimal places of calculation results."""
    
    my(
        $chem_hrefs,
        $precision_href,
        $enri_lev_range_first,
    ) = @_;
    my $num_decimal_pts = length(substr($enri_lev_range_first, 2));
    
    my %fmt_specifiers = (
        molar_mass         => '%.5f', # Molar mass of a nuclide or a material
        wgt_molar_mass     => '%.5f', # Weighted molar mass of a nuclide
        wgt_avg_molar_mass => '%.5f', # Weighted-avg molar mass of an element
        amt_frac           => '%.'.$num_decimal_pts.'f',
        mass_frac          => '%.'.$num_decimal_pts.'f',
        mass_dens          => '%.5f',
        num_dens           => '%.5e',
        dcc                => '%.4f', # Density change coefficient
    );
    # Override the format specifiers if any have been
    # designated via the input file.
    $fmt_specifiers{$_} = $precision_href->{$_} for keys %$precision_href;
    
    # Memorandum
    # - "DO NOT" change the number of decimal places of the element hashes.
    #   If adjusted, the modified precision remains changed in the next run
    #   of enri(), affecting all the other subsequent calculations that use
    #   the attributes of the element hashes.
    # - Instead, work ONLY on the materials hashes which will be recalculated
    #   each time enri() is called.
    foreach my $attr (keys %fmt_specifiers) {
        # $k1 == o, mo, momet, moo2, moo3...
        foreach my $k1 (keys %$chem_hrefs) {
            #*******************************************************************
            # Work ONLY on materials.
            #*******************************************************************
            next unless $chem_hrefs->{$k1}{data_type} =~ /mat/i;
            
            if (
                exists $chem_hrefs->{$k1}{$attr}
                and ref \$chem_hrefs->{$k1}{$attr} eq SCALAR
            ) {
                #        $moo3{mass_dens}
                $chem_hrefs->{$k1}{$attr} = sprintf(
                    "$fmt_specifiers{$attr}",
                    $chem_hrefs->{$k1}{$attr},
                )
            }
            
            # $k2 == mass_dens, HASH (<= mo, o, mo92, ...)
            foreach my $k2 (%{$chem_hrefs->{$k1}}) {
                # If $k2 == HASH (<= mo, o, mo92, ...)
                if (
                    ref $k2 eq HASH
                    and exists $k2->{$attr}
                    and ref \$k2->{$attr} eq SCALAR
                ) {
                    # Increase the number of decimal points of the Mo mass
                    # fraction "if" it is smaller than 5. This is to
                    # smoothen the curve of the Mo mass fraction of Mo oxides.
                    # e.g. Mo mass frac 0.6666 --> 0.66656
                    #      at Mo-100 mass frac 0.10146
                    if (
                        $num_decimal_pts < 5
                        and $attr eq 'mass_frac'
                        and exists $k2->{href} # $moo3{mo} and $moo3{o} only
                        and $k2->{href}{label} eq 'mo' # $moo3{mo} only
                    ) {
                        # $moo3{mo}{mass_frac}
                        $k2->{$attr} = sprintf(
                            "%.5f",
                            $k2->{$attr},
                        );
                    }
                    
                    else {
                        # $moo3{mo}{amt_subs}
                        $k2->{$attr} = sprintf(
                            "$fmt_specifiers{$attr}",
                            $k2->{$attr},
                        );
                    }
                }
            }
        }
    }
    
    return;
}


sub assoc_prod_nucls_with_reactions_and_dccs {
    # """Associate product nuclides with nuclear reactions and DCCs."""
    
    my(
        $chem_hrefs,           # e.g.
        $mat,                  # 'moo3'
        $enri_nucl,            # 'mo100'
        $enri_lev,             # 0.0974
        $enri_lev_range_first, # 0.0000
        $enri_lev_range_last,  # 0.9739
        $enri_lev_type,        # 'amt_frac'
        $depl_order,           # 'ascend'
        $out_path,             # './mo100'
        $projs,                # ['g', 'n', 'p']
        $is_verbose,           # 1 (boolean)
    ) = @_;
    my $mat_href = $chem_hrefs->{$mat}, # \%moo3
    
    my %elems = (
        # (key) Atomic number
        # (val) Element name and symbol
        30 => {symb => 'Zn', name => 'zinc'     },
        31 => {symb => 'Ga', name => 'gallium'  },
        32 => {symb => 'Ge', name => 'germanium'},
        33 => {symb => 'As', name => 'arsenic'  },
        34 => {symb => 'Se', name => 'selenium' },
        35 => {symb => 'Br', name => 'bromine'  },
        36 => {symb => 'Kr', name => 'krypton'  },
        37 => {symb => 'Rb', name => 'rubidium' },
        38 => {
            symb => 'Sr',
            name => 'strontium',
            75 => {
                half_life => 1.97222e-05,
            },
            76 => {
                half_life => 0.002472222,
            },
            77 => {
                half_life => 0.0025,
            },
            78 => {
                half_life => 0.041666667,
            },
            79 => {
                half_life => 0.0375,
            },
            80 => {
                half_life => 1.771666667,
            },
            81 => {
                half_life => 0.371666667,
            },
            82 => {
                half_life => 613.2,
            },
            83 => {
                half_life => 32.41,
            },
            '83m' => {
                half_life => 0.001375,
            },
            84 => {
                half_life => 'stable',
            },
            85 => {
                half_life => 1556.16,
            },
            '85m' => {
                half_life => 1.127166667,
            },
            86 => {
                half_life => 'stable',
            },
            87 => {
                half_life => 'stable',
            },
            '87m' => {
                half_life => 2.803,
            },
            88 => {
                half_life => 'stable',
            },
            89 => {
                half_life => 1212.72,
            },
            90 => {
                half_life => 252200.4,
            },
            91 => {
                half_life => 9.63,
            },
            92 => {
                half_life => 2.71,
            },
            93 => {
                half_life => 0.123716667,
            },
            94 => {
                half_life => 0.020916667,
            },
            95 => {
                half_life => 0.006638889,
            },
            96 => {
                half_life => 0.000297222,
            },
            97 => {
                half_life => 0.000118333,
            },
            98 => {
                half_life => 0.000181389,
            },
            99 => {
                half_life => 7.47222e-05,
            },
            100 => {
                half_life => 5.61111e-05,
            },
            101 => {
                half_life => 3.27778e-05,
            },
            102 => {
                half_life => 1.91667e-05,
            },
        },
        39 => {
            symb => 'Y',
            name => 'yttrium',
            79 => {
                half_life => 0.004111111,
            },
            80 => {
                half_life => 0.009722222,
            },
            81 => {
                half_life => 0.019555556,
            },
            82 => {
                half_life => 0.002638889,
            },
            83 => {
                half_life => 0.118,
            },
            '83m' => {
                half_life => 0.0475,
            },
            84 => {
                half_life => 0.001277778,
            },
            '84m' => {
                half_life => 0.658333333,
            },
            85 => {
                half_life => 2.68,
            },
            '85m' => {
                half_life => 4.86,
            },
            86 => {
                half_life => 14.74,
            },
            '86m' => {
                half_life => 0.8,
            },
            87 => {
                half_life => 79.8,
            },
            '87m' => {
                half_life => 13.37,
            },
            88 => {
                half_life => 2559.6,
            },
            '88m' => {
                half_life => 3.86111e-06,
            },
            89 => {
                half_life => 'stable',
            },
            '89m' => {
                half_life => 0.004461111,
            },
            90 => {
                half_life => 64,
            },
            '90m' => {
                half_life => 3.19,
            },
            91 => {
                half_life => 1404.24,
            },
            '91m' => {
                half_life => 0.8285,
            },
            92 => {
                half_life => 3.54,
            },
            93 => {
                half_life => 10.18,
            },
            '93m' => {
                half_life => 0.000227778,
            },
            94 => {
                half_life => 0.311666667,
            },
            95 => {
                half_life => 0.171666667,
            },
            96 => {
                half_life => 0.001483333,
            },
            '96m' => {
                half_life => 0.002666667,
            },
            97 => {
                half_life => 0.001041667,
            },
            '97m' => {
                half_life => 0.000325,
            },
            98 => {
                half_life => 0.000152222,
            },
            '98m' => {
                half_life => 0.000555556,
            },
            99 => {
                half_life => 0.000408333,
            },
            100 => {
                half_life => 0.000204722,
            },
            '100m' => {
                half_life => 0.000261111,
            },
            101 => {
                half_life => 0.000125,
            },
            102 => {
                half_life => 0.0001,
            },
            '102m' => {
                half_life => 8.33333e-05,
            },
            103 => {
                half_life => 6.38889e-05,
            },
        },
        40 => {
            symb => 'Zr',
            name => 'zirconium',
            81 => {
                half_life => 0.004166667,
            },
            82 => {
                half_life => 0.008888889,
            },
            83 => {
                half_life => 0.012222222,
            },
            84 => {
                half_life => 0.431666667,
            },
            85 => {
                half_life => 0.131,
            },
            '85m' => {
                half_life => 0.003027778,
            },
            86 => {
                half_life => 16.5,
            },
            87 => {
                half_life => 1.68,
            },
            '87m' => {
                half_life => 0.003888889,
            },
            88 => {
                half_life => 2001.6,
            },
            89 => {
                half_life => 78.41,
            },
            '89m' => {
                half_life => 0.069666667,
            },
            90 => {
                half_life => 'stable',
            },
            '90m' => {
                half_life => 0.000224778,
            },
            91 => {
                half_life => 'stable',
            },
            92 => {
                half_life => 'stable',
            },
            93 => {
                half_life => 13402.8,
            },
            94 => {
                half_life => 'stable',
            },
            95 => {
                half_life => 1536.48,
            },
            96 => {
                half_life => 3.3288e23,
            },
            97 => {
                half_life => 16.91,
            },
            98 => {
                half_life => 0.008527778,
            },
            99 => {
                half_life => 0.000583333,
            },
            100 => {
                half_life => 0.001972222,
            },
            101 => {
                half_life => 0.000638889,
            },
            102 => {
                half_life => 0.000805556,
            },
            103 => {
                half_life => 0.000361111,
            },
            104 => {
                half_life => 0.000333333,
            },
            105 => {
                half_life => 0.000166667,
            },
        },
        41 => {
            symb => 'Nb',
            name => 'niobium',
            83 => {
                half_life => 0.001138889,
            },
            84 => {
                half_life => 0.003333333,
            },
            85 => {
                half_life => 0.005805556,
            },
            86 => {
                half_life => 0.024444444,
            },
            '86m' => {
                half_life => 0.015555556,
            },
            87 => {
                half_life => 0.043333333,
            },
            '87m' => {
                half_life => 0.061666667,
            },
            88 => {
                half_life => 0.241666667,
            },
            '88m' => {
                half_life => 0.13,
            },
            89 => {
                half_life => 1.9,
            },
            '89m' => {
                half_life => 1.18,
            },
            90 => {
                half_life => 14.6,
            },
            '90m' => {
                half_life => 0.005225,
            },
            91 => {
                half_life => 5956800,
            },
            '91m' => {
                half_life => 1460.64,
            },
            92 => {
                half_life => 3.03972e11,
            },
            '92m' => {
                half_life => 243.6,
            },
            93 => {
                half_life => 'stable',
            },
            '93m' => {
                half_life => 141298.8,
            },
            94 => {
                half_life => 177828000,
            },
            '94m' => {
                half_life => 0.104383333,
            },
            95 => {
                half_life => 839.4,
            },
            '95m' => {
                half_life => 86.6,
            },
            96 => {
                half_life => 23.35,
            },
            97 => {
                half_life => 1.201666667,
            },
            '97m' => {
                half_life => 0.014638889,
            },
            98 => {
                half_life => 0.000794444,
            },
            '98m' => {
                half_life => 0.855,
            },
            99 => {
                half_life => 0.004166667,
            },
            '99m' => {
                half_life => 0.043333333,
            },
            100 => {
                half_life => 0.000416667,
            },
            '100m' => {
                half_life => 0.000830556,
            },
            101 => {
                half_life => 0.001972222,
            },
            102 => {
                half_life => 0.000361111,
            },
            '102m' => {
                half_life => 0.001194444,
            },
            103 => {
                half_life => 0.000416667,
            },
            104 => {
                half_life => 0.001333333,
            },
            '104m' => {
                half_life => 0.000255556,
            },
            105 => {
                half_life => 0.000819444,
            },
            106 => {
                half_life => 0.000283333,
            },
            107 => {
                half_life => 9.16667e-05,
            },
            108 => {
                half_life => 5.36111e-05,
            },
            109 => {
                half_life => 5.27778e-05,
            },
            110 => {
                half_life => 4.72222e-05,
            },
        },
        42 => {
            symb => 'Mo',
            name => 'molybdenum',
            86 => {
                half_life => 0.005444444,
            },
            87 => {
                half_life => 0.003722222,
            },
            88 => {
                half_life => 0.133333333,
            },
            89 => {
                half_life => 0.034,
            },
            '89m' => {
                half_life => 5.27778e-05,
            },
            90 => {
                half_life => 5.56,
            },
            91 => {
                half_life => 0.258166667,
            },
            '91m' => {
                half_life => 0.018055556,
            },
            92 => {
                half_life => 'stable',
            },
            93 => {
                half_life => 35040000,
            },
            '93m' => {
                half_life => 6.85,
            },
            94 => {
                half_life => 'stable',
            },
            95 => {
                half_life => 'stable',
            },
            96 => {
                half_life => 'stable',
            },
            97 => {
                half_life => 'stable',
            },
            98 => {
                half_life => 'stable',
            },
            99 => {
                half_life => 65.94,
            },
            100 => {
                half_life => 8.76e22,
            },
            101 => {
                half_life => 0.2435,
            },
            102 => {
                half_life => 0.188333333,
            },
            103 => {
                half_life => 0.01875,
            },
            104 => {
                half_life => 0.016666667,
            },
            105 => {
                half_life => 0.009888889,
            },
            106 => {
                half_life => 0.002333333,
            },
            107 => {
                half_life => 0.000972222,
            },
            108 => {
                half_life => 0.000302778,
            },
            109 => {
                half_life => 0.000147222,
            },
            110 => {
                half_life => 8.33333e-05,
            },
        },
        43 => {
            symb => 'Tc',
            name => 'technetium',
            88 => {
                half_life => 0.001777778,
            },
            '88m' => {
                half_life => 0.001611111,
            },
            89 => {
                half_life => 0.003555556,
            },
            '89m' => {
                half_life => 0.003583333,
            },
            90 => {
                half_life => 0.013666667,
            },
            '90m' => {
                half_life => 0.002416667,
            },
            91 => {
                half_life => 0.052333333,
            },
            '91m' => {
                half_life => 0.055,
            },
            92 => {
                half_life => 0.0705,
            },
            93 => {
                half_life => 2.75,
            },
            '93m' => {
                half_life => 0.725,
            },
            94 => {
                half_life => 4.883333333,
            },
            '94m' => {
                half_life => 0.866666667,
            },
            95 => {
                half_life => 20,
            },
            '95m' => {
                half_life => 1464,
            },
            96 => {
                half_life => 102.72,
            },
            '96m' => {
                half_life => 51.5,
            },
            97 => {
                half_life => 22776000000,
            },
            '97m' => {
                half_life => 2162.4,
            },
            98 => {
                half_life => 36792000000,
            },
            99 => {
                half_life => 1849236000,
            },
            '99m' => {
                half_life => 6.01,
            },
            100 => {
                half_life => 0.004388889,
            },
            101 => {
                half_life => 0.237,
            },
            102 => {
                half_life => 0.001466667,
            },
            '102m' => {
                half_life => 0.0725,
            },
            103 => {
                half_life => 0.015055556,
            },
            104 => {
                half_life => 0.305,
            },
            105 => {
                half_life => 0.126666667,
            },
            106 => {
                half_life => 0.009888889,
            },
            107 => {
                half_life => 0.005888889,
            },
            108 => {
                half_life => 0.001436111,
            },
            109 => {
                half_life => 0.000241667,
            },
            110 => {
                half_life => 0.000255556,
            },
            111 => {
                half_life => 8.33333e-05,
            },
            112 => {
                half_life => 7.77778e-05,
            },
            113 => {
                half_life => 3.61111e-05,
            },
        },
        44 => {symb => 'Ru', name => 'ruthenium' },
        45 => {symb => 'Rh', name => 'Rhodium'   },
        46 => {symb => 'Pd', name => 'Palladium' },
        47 => {symb => 'Ag', name => 'Silver'    },
        48 => {symb => 'Cd', name => 'Cadmium'   },
        49 => {symb => 'In', name => 'Indium'    },
        50 => {symb => 'Sn', name => 'Tin'       },
    );
    my %prod_nucls; # Storage for product nuclides
    my %parts = (
        # Homogeneous: Ejectiles are multiplied by integers in the loop below.
        g => {
            name     => 'gamma',
            num_neut => 0,
            num_prot => 0,
            max_ejec => {
                # (key) projectile
                # (val) max_ejec
                g => 1,
                n => 1,
                p => 1,
            },
        },
        n => {
            name     => 'neutron',
            num_neut => 1,
            num_prot => 0,
            max_ejec => {
                g => 3,
                n => 3,
                p => 3,
            },
        },
        p => {
            name     => 'proton',
            num_neut => 0,
            num_prot => 1,
            max_ejec => {
                g => 1,
                n => 3,
                p => 2,
            },
        },
        d => {
            name     => 'deuteron',
            num_neut => 1,
            num_prot => 1,
            max_ejec => {
                g => 1,
                n => 1,
                p => 1,
            },
        },
        t => {
            name     => 'triton',
            num_neut => 2,
            num_prot => 1,
            max_ejec => {
                g => 1,
                n => 1,
                p => 1,
            },
        },
        a => {
            name     => 'alpha',
            num_neut => 2,
            num_prot => 2,
            max_ejec => {
                g => 1,
                n => 1,
                p => 1,
            },
        },
        
        # Heterogeneous: Number of ejectiles are invariable.
        np => { # For neutron reactions
            num_neut => 1,
            num_prot => 1,
        },
        pn => { # For proton reactions
            num_neut => 1,
            num_prot => 1,
        },
        an => {
            num_neut => 3,
            num_prot => 2,
        },
        ann => {
            num_neut => 4,
            num_prot => 2,
        },
        ap => {
            num_neut => 2,
            num_prot => 3,
        },
        app => {
            num_neut => 2,
            num_prot => 4,
        },
    );
    
    # Homogeneous ejectiles
    my %ejecs = (
        # (key) projectile
        # (val) ejecs_hetero
        g => [qw(g n p a)],
        n => [qw(g n p d t a)],
        p => [qw(g n p d t a)],
    );
    # Heterogeneous ejectiles
    my %ejecs_hetero = (
        # (key) projectile
        # (val) ejecs_hetero
        g => [qw(np)],
        n => [qw(np an ann ap app)],
        p => [qw(pn an ann ap)],
    );
    
    #
    # (1/2) Arithmetic for nuclear reaction channels
    #
    
    # $moo3{consti_elems} = ['mo', 'o']
    foreach my $elem_str (@{$mat_href->{consti_elems}}) {
        # Redirect the atomic number of the constituent element
        # for clearer coding.
        my $atomic_num = $mat_href->{$elem_str}{href}{atomic_num};
        
        # $mo{mass_nums} = ['92', '94', '95', '96', '97', '98', '100']
        foreach my $mass_num (@{$mat_href->{$elem_str}{href}{mass_nums}}) {
            # ('g', 'n', 'p')
            foreach my $proj (@$projs) {
                # Homogeneous ejectiles
                # e.g. ('g', 'n', 'p', 'd', 't', 'a')
                foreach my $ejec (@{$ejecs{$proj}}) {
                    foreach my $num_ejec (1..$parts{$ejec}{max_ejec}{$proj}) {
                        # Atomic number of the product nuclide
                        my $new_atomic_num =
                            $atomic_num
                            + $parts{$proj}{num_prot}
                            - $num_ejec * $parts{$ejec}{num_prot};
                        
                        # Mass number of the product nuclide
                        my $new_mass_num =
                            $mass_num
                            + $parts{$proj}{num_neut}
                            + $parts{$proj}{num_prot}
                            - $num_ejec * $parts{$ejec}{num_neut}
                            - $num_ejec * $parts{$ejec}{num_prot};
                        
                        # Autovivified
                        my $reaction = sprintf(
                            "%s%s%s%s%s",
                            $elem_str,
                            $mass_num,
                            $proj,
                            ($num_ejec > 1 ? $num_ejec : ''),
                            $ejec,
                        );
                        # Skip nn, pp, ...
                        next if $num_ejec == 1 and $proj eq $ejec;
                        $prod_nucls
                            {$proj}{$new_atomic_num}{$new_mass_num}{$reaction} =
                                $mat_href->{$elem_str.$mass_num}{dcc};
                    }
                }
                
                # Heterogeneous ejectiles
                # e.g. ('np', 'an', 'ann', 'ap', 'app')
                foreach my $ejecs (@{$ejecs_hetero{$proj}}) {
                    # Atomic number of the product nuclide
                    my $new_atomic_num =
                        $atomic_num
                        + $parts{$proj}{num_prot}
                        - $parts{$ejecs}{num_prot};
                    
                    # Mass number of the product nuclide
                    my $new_mass_num =
                        $mass_num
                        + $parts{$proj}{num_neut}
                        + $parts{$proj}{num_prot}
                        - $parts{$ejecs}{num_neut}
                        - $parts{$ejecs}{num_prot};
                    
                    # Autovivified
                    my $reaction = sprintf(
                        "%s%s%s%s",
                        $elem_str,
                        $mass_num,
                        $proj,
                        $ejecs,
                    );
                    $prod_nucls
                        {$proj}{$new_atomic_num}{$new_mass_num}{$reaction} =
                            $mat_href->{$elem_str.$mass_num}{dcc};
                }
            }
        }
    }
    
    #
    # (2/2) Generate reporting files.
    #
    my %convs = (
        isot      => '%-3s',
        half_life => '%7.1f',
        stable    => '%8s', # 7.1f => 8s
        react     => '%-10s',
    );
    my %seps = (
        col        => "  ", # or: \t
        data_block => "\n",
        dataset    => "\n\n",
    );
    my $not_a_number = "NaN";
    my %filters = (
        half_lives => {
            min => 10 / 60,  # h; 10 min
            max => 24 * 365, # h; 1 y
        },
        stable => 'off', # on:show stable nucl
    );
    state $is_first = 1; # Hook - onetime on
    foreach my $proj (@$projs) {
        mkdir $out_path if not -e $out_path;
        (my $from = $enri_lev_range_first) =~ s/[.]/p/;
        (my $to   = $enri_lev_range_last)  =~ s/[.]/p/;
        my $nucls_rpt_bname = sprintf(
            "%s_%s_%s_%s_%s_%s_%s",
            $mat,
            $enri_nucl,
            $enri_lev_type,
            $from,
            $to,
            (
                $depl_order =~ /asc/i  ? 'asc' :
                $depl_order =~ /desc/i ? 'desc' :
                                         'rand'
            ),
            $proj,
        );
        my $nucls_rpt_fname = "$out_path/$nucls_rpt_bname.dat";
        unlink $nucls_rpt_fname if -e $nucls_rpt_fname and $is_first;
        
        open my $nucls_rpt_fh, '>>:encoding(UTF-8)', $nucls_rpt_fname;
        select($nucls_rpt_fh);
        
        # Front matter and warnings
        if ($is_first) {
            my $dt = DateTime->now(time_zone => 'local');
            my $ymd = $dt->ymd();
            my $hms = $dt->hms(':');
            say "#".("-" x 79);
            say "#";
            printf(
                "# Product nuclides of Mo %s reactions associated with DCCs\n",
                $parts{$proj}{name},
            );
            say "# Generated by $0 (J. Jang)";
            printf("# %s %s\n", $ymd, $hms);
            say "#";
            say "# Display conditions for product nuclides";
            printf(
                "# > Min half-life:  %.5e h (%.5e m; %.5e y)\n",
                $filters{half_lives}{min},
                $filters{half_lives}{min} * 60,
                $filters{half_lives}{min} / 24 / 365,
            );
            printf(
                "# > Max half-life:  %.5e h (%.5e m; %.5e y)\n",
                $filters{half_lives}{max},
                $filters{half_lives}{max} * 60,
                $filters{half_lives}{max} / 24 / 365,
            );
            say "# > Stable nuclide: $filters{stable}";
            say "#";
            say "#".("-" x 79);
        }
        
        # Dataset header: Current enrichment level
        print $seps{dataset} unless $is_first; # Dataset separator
        say "#".("=" x 79);
        printf(
            "# [%s] <= %s %s in %s\n",
            $enri_lev,
            $enri_nucl,
            $enri_lev_type,
            $mat,
        );
        say "#".("=" x 79);
        
        # Layer 1: Chemical element
        my @elems_asc =
            sort { $a <=> $b } keys %{$prod_nucls{$proj}};
        # 39, 40, 41, ... (atomic number)
        foreach my $elem (@elems_asc) {
            # Data block header: Atomic number
            say "#".("-" x 79);
            print "# Z = $elem";
            print $elems{$elem}{symb} ? " ($elems{$elem}{symb}" : "";
            print $elems{$elem}{name} ? "; $elems{$elem}{name}" : "";
            print $elems{$elem}{symb} ? ")" : "";
            print "\n";
            say "#".("-" x 79);
            
            # Layer 2: Isotope
            my @isots_asc =
                sort { $a <=> $b } keys %{$prod_nucls{$proj}{$elem}};
            foreach my $isot (@isots_asc) {
                # Layer 3: Isotope and its isomer
                my @the_isots = ($isot);
                if (
                    exists $elems{$elem}{$isot.'m'}
                    and (
                        $elems{$elem}{$isot.'m'}{half_life}
                        > $filters{half_lives}{min}
                    )
                    and (
                        $elems{$elem}{$isot.'m'}{half_life}
                        < $filters{half_lives}{max}
                    )
                ) { push @the_isots, $isot.'m' }
                foreach my $the_isot (@the_isots) {
                    # Filtering
                    if ($elems{$elem}{$the_isot}{half_life}) {
                        next if (
                            $elems{$elem}{$the_isot}{half_life} =~ /stable/i
                            and not $filters{stable} =~ /on/i
                        );
                        next if (
                            $elems{$elem}{$the_isot}{half_life} =~ /[0-9]+/
                            and (
                                $elems{$elem}{$the_isot}{half_life}
                                < $filters{half_lives}{min}
                            )
                        );
                        next if (
                            $elems{$elem}{$the_isot}{half_life} =~ /[0-9]+/
                            and (
                                $elems{$elem}{$the_isot}{half_life}
                                > $filters{half_lives}{max}
                            )
                        );
                    }
                    
                    # Mass number
                    printf(
                        "$convs{isot}%s",
                        $the_isot,
                        $seps{col},
                    );
                    
                    # Half-life
                    printf(
                        (
                            $elems{$elem}{$the_isot}{half_life} =~ /[0-9]+/ ?
                                $convs{half_life}."h" : $convs{stable}
                        ),
                        $elems{$elem}{$the_isot}{half_life},
                    ) if $elems{$elem}{$the_isot}{half_life};
                    print $not_a_number
                        if not $elems{$elem}{$the_isot}{half_life};
                    print $seps{col};
                    
                    # Layer 3: Nuclear reaction
                    (my $isot = $the_isot) =~ s/m$//i;
                    my @reacts_sorted =
                        sort keys %{$prod_nucls{$proj}{$elem}{$isot}};
                    foreach my $react (@reacts_sorted) {
                        printf(
                            "$convs{react}%s%s%s",
                            $react,
                            $seps{col},
                            $prod_nucls{$proj}{$elem}{$isot}{$react},
                            ($react eq $reacts_sorted[-1] ? "" : $seps{col}),
                        );
                    }
                    print "\n";
                }
            }
            print $seps{data_block} unless $elem == $elems_asc[-1];
        }
        
        select(STDOUT);
        close $nucls_rpt_fh;
        
        if ($enri_lev == $enri_lev_range_last) {
            say "[$nucls_rpt_fname] generated.";
        }
    }
    $is_first = 0; # Hook - off
    
    if ($is_verbose) {
        dump(\%prod_nucls);
        pause_shell("Press enter to continue...");
    }
    
    return;
}


sub enri_preproc {
    # """Preprocessor for enri(): Populate chemical entity hashes and
    # prepare for DCC calculation."""
    
    my @hnames_ordered = @{$_[0]->{hnames}};
    my( # Strings to be used as the keys of %registry
        $mat,
        $enri_nucl_elem,
        $enri_nucl_mass_num,
        $enri_lev,
    ) = @{$_[0]->{dcc_preproc}}{
        'mat',
        'enri_nucl_elem',
        'enri_nucl_mass_num',
        'enri_lev', # Used only for decimal places calculation
    };
    my $enri_lev_type       = $_[0]->{enri_lev_type};
    my $min_depl_lev_global = $_[0]->{min_depl_lev_global};
    my %min_depl_lev_local  = %{$_[0]->{min_depl_lev_local}}
        if $_[0]->{min_depl_lev_local};
    my $depl_order = $_[0]->{depl_order};
    my $is_verbose = $_[0]->{is_verbose};
    
    # Notification
    if ($is_verbose) {
        say "\n".("=" x 70);
        printf(
            "[%s]\n",
            join('::', (caller(0))[3])
        );
        say "=" x 70;
        printf(
            "populating the hashes of [%s]...\n",
            join(', ', @hnames_ordered),
        );
    }
    
    #
    # Notes
    #
    # Abbreviations
    # - TBC: To be calculated
    # - TBF: To be filled
    # - TBP: To be passed
    #
    # Idiosyncrasies
    # - Naturally occurring nuclides of a chemical element are registered
    #   to the element hash by their mass numbers as the hash keys.
    #   Also, an anonymous array of these keys is registered to the element hash
    #   by 'mass_nums' as the hash key. This array plays important roles
    #   throughout the program; examples include weighted-average molar mass
    #   calculation and enrichment level redistribution. Also,
    #   the use of the array enables changing the order of the nuclides
    #   to be depleted in the process of the enrichment of a specific nuclide.
    #
    
    #===========================================================================
    # Data: Chemical elements
    #===========================================================================
    #---------------------------------------------------------------------------
    # Z=8: oxygen
    #---------------------------------------------------------------------------
    my %o = (
        data_type  => 'elem', # Used for decimal places adjustment (postproc)
        atomic_num => 8,      # Used for nuclide production mapping
        label      => 'o',    # Used for referring to the hash name
        symb       => 'O',    # Used for output files
        name       => 'oxygen',
        mass_frac_sum      => 0, # TBC; used for mass-fraction weighting
        wgt_avg_molar_mass => 0, # TBC
        # Naturally occurring isotopes of this element
        # - Used for the calculation of its weighted-average molar mass
        #   and for enrichment level redistribution.
        # - Put the nuclides in the ascending order of mass number.
        mass_nums => [ # Iteration control; values must be keys of this hash
            '16',
            '17',
            '18',
        ],
        # amt_frac
        # - Natural abundance by "amount" fraction found in
        #   http://www.ciaaw.org/isotopic-abundances.htm
        #
        # mass_frac
        # - Calculated based on the amount fraction above
        #
        # molar_mass
        # - Atomic mass found in
        #   - http://www.ciaaw.org/atomic-masses.htm
        #   - wang2017.pdf
        '16' => {
            data_type      => 'nucl',
            mass_num       => 16,
            label          => 'o16',
            symb           => 'O-16',
            name           => 'oxygen-16',
            amt_frac       => 0.99757,
            mass_frac      => 0,            # TBC
            molar_mass     => 15.994914619, # g mol^-1
            wgt_molar_mass => 0,            # TBC
        },
        '17' => {
            data_type      => 'nucl',
            mass_num       => 17,
            label          => 'o17',
            symb           => 'O-17',
            name           => 'oxygen-17',
            amt_frac       => 0.0003835,
            mass_frac      => 0,
            molar_mass     => 16.999131757,
            wgt_molar_mass => 0,
        },
        '18' => {
            data_type      => 'nucl',
            mass_num       => 18,
            label          => 'o18',
            symb           => 'O-18',
            name           => 'oxygen-18',
            amt_frac       => 0.002045,
            mass_frac      => 0,
            molar_mass     => 17.999159613,
            wgt_molar_mass => 0,
        },
    );
    #---------------------------------------------------------------------------
    # Z=40: zirconium
    #---------------------------------------------------------------------------
    my %zr = (
        data_type          => 'elem',
        atomic_num         => 40,
        label              => 'zr',
        symb               => 'Zr',
        name               => 'zirconium',
        mass_frac_sum      => 0,
        wgt_avg_molar_mass => 0,
        mass_nums => [
            '90',
            '91',
            '92',
            '94',
            '96',
        ],
        '90' => {
            data_type      => 'nucl',
            mass_num       => 90,
            label          => 'zr90',
            symb           => 'Zr-90',
            name           => 'zirconium-90',
            amt_frac       => 0.5145,
            mass_frac      => 0,
            molar_mass     => 89.90469876,
            wgt_molar_mass => 0,
        },
        '90m' => {
            data_type => 'nucl',
            mass_num  => 90,
            label     => 'zr90m',
            symb      => 'Zr-90m',
            name      => 'zirconium-90m',
            # Radioactive
            half_life             => (809.2e-3 / 3600),          # h
            dec_const             => log(2) / (809.2e-3 / 3600), # h^-1
            yield                 => 0, # TBC
            yield_per_microamp    => 0, # TBC
            sp_yield              => 0, # TBC
            sp_yield_per_microamp => 0, # TBC
        },
        '91' => {
            data_type      => 'nucl',
            mass_num       => 91,
            label          => 'zr91',
            symb           => 'Zr-91',
            name           => 'zirconium-91',
            amt_frac       => 0.1122,
            mass_frac      => 0,
            molar_mass     => 90.90564022,
            wgt_molar_mass => 0,
        },
        '92' => {
            data_type      => 'nucl',
            mass_num       => 92,
            label          => 'zr92',
            symb           => 'Zr-92',
            name           => 'zirconium-92',
            amt_frac       => 0.1715,
            mass_frac      => 0,
            molar_mass     => 91.90503532,
            wgt_molar_mass => 0,
        },
        '93' => {
            data_type => 'nucl',
            mass_num  => 93,
            label     => 'zr93',
            symb      => 'Zr-93',
            name      => 'zirconium-93',
            # Radioactive
            half_life             => (1.53e+6 * 365 * 24),
            dec_const             => log(2) / (1.53e+6 * 365 * 24),
            yield                 => 0,
            yield_per_microamp    => 0,
            sp_yield              => 0,
            sp_yield_per_microamp => 0,
        },
        '94' => {
            data_type      => 'nucl',
            mass_num       => 94,
            label          => 'zr94',
            symb           => 'Zr-94',
            name           => 'zirconium-94',
            amt_frac       => 0.1738,
            mass_frac      => 0,
            molar_mass     => 93.90631252,
            wgt_molar_mass => 0,
        },
        '95' => {
            data_type => 'nucl',
            mass_num  => 95,
            label     => 'zr95',
            symb      => 'Zr-95',
            name      => 'zirconium-95',
        },
        '96' => {
            data_type      => 'nucl',
            mass_num       => 96,
            label          => 'zr96',
            symb           => 'Zr-96',
            name           => 'zirconium-96',
            amt_frac       => 0.0280,
            mass_frac      => 0,
            molar_mass     => 95.90827762,
            wgt_molar_mass => 0,
        },
        '98' => {
            data_type => 'nucl',
            mass_num  => 98,
            label     => 'zr98',
            symb      => 'Zr-98',
            name      => 'zirconium-98',
            # Radioactive
            half_life             => (30.7  / 3600),
            dec_const             => log(2) / (30.7  / 3600),
            yield                 => 0,
            yield_per_microamp    => 0,
            sp_yield              => 0,
            sp_yield_per_microamp => 0,
        },
    );
    #---------------------------------------------------------------------------
    # Z=41: niobium
    #---------------------------------------------------------------------------
    my %nb = (
        data_type          => 'elem',
        atomic_num         => 41,
        label              => 'nb',
        symb               => 'Nb',
        name               => 'niobium',
        mass_frac_sum      => 0,
        wgt_avg_molar_mass => 0,
        mass_nums => [
            '93',
        ],
        '93' => {
            data_type      => 'nucl',
            mass_num       => 93,
            label          => 'nb93',
            symb           => 'Nb-93',
            name           => 'niobium-93',
            amt_frac       => 1.00000,
            mass_frac      => 0,
            molar_mass     => 92.9063732,
            wgt_molar_mass => 0,
        },
    );
    #---------------------------------------------------------------------------
    # Z=42: molybdenum
    #---------------------------------------------------------------------------
    my %mo = (
        data_type          => 'elem',
        atomic_num         => 42,
        label              => 'mo',
        symb               => 'Mo',
        name               => 'molybdenum',
        mass_frac_sum      => 0,
        wgt_avg_molar_mass => 0,
        mass_nums => [
            '92',
            '94',
            '95',
            '96',
            '97',
            '98',
            '100',
        ],
        '92' => {
            data_type      => 'nucl',
            mass_num       => 92,
            label          => 'mo92',
            symb           => 'Mo-92',
            name           => 'molybdenum-92',
            amt_frac       => 0.14649,
            mass_frac      => 0,
            molar_mass     => 91.906807,
            wgt_molar_mass => 0,
        },
        '94' => {
            data_type      => 'nucl',
            mass_num       => 94,
            label          => 'mo94',
            symb           => 'Mo-94',
            name           => 'molybdenum-94',
            amt_frac       => 0.09187,
            mass_frac      => 0,
            molar_mass     => 93.905084,
            wgt_molar_mass => 0,
        },
        '95' => {
            data_type      => 'nucl',
            mass_num       => 95,
            label          => 'mo95',
            symb           => 'Mo-95',
            name           => 'molybdenum-95',
            amt_frac       => 0.15873,
            mass_frac      => 0,
            molar_mass     => 94.9058374,
            wgt_molar_mass => 0,
        },
        '96' => {
            data_type      => 'nucl',
            mass_num       => 96,
            label          => 'mo96',
            symb           => 'Mo-96',
            name           => 'molybdenum-96',
            amt_frac       => 0.16673,
            mass_frac      => 0,
            molar_mass     => 95.9046748,
            wgt_molar_mass => 0,
        },
        '97' => {
            data_type      => 'nucl',
            mass_num       => 97,
            label          => 'mo97',
            symb           => 'Mo-97',
            name           => 'molybdenum-97',
            amt_frac       => 0.09582,
            mass_frac      => 0,
            molar_mass     => 96.906017,
            wgt_molar_mass => 0,
        },
        '98' => {
            data_type      => 'nucl',
            mass_num       => 98,
            label          => 'mo98',
            symb           => 'Mo-98',
            name           => 'molybdenum-98',
            amt_frac       => 0.24292,
            mass_frac      => 0,
            molar_mass     => 97.905404,
            wgt_molar_mass => 0,
        },
        '99' => {
            data_type => 'nucl',
            mass_num  => 99,
            label     => 'mo99',
            symb      => 'Mo-99',
            name      => 'molybdenum-99',
            # Radioactive
            half_life             => 65.94,
            dec_const             => log(2) / 65.94,
            yield                 => 0,
            yield_per_microamp    => 0,
            sp_yield              => 0,
            sp_yield_per_microamp => 0,
        },
        '100' => {
            data_type      => 'nucl',
            mass_num       => 100,
            label          => 'mo100',
            symb           => 'Mo-100',
            name           => 'molybdenum-100',
            amt_frac       => 0.09744,
            mass_frac      => 0,
            molar_mass     => 99.907468,
            wgt_molar_mass => 0,
        },
    );
    #---------------------------------------------------------------------------
    # Z=43: technetium
    #---------------------------------------------------------------------------
    my %tc = (
        data_type          => 'elem',
        atomic_num         => 43,
        label              => 'tc',
        symb               => 'Tc',
        name               => 'technetium',
        mass_frac_sum      => 0,
        wgt_avg_molar_mass => 0,
        mass_nums => [
            '',
        ],
        '99' => {
            data_type => 'nucl',
            mass_num  => 99,
            label     => 'tc99',
            symb      => 'Tc-99',
            name      => 'technetium-99',
            # Radioactive
            half_life             => 2.111e5 * 365 * 24, # 211,100 years
            dec_const             => log(2) / (2.111e5 * 365 * 24),
            yield                 => 0,
            yield_per_microamp    => 0,
            sp_yield              => 0,
            sp_yield_per_microamp => 0,
        },
        '99m' => {
            data_type => 'nucl',
            mass_num  => 99,
            label     => 'tc99m',
            symb      => 'Tc-99m',
            name      => 'technetium-99m',
            # Radioactive
            half_life             => 6.01,
            dec_const             => log(2) / 6.01,
            yield                 => 0,
            yield_per_microamp    => 0,
            sp_yield              => 0,
            sp_yield_per_microamp => 0,
        },
    );
    #---------------------------------------------------------------------------
    # Z=79: gold
    #---------------------------------------------------------------------------
    my %au = (
        data_type          => 'elem',
        atomic_num         => 79,
        label              => 'au',
        symb               => 'Au',
        name               => 'gold',
        mass_frac_sum      => 0,
        wgt_avg_molar_mass => 0,
        mass_nums => [
            '197',
        ],
        '196' => {
            data_type => 'nucl',
            mass_num  => 196,
            label     => 'au196',
            symb      => 'Au-196',
            name      => 'gold-196',
            # Radioactive
            half_life             => 6.183 * 24,
            dec_const             => log(2) / (6.183 * 24),
            yield                 => 0,
            yield_per_microamp    => 0,
            sp_yield              => 0,
            sp_yield_per_microamp => 0,
        },
        '197' => {
            data_type      => 'nucl',
            mass_num       => 197,
            label          => 'au197',
            symb           => 'Au-197',
            name           => 'gold-197',
            amt_frac       => 1.00000,
            mass_frac      => 0,
            molar_mass     => 196.966570,
            wgt_molar_mass => 0,
        },
    );
    
    #===========================================================================
    # Data: Materials
    #===========================================================================
    #---------------------------------------------------------------------------
    # molybdenum metal
    #---------------------------------------------------------------------------
    my %momet = (
        data_type    => 'mat',
        label        => 'momet',
        symb         => 'Mo_{met}',
        name         => 'molybdenum metal',
        molar_mass   => 0,     # TBC
        mass_dens    => 10.28, # g cm^-3
        num_dens     => 0,     # cm^-3. TBC
        vol          => 0,     # TBP
        mass         => 0,     # TBC using 'mass_dens' and 'vol' above
        consti_elems => [ # Iteration control; values must be keys of this hash
            'mo',
        ],
        mo => {
            # Properties of the constituent elements
            # "independent" on materials
            href      => \%mo,
            # Properties of the constituent elements
            # "dependent" on materials
            # - Embedded in each material
            amt_subs  => 1, # Amount of substance (aka number of moles)
            mass_frac => 0, # TBC
            mass      => 0, # TBC
            mass_dens => 0, # TBC
            num_dens  => 0, # TBC
        },
    );
    #---------------------------------------------------------------------------
    # molybdenum(IV) oxide
    #---------------------------------------------------------------------------
    my %moo2 = (
        data_type    => 'mat',
        label        => 'moo2',
        symb         => 'MoO_{2}',
        name         => 'molybdenum dioxide',
        molar_mass   => 0,
        mass_dens    => 6.47,
        num_dens     => 0,
        vol          => 0,
        mass         => 0,
        consti_elems => [
            'mo',
            'o',
        ],
        mo => {
            href      => \%mo,
            amt_subs  => 1,
            mass_frac => 0,
            mass      => 0,
            mass_dens => 0,
            num_dens  => 0,
        },
        o => {
            href      => \%o,
            amt_subs  => 2,
            mass_frac => 0,
            mass      => 0,
            mass_dens => 0,
            num_dens  => 0,
        },
    );
    #---------------------------------------------------------------------------
    # molybdenum(VI) oxide
    #---------------------------------------------------------------------------
    my %moo3 = (
        data_type    => 'mat',
        label        => 'moo3',
        symb         => 'MoO_{3}',
        name         => 'molybdenum trioxide',
        molar_mass   => 0,
        mass_dens    => 4.69,
        num_dens     => 0,
        vol          => 0,
        mass         => 0,
        consti_elems => [
            'mo',
            'o',
        ],
        mo => {
            href      => \%mo,
            amt_subs  => 1,
            mass_frac => 0,
            mass      => 0,
            mass_dens => 0,
            num_dens  => 0,
        },
        o => {
            href      => \%o,
            amt_subs  => 3,
            mass_frac => 0,
            mass      => 0,
            mass_dens => 0,
            num_dens  => 0,
        },
    );
    #---------------------------------------------------------------------------
    # gold metal
    #---------------------------------------------------------------------------
    my %aumet = (
        data_type    => 'mat',
        label        => 'aumet',
        symb         => 'Au_{met}',
        name         => 'gold metal',
        molar_mass   => 0,
        mass_dens    => 11.34,
        num_dens     => 0,
        vol          => 0,
        mass         => 0,
        consti_elems => [
            'au',
        ],
        au => {
            href      => \%au,
            amt_subs  => 1,
            mass_frac => 0,
            mass      => 0,
            mass_dens => 0,
            num_dens  => 0,
        },
    );
    
    #===========================================================================
    # The above hashes must be registered here.
    #===========================================================================
    my %elem_hrefs = (
        o  => \%o,
        zr => \%zr,
        nb => \%nb,
        mo => \%mo,
        tc => \%tc,
        au => \%au,
    );
    my %mat_hrefs = (
        momet => \%momet,
        moo2  => \%moo2,
        moo3  => \%moo3,
        aumet => \%aumet,
    );
    my %registry = (%elem_hrefs, %mat_hrefs);
    
    #===========================================================================
    # Additional data for nuclides: Set the minimum depletion levels
    # which will be used in enrich_or_deplete().
    #===========================================================================
    foreach my $chem_dat (@hnames_ordered) {
        # Global minimum depletion level
        if (
            exists $registry{$chem_dat}{mass_nums}
            and ref $registry{$chem_dat}{mass_nums} eq ARRAY
        ) {
            printf(
                "Assigning the global minimum depletion level [%s]".
                " to [%s] isotopes...\n",
                $min_depl_lev_global,
                $registry{$chem_dat}{label},
            ) if $is_verbose;
            foreach my $mass_num (@{$registry{$chem_dat}{mass_nums}}) {
                $registry{$chem_dat}{$mass_num}{min_depl_lev} =
                    $min_depl_lev_global;
            }
        }
        
        # Local minimum depletion levels: Overwrite 'min_depl_lev's if given.
        foreach my $elem (keys %min_depl_lev_local) {
            if ($registry{$chem_dat}{label} eq $elem) {
                printf(
                    "Overwriting the global minimum depletion level of".
                    " [%s] isotopes using the local depletion levels...\n",
                    $elem,
                ) if $is_verbose;
                foreach my $mass_num (keys %{$min_depl_lev_local{$elem}}) {
                    $registry{$chem_dat}{$mass_num}{min_depl_lev} =
                        $min_depl_lev_local{$elem}{$mass_num};
                }
            }
        }
    }
    
    #===========================================================================
    # (a) & (b) Calculate the mass fractions of the isotopes of the elements
    #           using their natural abundances.
    #===========================================================================
    printf(
        "Calculating the initial mass fractions of [%s] isotopes ".
        "using their natural abundances for the [%s] material...\n",
        join(', ', @{$registry{$mat}->{consti_elems}}),
        $registry{$mat}->{label},
    ) if $is_verbose;
    
    # (a) Calculate the weighted-average molar masses of the constituent
    #     elements of the material using the natural abundances
    #     (amount fractions) of their isotopes.
    calc_consti_elem_wgt_avg_molar_masses(
        $registry{$mat},
        'amt_frac',
        $is_verbose,
    );
    
    # (b) Convert the amount fractions of the nuclides (the isotopes of
    #     the elements) to mass fractions.
    convert_fracs(
        $registry{$mat},
        'amt_to_mass',
        $is_verbose,
    );
    
    # (c) Redistribute the enrichment levels of the nuclides to reflect
    #     the enrichment of the nuclide of interest.
    # - The use of a conversion (format specifier) for $dcc_for is necessary
    #   to make the number of decimal places of the natural enrichment
    #   levels which will fill in '.._frac_bef' the same as the number of
    #   decimal places of the enrichment levels which will be passed to enri().
    #   This will in turn enable dcc = 1 at the natural enrichment level.
    #   e.g. If the mass fractions to be passed to enri() have four decimal
    #        places, here we do:
    #        0.101460216237459 of $mo{100}{mass_frac} --> 0.1015
    my $decimal_places = (split /[.]/, $enri_lev)[1];
    my $conv = '%.'.length($decimal_places).'f';
    my $dcc_for = sprintf(
        "$conv",
        $registry{$enri_nucl_elem}{$enri_nucl_mass_num}{$enri_lev_type},
    );
    enrich_or_deplete(              # e.g.
        $registry{$enri_nucl_elem}, # \%mo
        $enri_nucl_mass_num,        # '100'
        $dcc_for,                   # 0.1015
        $enri_lev_type,             # 'amt_frac'
        $depl_order,                # 'ascend'
        $is_verbose,                # 1 (boolean)
    );
    
    # (d) Convert the redistributed enrichment levels.
    #     (i)  If the amount fraction represents the enrichment level,
    #          convert the redistributed amount fractions to mass fractions.
    #     (ii) If the mass fraction represents the enrichment level,
    #          convert the redistributed mass fractions to amount fractions.
    convert_fracs(
        $registry{$mat}, # e.g. \%moo3
        (
            $enri_lev_type eq 'amt_frac' ?
                'amt_to_mass' : # Convert redistributed amt fracs to mass fracs
                'mass_to_amt'   # Convert redistributed mass fracs to amt fracs
        ),
        $is_verbose, # e.g. 1 (boolean)
    );
    
    # (e) Again calculate the weighted-average molar masses of the constituent
    #     elements, but now using the enrichment levels of their isotopes.
    #     (the enrichment level can either be 'amt_frac' or 'mass_frac'
    #     depending on the user's input)
    calc_consti_elem_wgt_avg_molar_masses(
        $registry{$mat}, # e.g. \%moo3
        $enri_lev_type,  # e.g. 'amt_frac' or 'mass_frac'
        $is_verbose,     # e.g. 1 (boolean)
    );
    
    # (f) Calculate:
    # - The molar mass of the material using the weighted-average
    #   molar masses of its constituent elements obtained in (e)
    # - Mass fractions and masses of the constituent elements using
    #   the molar mass of the material
    # - Masses of the isotopes
    #   ********************************************************************
    # - *** Most importantly, populate the 'mass_frac_bef' attribute for ***
    #   *** density change coefficient calculation in enri().               ***
    #   ********************************************************************
    printf(
        "Populating the [$enri_lev_type\_bef] attributes of [%s] ".
        "for DCC calculation...\n",
        join(', ', @{$registry{$mat}->{consti_elems}}),
    ) if $is_verbose;
    calc_mat_molar_mass_and_subcomp_mass_fracs_and_dccs(
        $registry{$mat}, # e.g. \%moo3
        $enri_lev_type,  # e.g. 'amt_frac' or 'mass_frac'
        $is_verbose,     # e.g. 1 (boolean)
        'dcc_preproc',   # Tells the routine that it's a preproc call
    );
    
    # Return a hash of chemical entity hashes.
    my %chem_hrefs;
    foreach my $hname (@hnames_ordered) {
        $chem_hrefs{$hname} = $registry{$hname} if $registry{$hname};
    }
    return \%chem_hrefs;
}


sub enri {
    # """Calculate enrichment-dependent quantities."""
    
    my(                      # e.g.
        $chem_hrefs,         # {o => \%o, mo => \%mo, momet => \%momet, ...}
        $mat,                # momet, moo2, moo3, ...
        $enri_nucl_elem,     # mo, o, ...
        $enri_nucl_mass_num, # '100', '98', ...
        $enri_lev,           # 0.9739, 0.9954, ...
        $enri_lev_type,      # 'amt_frac'
        $depl_order,         # 'ascend'
        $is_verbose,         # 1 (boolean)
    ) = @_;
    
    # (1) Redistribute the enrichment levels of the nuclides to reflect
    #     the enrichment of the nuclide of interest.
    my $is_exit = enrich_or_deplete(    # e.g.
        $chem_hrefs->{$enri_nucl_elem}, # \%mo
        $enri_nucl_mass_num,            # '100'
        $enri_lev,                      # 0.9739
        $enri_lev_type,                 # 'amt_frac'
        $depl_order,                    # 'ascend'
        $is_verbose,                    # 1 (boolean)
    );
    return $is_exit if $is_exit; # Use it as a signal "not" to accumulate data.
    
    # (2) Convert the redistributed enrichment levels.
    convert_fracs(              # e.g.
        $chem_hrefs->{$mat},    # \%moo3
        (
            $enri_lev_type eq 'amt_frac' ?
                'amt_to_mass' : # Convert redistributed amt fracs to mass fracs
                'mass_to_amt'   # Convert redistributed mass fracs to amt fracs
        ),
        $is_verbose,            # 1 (boolean)
    );
    
    # (3) Calculate the weighted-average molar masses of the constituent
    #     elements using the enrichment levels of their isotopes.
    calc_consti_elem_wgt_avg_molar_masses(
        $chem_hrefs->{$mat}, # \%moo3
        $enri_lev_type,      # 'amt_frac' or 'mass_frac'
        $is_verbose,         # 1 (boolean)
    );
    
    # (4) Calculate:
    # - The molar mass of the material using the weighted-average
    #   molar masses of its constituent elements obtained in (3)
    # - Mass fractions and masses of the constituent elements using
    #   the molar mass of the material
    # - Masses of the isotopes
    #   ******************************************************************
    # - *** Most importantly, density change coefficients of the isotopes ***
    #   ******************************************************************
    calc_mat_molar_mass_and_subcomp_mass_fracs_and_dccs(
        $chem_hrefs->{$mat}, # \%moo3
        $enri_lev_type,      # 'amt_frac' or 'mass_frac'
        $is_verbose,         # 1 (boolean)
    );
    
    # (5) Calculate:
    # - Number density of the material
    # - Mass and number densities of the constituent elements and
    #   their isotopes
    calc_mass_dens_and_num_dens(
        $chem_hrefs->{$mat}, # \%moo3
        $enri_lev_type,      # 'amt_frac' or 'mass_frac'
        $is_verbose,         # 1 (boolean)
    );
    
    return;
}


sub enri_postproc {
    # """Postprocessor for enri()"""
    
    my(
        $chem_hrefs,           # e.g.
        $mat,                  # 'moo3'
        $enri_nucl,            # 'mo100'
        $enri_lev,             # 0.9739, 0.9954, ...
        $enri_lev_range_first, # 0.0000
        $enri_lev_range_last,  # 0.9739
        $enri_lev_type,        # 'amt_frac'
        $depl_order,           # 'ascend'
        $out_path,             # './mo100'
        $projs,                # ['g', 'n', 'p']
        $precision_href,
        $is_verbose,           # 1 (boolean)
    ) = @_;
    
    # (6) Adjust the number of decimal places of calculation results.
    adjust_num_of_decimal_places(
        $chem_hrefs,
        $precision_href,
        $enri_lev_range_first,
    );
    
    # (7) Associate product nuclides with nuclear reactions and DCCs.
    assoc_prod_nucls_with_reactions_and_dccs(
        $chem_hrefs,
        $mat,
        $enri_nucl,
        $enri_lev,
        $enri_lev_range_first,
        $enri_lev_range_last,
        $enri_lev_type,
        $depl_order,
        $out_path,
        $projs,
        $is_verbose,
    );
    
    return;
}
#-------------------------------------------------------------------------------


sub parse_argv {
    # """@ARGV parser"""
    
    my(
        $argv_aref,
        $cmd_opts_href,
        $run_opts_href,
    ) = @_;
    my %cmd_opts = %$cmd_opts_href; # For regexes
    
    # Parser: Overwrite default run options if requested by the user.
    my $field_sep = ',';
    foreach (@$argv_aref) {
        # Mo materials
        if (/$cmd_opts{mats}/) {
            s/$cmd_opts{mats}//;
            if (/\ball\b/i) {
                @{$run_opts_href->{mats}} = qw(momet moo2 moo3);
            }
            else {
                @{$run_opts_href->{mats}} = split /$field_sep/;
            }
        }
        
        # Mo isotope to be enriched
        if (/$cmd_opts{enri_nucl}/) {
            ($run_opts_href->{enri_nucl} = $_) =~ s/$cmd_opts{enri_nucl}//;
        }
        
        # Fraction type to denote the enrichment level
        if (/$cmd_opts{enri_lev_type}/) {
            ($run_opts_href->{enri_lev_type} = $_) =~
                s/$cmd_opts{enri_lev_type}//;
            unless ($run_opts_href->{enri_lev_type} =~ /\b(amt|mass)_frac\b/) {
                croak "[$run_opts_href->{enri_lev_type}] is invalid;".
                      " type [amt_frac] or [mass_frac].\n";
            }
        }
        
        # Range of enrichment levels
        if (/$cmd_opts{enri_lev_range}/) {
            s/$cmd_opts{enri_lev_range}//;
            @{$run_opts_href->{enri_lev_range}} = split /$field_sep/;
        }
        
        # Global minimum depletion level
        if (/$cmd_opts{min_depl_lev_global}/) {
            ($run_opts_href->{min_depl_lev_global} = $_) =~
                s/$cmd_opts{min_depl_lev_global}//;
        }
        
        # Depletion order
        if (/$cmd_opts{depl_order}/) {
            ($run_opts_href->{depl_order} = $_) =~
                s/$cmd_opts{depl_order}//;
        }
        
        # Input file
        if (/$cmd_opts{inp}/) {
            ($run_opts_href->{inp} = $_) =~
                s/$cmd_opts{inp}//;
        }
        
        # Output path
        if (/$cmd_opts{out_path}/) {
            s/$cmd_opts{out_path}//;
            ($run_opts_href->{out_path} = $_) =~
                s/$cmd_opts{out_path}//;
        }
        
        # Output formats
        if (/$cmd_opts{out_fmts}/) {
            s/$cmd_opts{out_fmts}//;
            if (/\ball\b/i) {
                @{$run_opts_href->{out_fmts}} = qw(dat tex csv xlsx json yaml);
            }
            else {
                @{$run_opts_href->{out_fmts}} = split /$field_sep/;
            }
        }
        
        # Projectiles
        if (/$cmd_opts{projs}/) {
            s/$cmd_opts{projs}//;
            if (/\ball\b/i) {
                @{$run_opts_href->{projs}} = qw(g n p);
            }
            else {
                @{$run_opts_href->{projs}} = split /$field_sep/;
            }
        }
        
        # Calculation processes will be displayed.
        if (/$cmd_opts{verbose}/) {
            $run_opts_href->{is_verbose} = 1;
        }
        
        # The front matter won't be displayed at the beginning of the program.
        if (/$cmd_opts{nofm}/) {
            $run_opts_href->{is_nofm} = 1;
        }
        
        # The shell won't be paused at the end of the program.
        if (/$cmd_opts{nopause}/) {
            $run_opts_href->{is_nopause} = 1;
        }
    }
    
    return;
}


sub parse_inp {
    # """Input file parser"""
    
    my $run_opts_href = shift;
    
    # Parser: Overwrite default run options if requested by the input file.
    my %seps = (
        key_val    => qr/\s*=\s*/,
        key_subkey => qr/\s*[.]\s*/,
    );
    open my $inp_fh, '<', $run_opts_href->{inp};
    foreach (<$inp_fh>) {
        chomp();
        next if /^\s*$/; # Skip a blank line.
        next if /^\s*#/; # Skip a comment line.
        s/^\s+//;        # Suppress leading blanks.
        s/\s*#.*//;      # Suppress a trailing comment.
        
        # Local minimum depletion levels
        # e.g. [min_depl_lev_local.mo.92 = 0.00005] in the input file
        #      => [$run_opts_href->{min_depl_lev_local}{mo}{92} = 0.00005;] here
        if (/min_depl_lev_local/i) {
            my($key, $val) = (split /$seps{key_val}/)[0, 1];
            (my $subkey = $key) =~ s/min_depl_lev_local$seps{key_subkey}//;
            my($elem, $mass_num) = (split /$seps{key_subkey}/, $subkey)[0, 1];
            
            $run_opts_href->{min_depl_lev_local}{$elem}{$mass_num} = $val;
        }
        
        # Calculation precision
        if (/precision/i) {
            my($key, $val) = (split /$seps{key_val}/)[0, 1];
            (my $subkey = $key) =~ s/precision$seps{key_subkey}//;
            
            $run_opts_href->{precision_href}{$subkey} = $val;
        }
    }
    close $inp_fh;
    
    return;
}


sub outer_enri {
    # """enrimo outer layer"""
    
    my $run_opts_href  = shift;
    my $prog_info_href = shift;
    my $chem_hrefs = {};
    my $out_arefs  = {};
    
    foreach my $mat (@{$run_opts_href->{mats}}) {
        # Prepare DCC calculation data.
        $chem_hrefs = enri_preproc(
            {
                hnames => [ # Names of chemical entity hashes
                    'o',
                    'mo',
                    'momet',
                    'moo2',
                    'moo3',
                ],
                dcc_preproc => { # Keys: strings
                    mat                => $mat,
                    enri_nucl_elem     => $run_opts_href->{enri_nucl_elem},
                    enri_nucl_mass_num => $run_opts_href->{enri_nucl_mass_num},
                    # Below is used only for decimal places calculation;
                    # use any of the enrichment levels.
                    enri_lev => $run_opts_href->{enri_lev_range}[-1],
                },
                enri_lev_type       => $run_opts_href->{enri_lev_type},
                min_depl_lev_global => $run_opts_href->{min_depl_lev_global},
                min_depl_lev_local  => $run_opts_href->{min_depl_lev_local},
                depl_order          => $run_opts_href->{depl_order},
                is_verbose          => $run_opts_href->{is_verbose},
            },
        );
        
        printf(
            "\n%s\n[%s]\n%s\n",
            '=' x 70,
            join('::', (caller(0))[3]),
            '=' x 70,
        );
        printf(
            "Mo material: [%s]\n",
            $mat,
        );
        printf(
            "Mo-%s enrichment levels: [%s..%s]\n",
            $run_opts_href->{enri_nucl_mass_num},
            $run_opts_href->{enri_lev_range}[0],
            $run_opts_href->{enri_lev_range}[-1],
        );
        foreach my $enri_lev (@{$run_opts_href->{enri_lev_range}}) {
            say "Running at [$enri_lev]..."
                if $run_opts_href->{is_verbose};
            inner_enri(
                $chem_hrefs,
                $out_arefs,
                $mat,
                $run_opts_href->{enri_nucl},
                $run_opts_href->{enri_nucl_elem},
                $run_opts_href->{enri_nucl_mass_num},
                $enri_lev,
                $run_opts_href->{enri_lev_range}[0],
                $run_opts_href->{enri_lev_range}[-1],
                $run_opts_href->{enri_lev_type},
                $run_opts_href->{depl_order},
                $run_opts_href->{out_path},
                $run_opts_href->{projs},
                $run_opts_href->{precision_href},
                $run_opts_href->{is_verbose},
            );
        }
        
        write_to_data_files(
            $run_opts_href,
            $prog_info_href,
            $chem_hrefs,
            $out_arefs,
            $mat,
            $run_opts_href->{enri_nucl},
            $run_opts_href->{enri_nucl_elem},
            $run_opts_href->{enri_nucl_mass_num},
            $run_opts_href->{enri_lev_type},
            $run_opts_href->{depl_order},
        );
    }
    
    return;
}


sub inner_enri {
    # """enrimo inner layer"""
    
    my(
        $chem_hrefs,
        $out_arefs,
        $mat,
        $enri_nucl,
        $enri_nucl_elem,
        $enri_nucl_mass_num,
        $enri_lev,
        $enri_lev_range_first,
        $enri_lev_range_last,
        $enri_lev_type,
        $depl_order,
        $out_path,
        $projs,
        $precision_href,
        $is_verbose,
    ) = @_;
    
    # (1)--(5)
    # Redistribute the fraction quantities of Mo isotopes and
    # calculate DCCs.
    my $is_exit = enri(      # e.g.
        $chem_hrefs,         # {o => %o, mo => \%mo, momet => \%momet, ...}
        $mat,                # momet, moo2, moo3, ...
        $enri_nucl_elem,     # mo
        $enri_nucl_mass_num, # '100', '98', ...
        $enri_lev,           # 0.9739, 0.9954, ...
        $enri_lev_type,      # 'amt_frac'
        $depl_order,         # 'ascend'
        $is_verbose,
    );
    return if $is_exit;
    
    # (6)--(7)
    # Adjust the numbers of decimal places and associate
    # product nuclides with nuclear reactions and DCCs.
    enri_postproc(
        $chem_hrefs,
        $mat,
        $enri_nucl,
        $enri_lev,
        $enri_lev_range_first,
        $enri_lev_range_last,
        $enri_lev_type,
        $depl_order,
        $out_path,
        $projs,
        $precision_href,
        $is_verbose,
    );
    
    # (8) Construct row-wise data for write_to_data_files().
    $out_arefs->{$mat} = []
        if not exists $out_arefs->{$mat};
    push @{$out_arefs->{$mat}},
        $chem_hrefs->{$mat}{$enri_nucl}{$enri_lev_type},
        $chem_hrefs->{$mat}{$enri_nucl}{amt_frac},
        $chem_hrefs->{$mat}{$enri_nucl}{mass_frac},
        $chem_hrefs->{$mat}{mo}{mass_frac},
        $chem_hrefs->{$mat}{mass_dens},
        $chem_hrefs->{$mat}{num_dens},
        $chem_hrefs->{$mat}{mo}{mass_dens},
        $chem_hrefs->{$mat}{mo}{num_dens},
        $chem_hrefs->{$mat}{$enri_nucl}{mass_dens},
        $chem_hrefs->{$mat}{$enri_nucl}{num_dens},
        $chem_hrefs->{$mat}{mo92}{dcc},
        $chem_hrefs->{$mat}{mo94}{dcc},
        $chem_hrefs->{$mat}{mo95}{dcc},
        $chem_hrefs->{$mat}{mo96}{dcc},
        $chem_hrefs->{$mat}{mo97}{dcc},
        $chem_hrefs->{$mat}{mo98}{dcc},
        $chem_hrefs->{$mat}{mo100}{dcc},
        $chem_hrefs->{$mat}{o16}{dcc},
        $chem_hrefs->{$mat}{o17}{dcc},
        $chem_hrefs->{$mat}{o18}{dcc};
    
    return;
}


sub write_to_data_files {
    # """Write the calculation results to data files."""
    my(
        $run_opts_href,
        $prog_info_href,
        $chem_hrefs,
        $out_arefs,
        $mat,
        $enri_nucl,
        $enri_nucl_elem,
        $enri_nucl_mass_num,
        $enri_lev_type,
        $depl_order,
    ) = @_;
    my %mo     = %{$chem_hrefs->{mo}};
    my %o      = %{$chem_hrefs->{o}};
    my %mo_mat = %{$chem_hrefs->{$mat}};
    my %terms = (
        el => {
            abbr => 'EL',
            full => 'enrichment level',
        },
        af => {
            abbr => 'AF',
            full => 'amount fraction',
        },
        mf => {
            abbr => 'MF',
            full => 'mass fraction',
        },
        md => {
            abbr => 'MD',
            full => 'mass density',
        },
        nd => {
            abbr => 'ND',
            full => 'number density',
        },
        dcc => {
            abbr => 'DCC',
            full => 'density change coefficient',
        },
    );
    $run_opts_href->{out_path} = "./$enri_nucl"
        if not $run_opts_href->{out_path};
    (my $from = $out_arefs->{$mat}[0]) =~ s/[.]/p/;
    (my $to = $chem_hrefs->{$mat}{$enri_nucl}{$enri_lev_type}) =~ s/[.]/p/;
    my $rpt_bname = sprintf(
        "%s_%s_%s_%s_%s_%s",
        $mat,
        $enri_nucl,
        $enri_lev_type,
        $from,
        $to,
        (
            $depl_order =~ /asc/i  ? 'asc' :
            $depl_order =~ /desc/i ? 'desc' :
                                     'rand'
        ),
    );
    
    reduce_data(
        { # Settings
            rpt_formats => $run_opts_href->{out_fmts},
            rpt_path    => $run_opts_href->{out_path},
            rpt_bname   => $rpt_bname,
            begin_msg   => "collecting data info...",
            prog_info   => $prog_info_href,
            cmt_arr     => [
                # Calculation conditions
                "-" x 69,
                " Calculation conditions",
                "-" x 69,
                " Mo material:           $mo_mat{symb}",
                " Enriched Mo isotope:   $mo{$enri_nucl_mass_num}{symb}",
                " Enrichment level type: $enri_lev_type",
                "-" x 69,
                # Minimum depletion levels
                "-" x 69,
                " Minimum depletion levels ($enri_lev_type)",
                "-" x 69,
                " $mo{92}{symb}:  $mo{92}{min_depl_lev}",
                " $mo{94}{symb}:  $mo{94}{min_depl_lev}",
                " $mo{95}{symb}:  $mo{95}{min_depl_lev}",
                " $mo{96}{symb}:  $mo{96}{min_depl_lev}",
                " $mo{97}{symb}:  $mo{97}{min_depl_lev}",
                " $mo{98}{symb}:  $mo{98}{min_depl_lev}",
                " $mo{100}{symb}: $mo{100}{min_depl_lev}",
                "-" x 69,
                # Abbreviations
                "-" x 69,
                " List of abbreviations",
                "-" x 69,
                " $terms{el}{abbr}:  $terms{el}{full}",
                " $terms{af}{abbr}:  $terms{af}{full}",
                " $terms{mf}{abbr}:  $terms{mf}{full}",
                " $terms{md}{abbr}:  $terms{md}{full}",
                " $terms{nd}{abbr}:  $terms{nd}{full}",
                " $terms{dcc}{abbr}: $terms{dcc}{full}",
                "-" x 69,
            ],
        },
        { # Columnar
            size  => 20, # For column size validation
            heads => [
                "$terms{el}{abbr} of $mo{$enri_nucl_mass_num}{symb}",
                "$terms{af}{abbr} of $mo{$enri_nucl_mass_num}{symb}",
                "$terms{mf}{abbr} of $mo{$enri_nucl_mass_num}{symb}",
                "$terms{mf}{abbr} of $mo{symb}",
                "$terms{md}{abbr} of $mo_mat{symb}",
                "$terms{nd}{abbr} of $mo_mat{symb}",
                "$terms{md}{abbr} of $mo{symb}",
                "$terms{nd}{abbr} of $mo{symb}",
                "$terms{md}{abbr} of $mo{$enri_nucl_mass_num}{symb}",
                "$terms{nd}{abbr} of $mo{$enri_nucl_mass_num}{symb}",
                "$terms{dcc}{abbr} of $mo{92}{symb}",
                "$terms{dcc}{abbr} of $mo{94}{symb}",
                "$terms{dcc}{abbr} of $mo{95}{symb}",
                "$terms{dcc}{abbr} of $mo{96}{symb}",
                "$terms{dcc}{abbr} of $mo{97}{symb}",
                "$terms{dcc}{abbr} of $mo{98}{symb}",
                "$terms{dcc}{abbr} of $mo{100}{symb}",
                "$terms{dcc}{abbr} of $o{16}{symb}",
                "$terms{dcc}{abbr} of $o{17}{symb}",
                "$terms{dcc}{abbr} of $o{18}{symb}",
            ],
            subheads => [
                "($enri_lev_type)",
                "",
                "",
                "",
                "(g cm^{-3})",
                "(cm^{-3})",
                "(g cm^{-3})",
                "(cm^{-3})",
                "(g cm^{-3})",
                "(cm^{-3})",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
            ],
            data_arr_ref => $out_arefs->{$mat},
#            sum_idx_multiples         => [3..5], # Can be discrete,
#            ragged_left_idx_multiples => [2..5], # but must be increasing
            freeze_panes => 'C4', # Alt: {row => 2,  col => 3}
            space_bef => {dat => " ", tex => " "},
            heads_sep => {dat => "|", csv => ","},
            space_aft => {dat => " ", tex => " "},
            data_sep  => {dat => " ", csv => ","},
        }
    );
    
    return;
}


sub enrimo {
    # """enrimo main routine"""
    
    if (@ARGV) {
        my %prog_info = (
            titl       => basename($0, '.pl'),
            expl       => 'Investigate the influence of an enriched Mo isotope',
            vers       => $VERSION,
            date_last  => $LAST,
            date_first => $FIRST,
            auth       => {
                name => 'Jaewoong Jang',
                posi => 'PhD student',
                affi => 'University of Tokyo',
                mail => 'jan9@korea.ac.kr',
            },
        );
        my %cmd_opts = ( # Command-line opts
            mats                => qr/-?-mat(?:erial)?s\s*=\s*/i,
            enri_nucl           => qr/-?-(?:nucl|(?:isot(?:ope)?))\s*=\s*/i,
            enri_lev_type       => qr/-?-(?:enri_lev_)?type\s*=\s*/i,
            enri_lev_range      => qr/-?-(?:enri_lev_)?range\s*=\s*/i,
            min_depl_lev_global => qr/-?-(?:min_depl_)?global\s*=\s*/i,
            depl_order          => qr/-?-(?:depl_)?order\s*=\s*/i,
            inp                 => qr/-?-i(?:np)?\s*=\s*/i,
            out_fmts            => qr/-?-o(?:ut)?(?:_fmts)?\s*=\s*/i,
            projs               => qr/-?-proj(?:ectile)?s\s*=\s*/i,
            out_path            => qr/-?-(?:out_)?path\s*=\s*/i,
            verbose             => qr/-?-verb(?:ose)?/i,
            nofm                => qr/-?-nofm/i,
            nopause             => qr/-?-nopause/i,
        );
        my %run_opts = ( # Program run opts
            mats                => ['momet'],
            enri_nucl           => 'mo100',
            enri_lev_type       => 'amt_frac',
            enri_lev_range      => [0, 0.0001, 1],
            min_depl_lev_global => 0.0000,
            min_depl_lev_local  => {},
            precision_href      => {},
            depl_order          => 'ascend', # ascend, descend, random
            inp                 => '',
            out_fmts            => ['dat', 'xlsx'],
            projs               => [],
            out_path            => '', # If remains empty, enri_nucl'll be used
            is_verbose          => 0,
            is_nofm             => 0,
            is_nopause          => 0,
        );
        
        # ARGV validation and parsing
        validate_argv(\@ARGV, \%cmd_opts);
        parse_argv(\@ARGV, \%cmd_opts, \%run_opts);
        parse_inp(\%run_opts) if $run_opts{inp};
        construct_range($run_opts{enri_lev_range});
        ($run_opts{enri_nucl_elem} = $run_opts{enri_nucl}) =~ s/[^a-zA-Z]//g;
        ($run_opts{enri_nucl_mass_num} = $run_opts{enri_nucl}) =~ s/[^0-9]//g;
        
        # Notification - beginning
        show_front_matter(\%prog_info, 'prog', 'auth', 'no_trailing_blkline')
            unless $run_opts{is_nofm};
        
        # Main
        outer_enri(\%run_opts, \%prog_info);
        
        # Notification - end
        show_elapsed_real_time("\n");
        pause_shell() unless $run_opts{is_nopause};
    }
    
    system("perldoc \"$0\"") if not @ARGV;
    
    return;
}


enrimo();
__END__

=head1 NAME

enrimo - Investigate the influence of an enriched Mo isotope

=head1 SYNOPSIS

    perl enrimo.pl [-materials=mo_mat ...] [-isotope=mo_isot]
                   [-enri_lev_type=frac_type] [-enri_lev_range=frac_range]
                   [-min_depl_lev_global=enri_lev] [-depl_order=option]
                   [-inp=fname] [-out_path=path] [-out_fmts=ext ...]
                   [-projectiles=particle ...]
                   [-verbose] [-nofm] [-nopause]

=head1 DESCRIPTION

    This Perl program generates datasets for investigating the influence of
    an enriched Mo isotope on its associated Mo material, Mo element,
    and companion isotopes.
    The following quantities, as functions of the enrichment level of
    the Mo isotope to be enriched, are calculated for a Mo material:
    - Amount fractions and and mass fractions of Mo and O isotopes
    - Mass fractions of Mo and O elements
    - Mass and number densities of the Mo material, Mo and O elements,
      and their isotopes
    - Density change coefficients (DCCs) of Mo and O isotopes

=head1 OPTIONS

    Multiple values are separated by the comma (,).

    -materials=mo_mat ... (short: -mats, default: momet)
        all
            All of the following mo_mat's.
        momet
            Mo metal
        moo2
            Mo(IV) oxide (aka Mo dioxide)
        moo3
            Mo(VI) oxide (aka Mo trioxide)

    -isotope=mo_isot (short: -isot, default: mo100)
        Mo isotope to be enriched.
        mo92
        mo94
        mo95
        mo96
        mo97
        mo98  <= Mo-98(n,g)Mo-99
        mo100 <= Mo-100(g,n)Mo-99, Mo-100(n,2n)Mo-99, Mo-100(p,2n)Tc-99m

    -enri_lev_type=frac_type (short: -type, default: amt_frac)
        The fraction type to refer to the enrichment level.
        amt_frac
        mass_frac

    -enri_lev_range=frac_range (short: -range, default: 0,0.0001,1)
        The range of enrichment levels to be examined.
        e.g. 0.1,0.5     (beg,end; incre is automatically determined)
        e.g. 0,0.001,1   (beg,incre,end)
        e.g. 0,0.00001,1 (beg,incre,end)

    -min_depl_lev_global=enri_lev (short: -global, default: 0.0000)
        The minimum depletion level that applies to all the nuclides
        associated with the designated Mo materials. Overridden, if given,
        by nuclide-specific minimum depletion levels.
        e.g. 0.0007

    -depl_order=option (short: -order, default: ascend)
        The order in which the Mo isotopes other than the to-be-enriched one
        will be depleted.
        ascend (short: asc)
            Ascending order of mass number
        descend (short: desc)
            Descending order of mass number
        random (short: rand, alt: shuffle)
            Random order

    -inp=fname (short: -i)
        An input file specifying the nuclide-specific minimum depletion levels
        and the calculation precision. See the sample input file for the syntax.
        e.g. 0p9739.enr

    -out_path=path (short: -path, default: the value of -isotope)
        Path for the output files.

    -out_fmts=ext ... (short: -o, default: dat,xlsx)
        Output file formats.
        all
            All of the following ext's.
        dat
            Plain text
        tex
            LaTeX tabular environment
        csv
            comma-separated value
        xlsx
            Microsoft Excel 2007
        json
            JavaScript Object Notation
        yaml
            YAML

    -projectiles=particle ... (short: -projs, default: none)
        Reaction projectiles for associating the product nuclides with DCCs.
        If designated, the relevant reporting files are generated
        in addition to the default output files.
        all
            All of the following particles.
        g
            Photon <= Mo-100(g,n)Mo-99
        n
            Neutron <= Mo-98(n,g)Mo-99, Mo-100(n,2n)Mo-99
        p
            Proton <= Mo-100(p,2n)Tc-99m

    -verbose (short: -verb)
        Display the calculation process in real time. This will pause
        the shell each time a core calculation routine is called; use it
        only when debugging or checking part of the calculation process.

    -nofm
        The front matter will not be displayed at the beginning of program.

    -nopause
        The shell will not be paused at the end of program.
        Use it for a batch run.

=head1 EXAMPLES

    perl enrimo.pl -type=mass_frac -range=0,0.00001,1
    perl enrimo.pl -mats=moo3 -global=0.0005 -verb
    perl enrimo.pl -mats=momet,moo3 -range=0.0974,0.0001,0.9739 -inp=0p9739.enr

=head1 REQUIREMENTS

    Perl 5
        Text::CSV, Excel::Writer::XLSX, JSON, YAML

=head1 SEE ALSO

L<enrimo on GitHub|https://github.com/jangcom/enrimo>

=head1 AUTHOR

Jaewoong Jang <jan9@korea.ac.kr>

=head1 COPYRIGHT

Copyright (c) 2018-2019 Jaewoong Jang

=head1 LICENSE

This software is available under the MIT license;
the license information is found in 'LICENSE'.

=cut
