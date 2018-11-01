#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use DateTime;
use autodie        qw(open close chdir mkdir binmode);
use feature        qw(say state);
use Data::Dump     qw(dump);
use List::Util     qw(first);
use Carp           qw(croak);
use Cwd            qw(getcwd);
use File::Basename qw(basename);
use File::Copy     qw(copy);
use constant PI     => 4 * atan2(1, 1);
use constant ARRAY  => ref [];
use constant HASH   => ref {};
use constant SCALAR => ref \$0;


#
# Outermost lexicals
#
my %prog_info = (
    titl        => basename($0, '.pl'),
    expl        => 'Examine the influence of an enriched/depleted Mo isotope',
    vers        => 'v1.0.0',
    date_last   => '2018-10-02',
    date_first  => '2018-09-21',
    opts        => { # Command options
        target    => qr/-tar(?:get)?=/i,
        isot      => qr/-isot(?:ope)?=/i,
        enri      => qr/-enri?=/i,
        dcc_init  => qr/-dcc(?:_init)?=/i,
        verbose   => qr/-verb(?:ose)?/i,
        yield_for => qr/-yield(?:_for)?=/i,
        pwm_for   => qr/-pwm(?:_for)?=/i,
        overwrite => qr/-over(?:write)?/i,
        nopause   => qr/-nop(?:ause)?/i,
    },
    auth        => {
        name => 'Jaewoong Jang',
        posi => 'PhD student',
        affi => 'University of Tokyo',
        mail => 'jang.comsci@gmail.com',
    },
    usage       => <<'    END_HEREDOC'
    NAME
        enrimo - Examine the influence of an enriched/depleted Mo isotope

    SYNOPSIS
        perl enrimo.pl [-target=mo_tar ...] [-isotope=mass_num] [-enri=range]
                       [-dcc_init=enri] [-verbose]
                       [-yield_for=file] [-pwm_for=enri ...] [-overwrite]
                       [-nopause]

    DESCRIPTION
        This program generates data files for investigating the influence of
        an enriched or depleted Mo isotope on Mo targets and elemental Mo.
        The following quantities, as functions of the enrichment ratio (i.e.
        the mass fraction) of the Mo isotope of interest, are generated
        for each of the Mo targets designated:
        - Mass fraction of elemental Mo
        - Mass and number densities of the Mo target in question
          and the associated elemental Mo and the Mo isotope of interest
        - Yield and specific yield of the product radionuclide

    OPTIONS
        Value separator: the comma (,)
        -target=mo_tar (default: momet)
            all
                All of the following mo_tar's.
            momet
                Metallic Mo.
            moo2
                Mo(IV) oxide (aka Mo dioxide).
            moo3
                Mo(VI) oxide (aka Mo trioxide).
        -isotope=mass_num (default: 100)
            92
            94
            95
            96
            97
            98  <= Mo-98(n,g)Mo-99
            100 <= Mo-100(g,n)Mo-99, Mo-100(n,2n)Mo-99, Mo-100(p,2n)Tc-99m
        -enri=range (default: 0,0.01,1)
            A range of the enrichment ratios.
            e.g. 0.1,0.5    (beg,end; incre is automatically determined)
            e.g. 0,0.001,1  (beg,incre,end)
            e.g. 0,0.0001,1 (beg,incre,end)
        -dcc_init=enri (default: 0.01)
            The initial mass fraction of the Mo isotope of interest,
            with which density change coefficients (DCCs) will be calculated
            for the enrichment ratios designated.
            The number of decimal places must be the same as -enri=range.
            For example:
            (Valid)   -enri=0,0.0001,1 -dcc_init=0.1015
            (Invalid) -enri=0,0.001,1  -dcc_init=0.1015
        -verbose
            Display the process of isotopic enrichment and
            its effects in real time.
        -yield_for=file
            An input file describing yield calculation conditions.
            Sample files: gn.enr, n2n.enr, p2n.enr
        -pwm_for=enri
            Generate pointwise (or energywise) multiplication reporting files
            for the designated enrichment ratios.
            Ignored if -yield_for= has not been given a filename.
        -overwrite
            Overwrite existing interpolated xs and MC fluence files.
            Ignored if -yield_for= has not been given a filename.
        -nopause
            The shell is not paused at the end of the program.
            You may want to use it for a batch run.

    EXAMPLES
        perl enrimo.pl -target=moo3 -enri=0,0.01,1 -verbose
        perl enrimo.pl -target=moo3 -enri=0,0.0001,1 -dcc_init=0.1015
        perl enrimo.pl -target=momet,moo2
        perl enrimo.pl -target=moo3 -isotope=98 -enri=0,0.001,1 -dcc_init=0.102
        perl enrimo.pl -yield_for=n2n.enr -enri=0,0.001,1 -dcc_init=0.102
        perl enrimo.pl -target=all -yield_for=gn.enr -pwm_for=0.1,0.95
        perl enrimo.pl -yield_for=gn.enr -enri=0,0.0001,1 -pwm_for=0.1014,0.95

    REQUIREMENTS
        Perl 5, gnuplot, PHITS

    SEE ALSO
        perl(1), gnuplot(1)

    AUTHOR
        Jaewoong Jang <jang.comsci@gmail.com>

    COPYRIGHT
        Copyright (c) 2018 Jaewoong Jang

    LICENSE
        This software is available under the MIT license;
        the license information is found in 'LICENSE'.
    END_HEREDOC
);
my %datetimes     = construct_timestamps();
my $tstamp_of_int = $datetimes{ymdhms};
my %seps = (
    field => ',',
);
my %consts = (
    avogadro  => 6.02214076e+23, # mol^-1
    micro_amp => 6.24150934e+12, # Number of charged particles per second
    barn      => 1e-24,          # cm^2
);
my %format_specifiers = (
    # Parsed at adjust_num_of_decimal_places()
    molar_mass     => '%.5f',
    wgt_molar_mass => '%.5f',
    avg_molar_mass => '%.5f',
    mole_frac      => '%.5f',
    mass_frac      => '%.5f',
    mass_dens      => '%.5f',
    num_dens       => '%.5e',
    # Directly used at calc_mo_tar_avg_molar_mass_and_its_subcomp_mass_fracs
    dcc            => '%.4f',
    # Yield-specific
    yield          => '%.5f',
    mass           => '%.5f',
    sp_yield       => '%.5f',
    # Directly used at calc_yield_and_specific_yield()
    erg_ev         => '%.5e',
    erg_mega_ev    => '%.5f',
    xs_micro       => '%.5e',
    xs_macro       => '%.5e',
    mc_flues       => '%.5e',
    pwm_micro      => '%.5e',
    pwm_macro      => '%.5e',
    beam_curr      => '%.5f',
    source_rate    => '%.5e',
    vol            => '%.5f',
    reaction_rate  => '%.5e',
);
my(%mo, %tc, %o);
my(%momet, %moo2, %moo3);
my %mo_targets = (
    momet => \%momet,
    moo2  => \%moo2,
    moo3  => \%moo3,
);
my %data_array_refs = ( # Must contain the same keys as %mo_targets
    momet => [],
    moo2  => [],
    moo3  => [],
);
# For yield calculation
my(%wmet, %graphite);
my %converters = (
    wmet     => \%wmet,
    graphite => \%graphite,
);
my %mc_flues = ( # Must contain the same keys as %mo_targets
    erg   => {ev   => [], mega_ev => []},
    momet => [],
    moo2  => [],
    moo3  => [],
);
my %xs =(
    erg   => {ev   => [], mega_ev => []},
    micro => {barn => [], 'cm^2'  => []},
    macro => {            'cm^-1' => []}, # macro barn not needed
);
my %pwm = ( # Must contain the same keys as %mo_targets
    momet => {},
    moo2  => {},
    moo3  => {},
);
my %memorized;
my %dcc;
# For command-line options
my @mo_targets_of_int = ('momet');
my $mo_isot_of_int    = 100;
my @enris_of_int      = (0, 0.01, 1);
my $dcc_init          = 0.10; # wrto the default 0.01 of @enris_of_int
my $is_verbose        = 0;
my $yield_for         = '';
my %pwm_enris_of_int  = (user => [], matched => []);
my $is_overwrite      = 0;
my $is_nopause        = 0;
my %calc_conds;
my $where_prog_began  = getcwd();


#
# Subroutine calls
#
if (@ARGV) {
    show_front_matter(\%prog_info, 'prog', 'auth');
    validate_argv(\%prog_info, \@ARGV);
    parse_argv();
    enrimo();
}
elsif (not @ARGV) {
    show_front_matter(\%prog_info, 'usage');
}
show_elapsed_real_time("\n");
pause_shell() unless $is_nopause;


#
# Subroutine definitions
#
sub parse_argv {
    my @_argv = @ARGV;
    
    # Overwrite default run variables if requested by the user.
    foreach (@_argv) {
        # Mo targets of interest == Keys of %mo_targets
        if (/$prog_info{opts}{target}/) {
            s/$prog_info{opts}{target}//;
            if (/\ball\b/i) {
                @mo_targets_of_int = ('momet', 'moo2', 'moo3');
            }
            else {
                @mo_targets_of_int = split /$seps{field}/;
            }
        }
        # Mo isotope of interest
        if (/$prog_info{opts}{isot}/) {
            ($mo_isot_of_int = $_) =~ s/$prog_info{opts}{isot}//;
        }
        # Mo isotope enrichment ratios
        if (/$prog_info{opts}{enri}/) {
            s/$prog_info{opts}{enri}//;
            @enris_of_int = split /$seps{field}/;
        }
        # The initial mass density of the Mo isotope of interest
        # with which DCCs will be calculated.
        if (/$prog_info{opts}{dcc_init}/) {
            s/$prog_info{opts}{dcc_init}//;
            $dcc_init = $_;
        }
        # Display mass fraction redistribution in real time.
        if (/$prog_info{opts}{verbose}/) {
            $is_verbose = 1;
        }
        # Description file for yield calculation
        if (/$prog_info{opts}{yield_for}/) {
            ($yield_for = $_) =~ s/$prog_info{opts}{yield_for}//;
        }
        # PWM enrichment ratios of interest
        if (/$prog_info{opts}{pwm_for}/) {
            s/$prog_info{opts}{pwm_for}//;
            @{$pwm_enris_of_int{user}} = split /$seps{field}/;
        }
        # Whether to overwrite existing interpolated xs and MC flue files
        if (/$prog_info{opts}{overwrite}/) {
            $is_overwrite = 1;
        }
        # Whether to skip pausing the shell at the end of the program
        if (/$prog_info{opts}{nopause}/) {
            $is_nopause = 1;
        }
    }
    
    # Construct a range of the designated enrichment ratios.
    construct_range(\@enris_of_int) if @enris_of_int;
}


sub enrimo {
    # > define_chem_data() internally iterates over the Mo targets of interest
    #   designated, but for only one enrichment ratio at a time.
    # > write_to_data_files() generates reporting files for one Mo target
    #   at a time.
    foreach (@enris_of_int) {
        define_chem_data($_);
    }
    foreach (@mo_targets_of_int) {
        write_to_data_files($_);
        write_to_pwm_data_files($_) if @{$pwm_enris_of_int{matched}};
    }
}


sub define_chem_data {
    my($enri_of_int) = @_;
    
    #
    # Initializations
    #
    
    # Chemical elements
    %mo = (
        elem => {
            name           => 'molybdenum',
            symb           => 'Mo',
            avg_molar_mass => 0, # To be calculated
        },
        # Naturally occurring isotopes
        # > Used for calculations involving isotopic properties such as
        #   mass and mole fractions and a molar mass.
        # > Put the isotopes in the order of disappearing in the process of
        #   isotopic enrichment. For example, ascending mass numbers
        #   reflect the use of centrifuge for isotopic enrichment.
        isotopes => [
            '92',
            '94',
            '95',
            '96',
            '97',
            '98',
            '100',
        ],
        # mole_frac: Natural abundance by "mole" fraction found in
        # [1] http://www.ciaaw.org/isotopic-abundances.htm
        # [2] meija2016a.pdf
        # [3] mayer2014.pdf
        #
        # molar_mass: Atomic mass found in
        # [1] http://www.ciaaw.org/atomic-masses.htm
        # [2] wang2017.pdf
        '92' => {
            symb           => 'Mo-92',
            mole_frac      => 0.14649,
            mass_frac      => 0,         # To be calculated
            molar_mass     => 91.906807, # g mol^-1
            wgt_molar_mass => 0,         # To be calculated
        },
        '94' => {
            symb           => 'Mo-94',
            mole_frac      => 0.09187,
            mass_frac      => 0,
            molar_mass     => 93.905084,
            wgt_molar_mass => 0,
        },
        '95' => {
            symb           => 'Mo-95',
            mole_frac      => 0.15873,
            mass_frac      => 0,
            molar_mass     => 94.9058374,
            wgt_molar_mass => 0,
        },
        '96' => {
            symb           => 'Mo-96',
            mole_frac      => 0.16673,
            mass_frac      => 0,
            molar_mass     => 95.9046748,
            wgt_molar_mass => 0,
        },
        '97' => {
            symb           => 'Mo-97',
            mole_frac      => 0.09582,
            mass_frac      => 0,
            molar_mass     => 96.906017,
            wgt_molar_mass => 0,
        },
        '98' => {
            symb           => 'Mo-98',
            mole_frac      => 0.24292,
            mass_frac      => 0,
            molar_mass     => 97.905404,
            wgt_molar_mass => 0,
        },
        '99' => { # For yield calculation
            key       => 'mo_99',        # A key of a Mo target hash
            symb      => 'Mo-99',        # Col head of a reporting file
            half_life => 65.94,          # h
            dec_const => log(2) / 65.94, # h^-1
            yield     => 0,              # To be calculated
            sp_yield  => 0,              # To be calculated
        },
        '100' => {
            symb           => 'Mo-100',
            mole_frac      => 0.09744,
            mass_frac      => 0,
            molar_mass     => 99.907468,
            wgt_molar_mass => 0,
        },
    );
    
    %tc = (
        '99m' => { # For yield calculation
            key       => 'tc_99m',
            symb      => 'Tc-99m',
            half_life => 6.01,
            dec_const => log(2) / 6.01,
            yield     => 0,
            sp_yield  => 0,
        },
    );
    
    %o = (
        elem => {
            name           => 'oxygen',
            symb           => 'O',
            avg_molar_mass => 0,
        },
        isotopes => [
            '16',
            '17',
            '18',
        ],
        # mole_frac: Natural abundance by "mole" fraction found in
        # [1] http://www.ciaaw.org/isotopic-abundances.htm
        # [2] meija2016a.pdf
        #
        # molar_mass: Atomic mass found in
        # [1] http://www.ciaaw.org/oxygen.htm
        # [2] wang2017.pdf
        '16' => {
            symb           => 'O-16',
            mole_frac      => 0.99757, # Average
            mass_frac      => 0,
            molar_mass     => 15.994914619,
            wgt_molar_mass => 0,
        },
        '17' => {
            symb           => 'O-17',
            mole_frac      => 0.0003835,
            mass_frac      => 0,
            molar_mass     => 16.999131757,
            wgt_molar_mass => 0,
        },
        '18' => {
            symb           => 'O-18',
            mole_frac      => 0.002045,
            mass_frac      => 0,
            molar_mass     => 17.999159613,
            wgt_molar_mass => 0,
        },
    );
    
    # Mo targets
    %momet = (
        mo_tar => {
            name           => "metallic molybdenum",
            symb           => "Mo_{met}",
            num_moles      => {mo => 1, o => 0},
            avg_molar_mass => 0,     # To be calculated
            mass_dens      => 10.28, # g cm^-3
            num_dens       => 0,     # cm^-3
        },
        # To be calculated
        mo_elem => {
            mass_frac => 0,
            mass_dens => 0,
            num_dens  => 0,
            mass      => 0, # Assigned at (8); used for specific yield.
        },
        # Isotope of interest to be autovivified
    );
    
    %moo2 = (
        mo_tar => {
            name           => "molybdenum dioxide",
            symb           => "MoO_{2}",
            num_moles      => {mo => 1, o => 2},
            avg_molar_mass => 0,
            mass_dens      => 6.47,
            num_dens       => 0,
        },
        mo_elem => {
            mass_frac => 0,
            mass_dens => 0,
            num_dens  => 0,
            mass      => 0,
        },
    );
    
    %moo3 = (
        mo_tar => {
            name           => "molybdenum trioxide",
            symb           => "MoO_{3}",
            num_moles      => {mo => 1, o => 3},
            avg_molar_mass => 0,
            mass_dens      => 4.69,
            num_dens       => 0,
        },
        mo_elem => {
            mass_frac => 0,
            mass_dens => 0,
            num_dens  => 0,
            mass      => 0,
        },
    );
    
    # Converters for yield calculation
    %wmet = (
        symb       => 'W',
        mat_id     => 7400,
        surface_id => 100,
        cell_id    => 1,
        mass_dens  => 19.25,
        rad        => 0, # To be overwritten by the user
        hgt        => 0, # To be overwritten by the user
    );
    
    %graphite = (
        symb       => 'C',
        mat_id     => 6000,
        surface_id => 100,
        cell_id    => 1,
        mass_dens  => 2.267,
        rad        => 0,
        hgt        => 0,
    );
    
    #++++ Debugging ++++#
#    dump(\%mo); dump(\%o);
    #+++++++++++++++++++#
    
    # (1) Calculate the average molar masses of naturally occurring Mo and O
    #     using the "mole" fractions of their isotopes taken from IUPAC-CIAAW.
    calc_elem_avg_molar_mass(\%mo, 'mole_frac', $is_verbose);
    calc_elem_avg_molar_mass(\%o, 'mole_frac', $is_verbose);
    
    # (2) Convert mole to mass fractions for (3).
    convert_fracs(\%mo, 'mole_to_mass');
    convert_fracs(\%o, 'mole_to_mass'); # Printing purpose only
    
    #++++ Debugging ++++#
#    dump(\%mo); dump(\%o);
    #+++++++++++++++++++#
    
    # (3) Redistribute the mass fractions of Mo isotopes to reflect
    #     enrichment or depletion of the Mo isotope of interest.
    enrich_or_deplete(\%mo, $mo_isot_of_int, $enri_of_int, $is_verbose);
    
    # (4) Again calculate the average molar mass of Mo element, but now
    #     using the "new mass" fractions of Mo isotopes calculated at (3).
    #     > The resulting average molar mass of Mo element is slightly
    #       different from the mole-fraction-weighted one calculated at (1).
    #       For example, for naturally occurring Mo, the average molar mass
    #       is calculated to be 95.95 g mol^-1 for mole-fraction weighting,
    #       but 96.01 g mol^-1 for mass-fraction weighting.
    #     > To eliminate this inconsistency, I have tried obtaining a new
    #       average molar mass of Mo element by using the mole fraction
    #       as the weighting fraction, as in (1). To do so, I have first
    #       converted the redistributed mass fractions to mole fractions.
    #       This, however, resulted in a total mole fraction less than 1,
    #       because the mass-to-mole fraction conversion of isotopes,
    #       or vice versa, depends on the average molar mass of the element.
    #     > Please be aware, accordingly, that, the average molar mass of
    #       Mo element obtained by the following routine call will be slightly
    #       different from the one obtained by mole-fraction weighting.
    calc_elem_avg_molar_mass(\%mo, 'mass_frac', $is_verbose);
    
    # (5) Convert mass to mole fractions (printing purpose only).
    convert_fracs(\%mo, 'mass_to_mole');
    
    #++++ Debugging ++++#
#    dump(\%mo); dump(\%o);
    #+++++++++++++++++++#
    
    # (6) Calculate:
    #     > Average molar masses of Mo targets using the average molar mass of
    #       O obtained at (1) and the average molar mass of Mo obtained at (4)
    #     > Mass fractions of the associated Mo elements using the average
    #       molar masses of Mo targets
    #     Associate the following to the hash of Mo targets:
    #     > Mass fractions of the associated Mo isotope of interest
    calc_mo_tar_avg_molar_mass_and_its_subcomp_mass_fracs(
        \@mo_targets_of_int,
        $enri_of_int,
        $is_verbose
    );
    
    # (7) Calculate:
    #     > Mass densities of elemental Mo and and the Mo isotope of interest
    #     > Number densities a Mo target, its elemental Mo, and
    #       the Mo isotope of interest
    calc_mass_and_num_dens(\@mo_targets_of_int);
    
    # (8) Calculate yields and specific yields.
    #     > Run only when a description file has been designated
    #       via the command-line option.
    if ($yield_for) {
        # Calculation conditions parsing: Performed only once.
        # > parse_calc_conds() also runs the following routines:
        #   > interp_and_read_in_micro_xs() reads in and interpolates
        #     the designated microscopic xs, and converts barn to cm^2.
        #   > obtain_and_read_in_mc_flue() performs PHITS simulations
        #     for respective Mo targets and obtains the projectile
        #     fluences averaged over the Mo targets.
        #   > The microscopic xs and the particle fluences are then
        #     multiplied point by point in calc_yield_and_specific_yield()
        #     at the end of this block, giving yields and specific yields.
        state $is_first_call = 1;
        parse_calc_conds(\@mo_targets_of_int) if $is_first_call;
        $is_first_call = 0;
        
        # Reassign the masses and volumes of the Mo targets
        # and the masses of the associated Mo elements each time
        # this routine (i.e. define_chem_data()) is called.
        # > This step is needed because the chemical element and compound
        #   hashes (e.g. %mo, %momet, etc) initialize their contents
        #   by the = assignment at every run of define_chem_data().
        #   (such initializations are needed to start from "untouched"
        #   mass fractions of Mo isotopes before their redistribution.)
        foreach my $k (@mo_targets_of_int) {
            # The %memorized hash is given the mass and volume values
            # in parse_calc_conds(), which is performed only once
            # even with multiple calls of define_chem_data().
            $mo_targets{$k}{mo_tar}{mass}  = $memorized{$k}{mo_tar}{mass};
            $mo_targets{$k}{mo_tar}{vol}   = $memorized{$k}{mo_tar}{vol};
            $mo_targets{$k}{mo_elem}{mass} = # Used for specific yield calc
                $mo_targets{$k}{mo_tar}{mass}
                * $mo_targets{$k}{mo_elem}{mass_frac};
        }
        
        # Calculate the yields and specific yields of the product
        # radionuclides for respective Mo targets designated.
        calc_yield_and_specific_yield(\@mo_targets_of_int, $enri_of_int);
    }
    
    #++++ Debugging ++++#
#    dump(\%memorized);
#    dump(\%mo); dump(\%o); dump($mo_targets{$_}) for @mo_targets_of_int;
    #+++++++++++++++++++#
    
    # (9) Adjust the numbers of decimal places.
    adjust_num_of_decimal_places(\%mo);
    adjust_num_of_decimal_places(\%o);
    adjust_num_of_decimal_places(\@mo_targets_of_int);
    
    # (10) Construct row-wise data for write_to_data_files().
    foreach my $k (@mo_targets_of_int) {
        # 13 columns
        if ($yield_for) {
            push @{$data_array_refs{$k}},
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_frac},
                $mo_targets{$k}{mo_elem}{mass_frac},
                $mo_targets{$k}{mo_tar}{mass_dens},
                $mo_targets{$k}{mo_tar}{num_dens},
                $mo_targets{$k}{mo_elem}{mass_dens},
                $mo_targets{$k}{mo_elem}{num_dens},
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_dens},
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{num_dens},
                $dcc{$k}{val},
                # yield, Mo target mass, and specific yield
                # $calc_conds{product_nucl}{key}: e.g. mo_99, tc_99m
                $mo_targets{$k}{$calc_conds{product_nucl}{key}}{yield},
                $mo_targets{$k}{mo_tar}{mass},  # NOT used for specific yield
                $mo_targets{$k}{mo_elem}{mass}, # Used for specific yield
                $mo_targets{$k}{$calc_conds{product_nucl}{key}}{sp_yield};
        }
        # 9 columns: "Without" yield, Mo target mass, and specific yield
        elsif (not $yield_for) {
            push @{$data_array_refs{$k}},
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_frac},
                $mo_targets{$k}{mo_elem}{mass_frac},
                $mo_targets{$k}{mo_tar}{mass_dens},
                $mo_targets{$k}{mo_tar}{num_dens},
                $mo_targets{$k}{mo_elem}{mass_dens},
                $mo_targets{$k}{mo_elem}{num_dens},
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_dens},
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{num_dens},
                $dcc{$k}{val};
        }
    }
}


sub calc_elem_avg_molar_mass {
    my($hash_ref_to_elem, $weighting_frac, $_is_verbose) = @_;
    
    if ($_is_verbose) {
        printf(
            "\n%s()\n".
            "calculating the average molar mass of [%s]...\n\n",
            join('::', (caller(0))[0, 3]),
            $hash_ref_to_elem->{elem}{symb},
        );
    }
    
    # Calculate the average molar mass of a chemical element
    # by adding up "weighted" molar masses of its isotopes.
    
    # Initialization
    $hash_ref_to_elem->{elem}{avg_molar_mass} = 0;
    
    foreach my $isot (@{$hash_ref_to_elem->{isotopes}}) {
        # (1) Weight the molar mass of an isotope by $weighting_frac.
        $hash_ref_to_elem->{$isot}{wgt_molar_mass} =
            $hash_ref_to_elem->{$isot}{$weighting_frac}
            * $hash_ref_to_elem->{$isot}{molar_mass};
        
        # (2) Cumulative sum of the weighted molar masses, which will
        #     in turn be the average molar mass of the element.
        $hash_ref_to_elem->{elem}{avg_molar_mass} +=
            $hash_ref_to_elem->{$isot}{wgt_molar_mass};
    }
    
    if ($_is_verbose) {
        dump($hash_ref_to_elem);
        pause_shell("Press enter to continue...");
    }
}


sub convert_fracs {
    my($hash_ref_to_elem, $conv_mode) = @_;
    
    # Mole to mass fractions
    # > enri_pmb.pdf
    # > https://en.wikipedia.org/wiki/Mole_fraction
    if ($conv_mode =~ /mole_to_mass/i) {
        foreach my $isot (@{$hash_ref_to_elem->{isotopes}}) {
            $hash_ref_to_elem->{$isot}{mass_frac} =
                $hash_ref_to_elem->{$isot}{mole_frac}
                * $hash_ref_to_elem->{$isot}{molar_mass}
                / $hash_ref_to_elem->{elem}{avg_molar_mass}
        }
    }
    
    # Mass to mole fractions
    # > https://en.wikipedia.org/wiki/Mass_fraction_(chemistry)
    elsif ($conv_mode =~ /mass_to_mole/i) {
        foreach my $isot (@{$hash_ref_to_elem->{isotopes}}) {
            $hash_ref_to_elem->{$isot}{mole_frac} =
                $hash_ref_to_elem->{$isot}{mass_frac}
                * $hash_ref_to_elem->{elem}{avg_molar_mass}
                / $hash_ref_to_elem->{$isot}{molar_mass};
        }
    }
}


sub calc_mo_tar_avg_molar_mass_and_its_subcomp_mass_fracs {
    my($keys_of_mo_targets, $_enri_of_int, $_is_verbose) = @_;
    
    foreach my $k (@$keys_of_mo_targets) { # e.g. momet, moo2, moo3
        if ($_is_verbose) {
            printf(
                "\n%s()\n".
                "calculating the average molar mass of [%s]...\n\n",
                join('::', (caller(0))[0, 3]),
                $mo_targets{$k}{mo_tar}{symb},
            );
        }
        
        # (1) Calculate the average molar mass of a Mo target, which depends on
        #     > The average molar mass of its element, which is changed
        #       when the isotopic composition of the element is changed.
        #       e.g. Mo-100 enrichment
        #     > The number of moles of oxygen:
        #       0 for metallic Mo => Mo target mass == Mo mass
        #       2 for MoO2        => Mo target mass >  Mo mass
        #       3 for MoO3        => Mo target mass >> Mo mass
        $mo_targets{$k}{mo_tar}{avg_molar_mass} =
            (
                $mo_targets{$k}{mo_tar}{num_moles}{mo}
                * $mo{elem}{avg_molar_mass} # <= Affected by Mo-100 enrichment
            ) + (
                $mo_targets{$k}{mo_tar}{num_moles}{o} # <= Mo target-dependent
                * $o{elem}{avg_molar_mass}
            );
        
        # (2) Using the average molar mass of the Mo target obtained at (1),
        #     calculate the mass fraction of its Mo element.
        $mo_targets{$k}{mo_elem}{mass_frac} =
            $mo{elem}{avg_molar_mass} / $mo_targets{$k}{mo_tar}{avg_molar_mass};
        
        # (3) Associate the mass fraction of the Mo isotope of interest.
        $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_frac} = # Autovivification
            $mo{$mo_isot_of_int}{mass_frac};
        
        if ($_is_verbose) {
            dump(\$mo_targets{$k}{mo_tar});
            pause_shell("Press enter to continue...");
        }
        
        # (4) Calculate a density change coefficient.
        if ($dcc_init) {
            # (i) $_enri_of_int same as the designated $dcc_init:
            #     The 1st independent variable of a DCC
            if ($_enri_of_int == $dcc_init) {
                $dcc{$k}{'mo_'.$mo_isot_of_int}{initial}{mass_frac}
                    = $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_frac};
                $dcc{$k}{mo_elem}{initial}{mass_frac} =
                    $mo_targets{$k}{mo_elem}{mass_frac};
            }
            
            # (ii) $_enri_of_int NOT the same as the designated $dcc_init:
            #      The 2nd independent variable of a DCC
            $dcc{$k}{'mo_'.$mo_isot_of_int}{final}{mass_frac}
                = $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_frac};
            $dcc{$k}{mo_elem}{final}{mass_frac} =
                $mo_targets{$k}{mo_elem}{mass_frac};
            
            # Calculate a DCC if its initial conditions have been defined.
            if ($dcc{$k}{'mo_'.$mo_isot_of_int}{initial}{mass_frac})
            {
                $dcc{$k}{val} = sprintf (
                    "$format_specifiers{dcc}",
                    (
                        $dcc{$k}{'mo_'.$mo_isot_of_int}{final}{mass_frac}
                        / $dcc{$k}{'mo_'.$mo_isot_of_int}{initial}{mass_frac}
                    ) * (
                        $dcc{$k}{mo_elem}{final}{mass_frac}
                        / $dcc{$k}{mo_elem}{initial}{mass_frac}
                    )
                );
            }
        }
    }
}


sub calc_mass_and_num_dens {
    my($keys_of_mo_targets) = @_;
    
    foreach my $k (@$keys_of_mo_targets) { # e.g. momet, moo2, moo3
        #
        # Mass density
        #
        
        # Mo element
        $mo_targets{$k}{mo_elem}{mass_dens} =
            $mo_targets{$k}{mo_elem}{mass_frac}
            * $mo_targets{$k}{mo_tar}{mass_dens};
        # Mo isotope of interest
        $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_dens} =
            $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_frac}
            * $mo_targets{$k}{mo_elem}{mass_dens};
        
        #
        # Number density (using the mass density)
        #
        
        # Mo target
        $mo_targets{$k}{mo_tar}{num_dens} =
            $mo_targets{$k}{mo_tar}{mass_dens}
            * $consts{avogadro}
            / $mo_targets{$k}{mo_tar}{avg_molar_mass};
        # Mo element
        $mo_targets{$k}{mo_elem}{num_dens} =
            $mo_targets{$k}{mo_elem}{mass_dens}
            * $consts{avogadro}
            / $mo{elem}{avg_molar_mass};
        # Mo isotope of interest
        $mo_targets{$k}{'mo_'.$mo_isot_of_int}{num_dens} =
            $mo_targets{$k}{'mo_'.$mo_isot_of_int}{mass_dens}
            * $consts{avogadro}
            / $mo{$mo_isot_of_int}{molar_mass};
    }
}


sub parse_calc_conds {
    my($keys_of_mo_targets) = @_;
    
    # (1) Construct a data structure for storing parsed values.
    %calc_conds = (
        # Irradiation conditions
        reaction => {
            regex => qr/^\s*reaction\s*=\s*/i,
            val   => 'gn', # gn, n2n, p2n
        },
        beam_erg => {
            regex => qr/^\s*beam_erg\s*=\s*/i,
            val   => 3.5e7, # eV
        },
        beam_curr => {
            regex => qr/^\s*beam_curr\s*=\s*/i,
            val   => 1, # uA
        },
        beam_rad => {
            regex => qr/^\s*beam_rad\s*=\s*/i,
            val   => 0.3, # cm
        },
        end_of_irr => {
            regex => qr/^\s*end_of_irr\s*=\s*/i,
            val   => 72, # h
        },
        
        # Targetry
        converter => {
            regex => qr/^\s*converter\s*=\s*/i,
            val   => 'wmet', # wmet:gn, graphite:n2n
        },
        converter_rad => {
            regex => qr/^\s*converter_rad\s*=\s*/i,
            val   => 1.0, # cm
        },
        converter_hgt => {
            regex => qr/^\s*converter_hgt\s*=\s*/i,
            val   => 0.3, # cm
        },
        mo_tar_rad => {
            regex => qr/^\s*mo_tar_rad\s*=\s*/i,
            val   => 0.5, # cm
        },
        mo_tar_hgt => {
            regex => qr/^\s*mo_tar_hgt\s*=\s*/i,
            val   => 1.0, # cm
        },
        
        # Monte Carlo simulation nps
        mc_flue_nps => {
            maxcas => {
                regex => qr/^\s*mc_flue_maxcas\s*=\s*/i,
                val   => 10000,
            },
            maxbch => {
                regex => qr/^\s*mc_flue_maxbch\s*=\s*/i,
                val   => 100,
            },
        },
        
        # Energy range for xs and MC fluence
        emin => {
            regex => qr/^\s*emin\s*=\s*/i,
            val   => 8.5e6, # eV
        },
        emax => {
            regex => qr/^\s*emax\s*=\s*/i,
            val   => 3.5e7,
        },
        ne => {
            regex => qr/^\s*ne\s*=\s*/i,
            val   => 1000,
        },
        
        # xs and MC fluence I/O
        micro_xs_dat => {
            dir => {
                regex => qr/^\s*micro_xs_dat_dir\s*=\s*/i,
                val   => 'xs',
            },
            fname => {
                regex => qr/^\s*micro_xs_dat\s*=\s*/i,
                val   => 'tendl2015_mo100_gn_mf3_t4.dat',
            },
        },
        mc_flue_dat => {
            dir => {
                regex => qr/^\s*mc_flue_dat_dir\s*=\s*/i,
                val   => 'mc_flue',
            },
            bname => {
                regex => qr/^\s*mc_flue_dat_bname\s*=\s*/i,
                val   => 'phits_mo100_gn',
            },
        },
    );
    
    # (2) Parse the user input file.
    open my $yield_for_fh, '<', $yield_for;
    foreach (<$yield_for_fh>) {
        chomp();
        next if /^\s*$/; # Skip a blank line.
        next if /^\s*#/; # Skip a comment line.
        s/\s*#.*//;      # Suppress a comment.
        
        # Irradiation conditions
        if (/$calc_conds{reaction}{regex}/) {
            s/$calc_conds{reaction}{regex}//;
            $calc_conds{reaction}{val} = $_;
        }
        if (/$calc_conds{beam_erg}{regex}/) {
            s/$calc_conds{beam_erg}{regex}//;
            $calc_conds{beam_erg}{val} = $_;
        }
        if (/$calc_conds{beam_curr}{regex}/) {
            s/$calc_conds{beam_curr}{regex}//;
            $calc_conds{beam_curr}{val} = $_;
        }
        if (/$calc_conds{beam_rad}{regex}/) {
            s/$calc_conds{beam_rad}{regex}//;
            $calc_conds{beam_rad}{val} = $_;
        }
        if (/$calc_conds{end_of_irr}{regex}/) {
            s/$calc_conds{end_of_irr}{regex}//;
            $calc_conds{end_of_irr}{val} = $_;
        }
        
        # Targetry
        if (/$calc_conds{converter}{regex}/) {
            s/$calc_conds{converter}{regex}//;
            $calc_conds{converter}{val} = $_;
        }
        if (/$calc_conds{converter_rad}{regex}/) {
            s/$calc_conds{converter_rad}{regex}//;
            $calc_conds{converter_rad}{val} = $_;
        }
        if (/$calc_conds{converter_hgt}{regex}/) {
            s/$calc_conds{converter_hgt}{regex}//;
            $calc_conds{converter_hgt}{val} = $_;
        }
        # Mo targets are designated via the command-line option.
        if (/$calc_conds{mo_tar_rad}{regex}/) {
            s/$calc_conds{mo_tar_rad}{regex}//;
            $calc_conds{mo_tar_rad}{val} = $_;
        }
        if (/$calc_conds{mo_tar_hgt}{regex}/) {
            s/$calc_conds{mo_tar_hgt}{regex}//;
            $calc_conds{mo_tar_hgt}{val} = $_;
        }
        
        # Monte Carlo simulation nps
        if (/$calc_conds{mc_flue_nps}{maxcas}{regex}/) {
            s/$calc_conds{mc_flue_nps}{maxcas}{regex}//;
            $calc_conds{mc_flue_nps}{maxcas}{val} = $_;
        }
        if (/$calc_conds{mc_flue_nps}{maxbch}{regex}/) {
            s/$calc_conds{mc_flue_nps}{maxbch}{regex}//;
            $calc_conds{mc_flue_nps}{maxbch}{val} = $_;
        }
        
        # Energy range for xs and MC fluence
        if (/$calc_conds{emin}{regex}/) {
            s/$calc_conds{emin}{regex}//;
            $calc_conds{emin}{val} = $_;
        }
        if (/$calc_conds{emax}{regex}/) {
            s/$calc_conds{emax}{regex}//;
            $calc_conds{emax}{val} = $_;
        }
        if (/$calc_conds{ne}{regex}/) {
            s/$calc_conds{ne}{regex}//;
            $calc_conds{ne}{val} = $_;
        }
        
        # xs and MC fluence I/O
        if (/$calc_conds{micro_xs_dat}{dir}{regex}/) {
            s/$calc_conds{micro_xs_dat}{dir}{regex}//;
            $calc_conds{micro_xs_dat}{dir}{val} = $_;
        }
        if (/$calc_conds{micro_xs_dat}{fname}{regex}/) {
            s/$calc_conds{micro_xs_dat}{fname}{regex}//;
            $calc_conds{micro_xs_dat}{fname}{val} = $_;
        }
        if (/$calc_conds{mc_flue_dat}{dir}{regex}/) {
            s/$calc_conds{mc_flue_dat}{dir}{regex}//;
            $calc_conds{mc_flue_dat}{dir}{val} = $_;
        }
        if (/$calc_conds{mc_flue_dat}{bname}{regex}/) {
            s/$calc_conds{mc_flue_dat}{bname}{regex}//;
            $calc_conds{mc_flue_dat}{bname}{val} = $_;
        }
    }
    close $yield_for_fh;
    
    # (3) Memorize the parsed values.
    # > The memorized values will all be written to the gnuplot data file
    #   for noticing the calculation conditions.
    # > In addition, $memorized{beam_curr} will be multiplied to the yield at
    #   calc_yield_and_specific_yield().
    $memorized{beam_curr} = 1 if not $memorized{beam_curr}; # Default to 1 uA
    foreach my $key (keys %calc_conds) {
        # Single-nested hash ref
        if (defined $calc_conds{$key}{val}) {
            $memorized{$key} = $calc_conds{$key}{val};
        }
        # Double-nested hash ref
        if ($key =~ /mc_flue_nps/) {
            $memorized{maxcas} = $calc_conds{$key}{maxcas}{val};
            $memorized{maxbch} = $calc_conds{$key}{maxbch}{val};
        }
    }
    
    # (4) Define which will be the product radionuclide.
    #     > When calc_yield_and_specific_yield() is called,
    #       a hash key named the same as this nuclide's 'key' attribute,
    #       (e.g. 'mo_99', 'tc_99m') and subattributes called 'yield' and
    #       'sp_yield' will be autovivified to each of the designated
    #       Mo targets. The values of 'yield' and 'sp_yield' will then
    #       be written to the data reduction reporting files.
    #     > As $calc_conds{product_nucl} is merely an alias of an isotope hash
    #       nested to %mo or %tc, decay constants needed in yield calculation
    #       are also referred via $calc_conds{product_nucl}.
    #       e.g. $calc_conds{product_nucl}{dec_const} == $mo{'99'}{dec_const} ||
    #                                                    $tc{'99m'}{dec_const}
    #     > Another use of $calc_conds{product_nucl} is to write the product
    #       radionuclide's symbol in the headings of the reporting files.
    $calc_conds{product_nucl} =
        $calc_conds{reaction}{val} =~ /^p/i ? $tc{'99m'} : # p2n
                                              $mo{'99'};   # gn, n2n
    
    # (5) Populate the converter dimension attributes.
    #     > These attributes will be used in generating PHITS simulation
    #       input files at obtain_and_read_in_mc_flue().
    $converters{$calc_conds{converter}{val}}{rad} = # == e.g. $wmet{rad}
        $calc_conds{converter_rad}{val};
    $converters{$calc_conds{converter}{val}}{hgt} =
        $calc_conds{converter_hgt}{val};
    
    #++++ Debugging ++++#
#    dump(\%calc_conds);
    #+++++++++++++++++++#
    
    # (6) Interpolate microscopic cross sections using gnuplot
    #     and store them in the units of barn and cm^2 into %xs.
    interp_and_read_in_micro_xs(
        $calc_conds{micro_xs_dat}{dir}{val},
        $calc_conds{micro_xs_dat}{fname}{val},
        $calc_conds{emin}{val},
        $calc_conds{emax}{val},
        $calc_conds{ne}{val},
    );
    
    # (7) Obtain Monte Carlo fluences using PHITS and store them into %mc_flues.
    foreach my $k (@$keys_of_mo_targets) { # e.g. momet, moo2, moo3
        #
        # Preprocessing for reaction-dependent PHITS input file generation
        #
        
        # Populate the dimension attributes of a Mo target.
        $mo_targets{$k}{mo_tar}{rad} = $calc_conds{mo_tar_rad}{val};
        $mo_targets{$k}{mo_tar}{hgt} = $calc_conds{mo_tar_hgt}{val};
        
        # Calculate the volume and mass of the Mo target "AND" memorize
        # them into the %memorized hash.
        # > These memorized values will then be assigned to the 'vol'
        #   and 'mass' subattributes of the Mo target hashes each time
        #   the define_chem_data() routine is called.
        #   (Remember: parse_calc_conds() has been designed to be
        #   a one-time routine, and therefore the Mo target radii and heights
        #   read in and assigned to the Mo target hashes here will be lost
        #   at the next call of parse_calc_conds(), which initializes
        #   the Mo target hashes by the = assignment.)
        $mo_targets{$k}{mo_tar}{vol} =
        $memorized{$k}{mo_tar}{vol}  = # Memorize!
            calculate_volume(
                'rcc',
                $mo_targets{$k}{mo_tar}{rad},
                $mo_targets{$k}{mo_tar}{hgt}
            );
        $mo_targets{$k}{mo_tar}{mass} =
        $memorized{$k}{mo_tar}{mass}  = # Memorize!
            $mo_targets{$k}{mo_tar}{mass_dens}
            * $mo_targets{$k}{mo_tar}{vol};
        
        # Perform a Monte Carlo simulation and obtain the projectile fluence
        # averaged over the Mo target.
        obtain_and_read_in_mc_flue(
            $calc_conds{mc_flue_dat}{dir}{val},
            $calc_conds{mc_flue_dat}{bname}{val},
            $calc_conds{emin}{val},
            $calc_conds{emax}{val},
            $calc_conds{ne}{val},
            $calc_conds{reaction}{val},
            $calc_conds{mc_flue_nps}{maxcas}{val},
            $calc_conds{mc_flue_nps}{maxbch}{val},
            $calc_conds{beam_erg}{val},
            $calc_conds{beam_rad}{val},
            $k, # e.g. momet, moo2, moo3
        );
    }
}


sub interp_and_read_in_micro_xs {
    my($xs_dat_dir, $xs_dat, $emin, $emax, $ne) = @_;
    my($bname, $ext) = (split /[.]/, $xs_dat)[0, 1];
    my $gp_interp_inp = "$bname\_interp.gp";
    my $xs_interp_dat = "$bname\_interp.$ext";
    $memorized{micro_xs_dat} = sprintf(
        "%s%s%s",
        $xs_dat_dir,
        $^O =~ /MSWin/? '\\' : '/',
        $xs_interp_dat
    );
    
    # Generate a gnuplot script for xs interpolation.
    mkdir $xs_dat_dir unless -e $xs_dat_dir;
    chdir $xs_dat_dir;
    
    if (not -e $gp_interp_inp or $is_overwrite) {
        open my $gp_interp_inp_fh, '>:encoding(UTF-8)', $gp_interp_inp;
        select($gp_interp_inp_fh);
        
        say "#!/usr/bin/gnuplot";
        say "";
        say "dat = '$xs_dat'";
        say "tab = '$xs_interp_dat'";
        say "";
        say "xmin = $emin";
        say "xmax = $emax";
        say "nx   = $ne";
        say "set xrange [xmin:xmax]";
        say "";
        say "set table tab";
        say "set samples nx";
        say "plot dat u 1:2 smooth cspline notitle";
        say "unset table";
        say "#eof";
        
        select(STDOUT);
        close $gp_interp_inp_fh;
    }
    
    # Interpolate the microscopic xs using gnuplot.
    if (not -e $xs_interp_dat or $is_overwrite) {
        system "gnuplot $gp_interp_inp";
#        unlink $gp_interp_inp;
    }
    
    # Read in the interpolated microscopic xs and store them
    # in the units of barn and cm^2.
    open my $xs_interp_dat_fh, '<', $xs_interp_dat;
    foreach (<$xs_interp_dat_fh>) {
        next if /^\s*#/ or /^$/; # Skip comment and blank lines.
        s/^\s+//;                # Suppress leading spaces.
        push @{$xs{erg}{ev}},       (split)[0];
        push @{$xs{erg}{mega_ev}},  (split)[0] / 1e6;
        push @{$xs{micro}{barn}},   (split)[1];
        push @{$xs{micro}{'cm^2'}}, (split)[1] * $consts{barn};
    }
    
    #++++ Debugging ++++#
#    say @{$xs{micro}{barn}} * 1;
    #+++++++++++++++++++#
    
    chdir $where_prog_began;
}


sub obtain_and_read_in_mc_flue {
    my(
        $mc_flue_dat_dir, $mc_flue_dat_bname, $emin, $emax, $ne,
        $reaction, $maxcas, $maxbch, $beam_erg, $beam_rad,
        $k,
    ) = @_;
    
    #
    # Scale the energy unit with respect to PHITS, which uses MeV.
    #
    $_ /= 1e6 for ($emin, $emax, $beam_erg);
    
    #
    # Caution: The energy unit of heavy ions (over deuteron) in PHITS is MeV/u;
    #          thus $beam_erg must also be in MeV/u for the n2n reaction,
    #          which uses deuteron as a neutron source.
    #
    
    #
    # Filenames
    #
    my $phits_bname = "$mc_flue_dat_bname\_$k";
    my $phits_inp   = "$phits_bname.inp";
    my $phits_out   = "$phits_bname.out";
    my $phits_trk   = "$phits_bname\_track.ang";
    my $phits_erg   = "$phits_bname\_erg.ang";
    $memorized{$k}{mc_flue_dat} = sprintf(
        "%s%s%s",
        $mc_flue_dat_dir,
        $^O =~ /MSWin/? '\\' : '/',
        $phits_erg
    );
    
    #
    # PHITS particles
    #
    my %parts = (
        proton   => {ityp => 1,  symb => 'proton'  },
        neutron  => {ityp => 2,  symb => 'neutron' },
        electron => {ityp => 12, symb => 'electron'},
        positron => {ityp => 13, symb => 'positron'},
        photon   => {ityp => 14, symb => 'photon'  },
        deuteron => {ityp => 15, symb => 'deuteron'},
    );
    
    #
    # Reaction-dependent PHITS parameters
    #
    
    # The starting z-coordinate of the first target
    # > Tungsten (W) for gn
    # > Graphite (C) for n2n
    # > Mo target for p2n (no converter)
    my $first_tar_z0  = 0.00; # cm
    
    # The distance between the first and second targets.
    # > Not used at all for p2n (again, no converter!)
    my $intertar_dist = 0.15; # cm
    
    # Reaction (i): Mo-100(g,n)Mo-99
    my %gn = (
        # negs=1 sets (and, remember that PHITS uses MeV):
        # emin(12,13)=0.1  (i.e. 100 keV for electron, positron        )
        # emin(14)=0.001   (i.e.   1 keV for                     photon)
        # dmax(12-14)=1000 (i.e.   1 GeV for electron, positron, photon)
        params       => "ipnint  = 1\n".
                        "negs    = 1",
        proj         => $parts{electron}{symb}, # The one incident on 1st target
        proj_erg     => $beam_erg,
        converter    => $converters{wmet},
        mo_target_z0 => $first_tar_z0
                        + $converters{wmet}{hgt}
                        + $intertar_dist,
        tally_parts  => {
            trk => $parts{electron}{symb}
                   ." ".$parts{photon}{symb},
#                   ." ".$parts{neutron}{symb}, # All photoneuts are < 8 MeV
            erg => $parts{photon}{symb}, # The one inducing nucl reaction
        },
    );
    
    # Reaction (ii): Mo-100(n,2n)Mo-99
    my %n2n = (
        # nucdata=1 sets:
        # emin(2)=1e-10 (i.e. 0.1 meV; for ref: 25 meV is the thermal neut erg)
        # dmax(2)=20    (i.e.  20 MeV)
        params  => "nucdata = 1",
        cutoffs => sprintf(
            "emin(%s) = %s\n".
            "emin(%s) = %s \$ Deut: MeV/u\n".
            "dmax(%s) = %s\n".
            "dmax(%s) = %s",
            $parts{neutron}{ityp},  1e-10, # 0.1 meV
            $parts{deuteron}{ityp}, 0.05,  # * 2 => 100 keV (MeV/u for deut)
            $parts{neutron}{ityp},  ($beam_erg * 2) + 1.0, # Because of (MeV/u)
            $parts{deuteron}{ityp}, ($beam_erg * 2) + 1.0,
        ),
        proj         => $parts{deuteron}{symb},
        proj_erg     => $beam_erg." \$ Deut: MeV/u",
        converter    => $converters{graphite},
        mo_target_z0 => $first_tar_z0
                        + $converters{graphite}{hgt}
                        + $intertar_dist,
        tally_parts  => {
            trk => $parts{deuteron}{symb}." ".
                   $parts{neutron}{symb},
            erg => $parts{neutron}{symb},
        },
    );
    
    # Reaction (iii): Mo-100(p,2n)Tc-99m
    my %p2n = (
        #-----------------------------------------------------------------------
        # 2018-10-04
        # Setting dmax(1) causes the following error:
        # Error: There is no cross-section table(s) in xsdir.
        #    8016.  h
        #   42092.  h
        #   42094.  h
        #   42095.  h
        #   42096.  h
        #   42097.  h
        #   42098.  h
        #   42100.  h
        # Please check [material] section,
        # or set nucdata=0 to disable nuclear data
        #-----------------------------------------------------------------------
        cutoffs => sprintf( # Don't use dmax(1)
            "emin(%s) = %s\n",
            $parts{proton}{ityp}, 0.1, # 100 keV
        ),
        proj         => $parts{proton}{symb},
        proj_erg     => $beam_erg,
        mo_target_z0 => $first_tar_z0, # No converter!
        tally_parts  => {
            trk => $parts{proton}{symb}." ".
                   $parts{neutron}{symb},
            erg => $parts{proton}{symb},
        },
    );
    
    # Hash refs to the reactions
    my %reactions = (
        gn  => \%gn,
        n2n => \%n2n,
        p2n => \%p2n,
    );
    
    #
    # Reaction-"in"dependent PHITS parameters
    #
    my %opts = (
        mo_target => {
            mat_id     => 4200, # Converter: 7400 (W) or 6000 (C)
            surface_id => 101,  # Converter: 100 (W and C)
            cell_id    => 10,   # Converter:   1 (W and C)
            mass_dens  => $mo_targets{$k}{mo_tar}{mass_dens},
            hgt        => $mo_targets{$k}{mo_tar}{hgt},
            rad        => $mo_targets{$k}{mo_tar}{rad},
            vol        => $mo_targets{$k}{mo_tar}{vol},
            comp       => $k =~ /momet/i ?
                "Mo $mo_targets{$k}{mo_tar}{num_moles}{mo}" :
                "Mo $mo_targets{$k}{mo_tar}{num_moles}{mo}".
                " O $mo_targets{$k}{mo_tar}{num_moles}{o}",
        },
        mc_calc_world => {
            mat_id     => 0, # The "inner" void; PHITS p. 136
            surface_id => 999,
            cell_id    => 98,
            rad        => 20,
            cmt        => '$ MC calculation world',
        },
        the_void => {
            mat_id  => -1, # The "outer" void; PHITS p. 136
            cell_id => 99,
        },
    );
    
    #
    # Generate a PHITS input file for obtaining Monte Carlo fluences.
    #
    mkdir $mc_flue_dat_dir unless -e $mc_flue_dat_dir;
    chdir $mc_flue_dat_dir;
    
    if (not -e $phits_inp or $is_overwrite) {
        open my $phits_inp_fh, '>:encoding(UTF-8)', $phits_inp;
        select($phits_inp_fh);
        
        # Shared-memory parallel computing
        #
        # Add an environment variable, if you have not, as:
        # OMP_NUM_THREADS = n
        # where n should be the number of physical cores,
        # not the number of threads that can be simultaneously processed.
        # For details, refer to:
        # > PHITS v3.02 User's Manual in Japanese, p. 295
        # > PHITS v3.02 User's Manual in English, p. 256
        say "\$OMP=0";
        
        # parameters section
        say "";
        say "[parameters]";
        say "icntl   = 0";
        say "maxcas  = $maxcas";
        say "maxbch  = $maxbch";
        say $reactions{$reaction}{params}
            if exists $reactions{$reaction}{params};
        say $reactions{$reaction}{cutoffs}
            if exists $reactions{$reaction}{cutoffs};
        say "file(1) = C:/phits";   # Sets file(7,20,21,24,25); v2.93 required
        say "file(6) = $phits_out"; # Simulation stat summary (CPU time etc)
        
        # source section
        say "";
        say "[source]";
        say "proj   = $reactions{$reaction}{proj}";
        say "s-type = 13";        # Normal distribution over an xy plane
        say "e0     = $reactions{$reaction}{proj_erg}"; # Monoenergetic
        say "x0     = 0";         # x-center coordinate
        say "y0     = 0";         # y-center coordinate
        say "r1     = $beam_rad"; # Beam radius in FWHM
        say "z0     = -5";        # z-beginning coordinate
        say "z1     = -5";        # z-ending coordinate
        say "dir    = 1";         # z-axis angle in arccosine
        
        # material section
        say "";
        say "[material]";
        # "With" a converter target: gn, n2n
        if (exists $reactions{$reaction}{converter}) {
            printf(
                "mat[%s] %s 1\n",
                $reactions{$reaction}{converter}{mat_id},
                $reactions{$reaction}{converter}{symb},
            )
        }
        printf(
            "mat[%s] %s\n",
            $opts{mo_target}{mat_id},
            $opts{mo_target}{comp}
        );
        
        # surface section
        say "";
        say "[surface]";
        # "With" a converter target: gn, n2n
        if (exists $reactions{$reaction}{converter}) {
            printf(
                "%s rcc  0.00 0.00 %s\n".
                "         0.00 0.00 %s\n".
                "         %s\n",
                $reactions{$reaction}{converter}{surface_id}, $first_tar_z0,
                $reactions{$reaction}{converter}{hgt}, # Vector height
                $reactions{$reaction}{converter}{rad}
            );
        }
        printf(
            "%s rcc  0.00 0.00 %s\n".
            "         0.00 0.00 %s\n".
            "         %s\n",
            $opts{mo_target}{surface_id}, $reactions{$reaction}{mo_target_z0},
            $opts{mo_target}{hgt},
            $opts{mo_target}{rad}
        );
        printf(
            "%s  so %s %s\n",
            $opts{mc_calc_world}{surface_id},
            $opts{mc_calc_world}{rad},
            $opts{mc_calc_world}{cmt},
        );
        
        # cell section
        say "";
        say "[cell]";
        # "With" a converter target: gn, n2n
        if (exists $reactions{$reaction}{converter}) {
            printf(
                "%s  %3s -%5s -%s\n",
                $reactions{$reaction}{converter}{cell_id},
                $reactions{$reaction}{converter}{mat_id},
                $reactions{$reaction}{converter}{mass_dens},
                $reactions{$reaction}{converter}{surface_id}
            );
        }
        printf(
            "%s %s -%s  -%s\n",
            $opts{mo_target}{cell_id},
            $opts{mo_target}{mat_id},
            $opts{mo_target}{mass_dens},
            $opts{mo_target}{surface_id}
        );
        printf(
            "%s   %s        -%s %s\n",
            $opts{mc_calc_world}{cell_id},
            $opts{mc_calc_world}{mat_id},
            $opts{mc_calc_world}{surface_id}, # "In"side the mc_calc_world
            exists $reactions{$reaction}{converter} ?
                '#'.$reactions{$reaction}{converter}{cell_id}.
                ' '.
                '#'.$opts{mo_target}{cell_id} :
                '#'.$opts{mo_target}{cell_id}
        );
        printf(
            "%s  %s         %s\n",
            $opts{the_void}{cell_id},
            $opts{the_void}{mat_id},
            $opts{mc_calc_world}{surface_id} # "Out"side the mc_calc_world
        );
        
        # volume section
        say "";
        say "[volume]";
        say "reg vol";
        say "$opts{mo_target}{cell_id} $opts{mo_target}{vol}";
        
        # t-track section 1: Particle tracks on xz plane
        say "";
        say "[t-track]";
        say "mesh   = xyz";
        say "x-type = 2";
        say "nx     = 100";
        say "xmin   = -3";
        say "xmax   = 3";
        say "y-type = 2";
        say "ny     = 1";
        say "ymin   = -3";
        say "ymax   = 3";
        say "z-type = 2";
        say "nz     = 100";
        say "zmin   = -2";
        say "zmax   = 4";
        say "e-type = 2";
        say "ne     = 1";
        say "emin   = $emin";
        # $emax + 1 enables the beam track to be shown from its origin.
        say "emax   = ".($emax + 1).' $ Source erg + 1';
        say "part   = $reactions{$reaction}{tally_parts}{trk}";
        say "axis   = xz";
        say "file   = $phits_trk";
        say "unit   = 1";
        say "factor = 1";
        say "title  = t-track-xz";
        say "gshow  = 1";
        say "epsout = 1";
        
        # t-track section 2: Energy spectrum
        say "";
        say "[t-track]";
        say "mesh   = reg";
        say "reg    = $opts{mo_target}{cell_id}";
        say "e-type = 2";
        say "ne     = $ne";
        say "emin   = $emin";
        say "emax   = $emax";
        say "part   = $reactions{$reaction}{tally_parts}{erg}";
        say "axis   = eng";
        say "file   = $phits_erg";
        say "unit   = 1";
        say "factor = 1";
        say "title  = t-track-energy";
        say "epsout = 1";
        
        # end section
        say "";
        print "[end]";
        
        select(STDOUT);
        close $phits_inp_fh;
    }
    
    #
    # Run PHITS
    #
    if (not -e $phits_erg or $is_overwrite) {
        system "phits $phits_inp";
    }
    
    #
    # Read in the Monte Carlo fluences and store them into %mc_flues.
    #
    open my $phits_erg_fh, '<', $phits_erg;
    foreach (<$phits_erg_fh>) {
        next unless /^\s*[0-9]/;
        s/^\s+//;
        push @{$mc_flues{erg}{ev}},      (split)[0] * 1e6;
        push @{$mc_flues{erg}{mega_ev}}, (split)[0];
        push @{$mc_flues{$k}},           (split)[2]; # $k == momet, moo2, moo3
    }
    
    #++++ Debugging ++++#
#    say @{$mc_flues{$k}} * 1;
    #+++++++++++++++++++#
    
    chdir $where_prog_began;
}


sub calc_yield_and_specific_yield {
    my($keys_of_mo_targets, $_enri_of_int) = @_;
    # Check if the current enrichment ratio matches one of the user-designated
    # enrichment ratios for which PWM files will be written.
    my $is_enri_of_int_for_pwm =
        grep { $_enri_of_int == $_ } @{$pwm_enris_of_int{user}};
    if ($is_enri_of_int_for_pwm) {
        # The two keys 'user' and 'matched' are used as the grep conditional
        # is a numerical comparison, which will, for example, return true
        # for a comparison of 0.1 and 0.10.
        push @{$pwm_enris_of_int{matched}}, $_enri_of_int;
    }
    
    #
    # Calculate yield and specific yield for each Mo target designated.
    #
    foreach my $k (@$keys_of_mo_targets) {
        #
        # Array size validation
        #
        if (@{$xs{micro}{'cm^2'}} * 1 != @{$mc_flues{$k}} * 1) {
            croak "\n\nNonidentical array sizes:\n".
                  "\@{\$xs{micro}{'cm^2'}} array size: [".
                  (@{$xs{micro}{'cm^2'}} * 1)."]\n".
                  "\@{\$mc_flues{$k}} array size: [".
                  (@{$mc_flues{$k}} * 1)."]";
        }
        
        # Memorize the number density of the target nuclide
        # for designated enrichment ratios.
        # > The key of $_enri_of_int is to be autovivified.
        # > These data will be written to reporting files at
        #   write_to_pwm_data_files().
        # > Use format specifiers.
        if ($is_enri_of_int_for_pwm) {
            $pwm{$k}{$_enri_of_int}{'mo_'.$mo_isot_of_int} = sprintf(
                "$format_specifiers{num_dens}",
                $mo_targets{$k}{'mo_'.$mo_isot_of_int}{num_dens}
            );
        }
        
        #
        # (1) "Under the integral" -> PWM
        # Caution: Use the cm^2 xs, not the original barn one.
        #
        
        # Initialize cumulative sums.
        $pwm{$k}{micro_gross} = $pwm{$k}{macro_gross} = 0;
        
        for (my $i=0; $i<=$#{$xs{micro}{'cm^2'}}; $i++) {
            # Skip a negative xs, which can result from gnuplot extrapolation.
            # (gnuplot extrapolation takes places when its interpolation
            # exceeds the last energy bin.)
            next if $xs{micro}{'cm^2'}[$i] < 0;
            
            # microscopic --> macroscopic xs
            $xs{macro}{'cm^-1'}[$i] =
                $xs{micro}{'cm^2'}[$i]
                 * $mo_targets{$k}{'mo_'.$mo_isot_of_int}{num_dens};
            
            # Perform pointwise multiplication.
            $pwm{$k}{micro}[$i] = $xs{micro}{'cm^2'}[$i]  * $mc_flues{$k}[$i];
            $pwm{$k}{macro}[$i] = $xs{macro}{'cm^-1'}[$i] * $mc_flues{$k}[$i];
            
            # Memorize PWM components for designated enrichment ratios.
            # > The key of $_enri_of_int is to be autovivified.
            # > These data will be written to reporting files at
            #   write_to_pwm_data_files().
            # > Use format specifiers.
            if ($is_enri_of_int_for_pwm) {
                # xs
                $pwm{$k}{$_enri_of_int}{xs_erg_ev}[$i] = sprintf(
                    "$format_specifiers{erg_ev}",
                    $xs{erg}{ev}[$i]
                );
                $pwm{$k}{$_enri_of_int}{xs_erg_mega_ev}[$i] = sprintf(
                    "$format_specifiers{erg_mega_ev}",
                    $xs{erg}{mega_ev}[$i]
                );
                $pwm{$k}{$_enri_of_int}{xs_micro}{barn}[$i] = sprintf(
                    "$format_specifiers{xs_micro}",
                    $xs{micro}{barn}[$i]
                );
                $pwm{$k}{$_enri_of_int}{xs_micro}{'cm^2'}[$i] = sprintf(
                    "$format_specifiers{xs_micro}",
                    $xs{micro}{'cm^2'}[$i]
                );
                $pwm{$k}{$_enri_of_int}{xs_macro}{'cm^-1'}[$i] = sprintf(
                    "$format_specifiers{xs_macro}",
                    $xs{macro}{'cm^-1'}[$i]
                );
                # MC fluence
                $pwm{$k}{$_enri_of_int}{mc_flues_erg_ev}[$i] = sprintf(
                    "$format_specifiers{erg_ev}",
                    $mc_flues{erg}{ev}[$i]
                );
                $pwm{$k}{$_enri_of_int}{mc_flues_erg_mega_ev}[$i] = sprintf(
                    "$format_specifiers{erg_mega_ev}",
                    $mc_flues{erg}{mega_ev}[$i]
                );
                $pwm{$k}{$_enri_of_int}{mc_flues}[$i] = sprintf(
                    "$format_specifiers{mc_flues}",
                    $mc_flues{$k}[$i]
                );
                # PWM
                $pwm{$k}{$_enri_of_int}{pwm_micro}[$i] = sprintf(
                    "$format_specifiers{pwm_micro}",
                    $pwm{$k}{micro}[$i]
                );
                $pwm{$k}{$_enri_of_int}{pwm_macro}[$i] = sprintf(
                    "$format_specifiers{pwm_macro}",
                    $pwm{$k}{macro}[$i]
                );
                # Reaction rates
                $pwm{$k}{$_enri_of_int}{beam_curr}[$i] = sprintf(
                    "$format_specifiers{beam_curr}",
                    $memorized{beam_curr}
                );
                $pwm{$k}{$_enri_of_int}{source_rate}[$i] = sprintf(
                    "$format_specifiers{source_rate}",
                    ($consts{micro_amp} * $memorized{beam_curr})
                );
                $pwm{$k}{$_enri_of_int}{reaction_rate_per_vol}[$i] = sprintf(
                    "$format_specifiers{reaction_rate}",
                    $pwm{$k}{macro}[$i]
                    * ($consts{micro_amp} * $memorized{beam_curr})
                );
                $pwm{$k}{$_enri_of_int}{mo_tar_vol}[$i] = sprintf(
                    "$format_specifiers{vol}",
                    $mo_targets{$k}{mo_tar}{vol}
                );
                $pwm{$k}{$_enri_of_int}{reaction_rate}[$i] = sprintf(
                    "$format_specifiers{reaction_rate}",
                    $pwm{$k}{macro}[$i]
                    * ($consts{micro_amp} * $memorized{beam_curr})
                    * $mo_targets{$k}{mo_tar}{vol}
                );
            }
        }
        
        # Obtain cumulative sums.
        $pwm{$k}{micro_gross} += $_ for @{$pwm{$k}{micro}}; #       source^-1
        $pwm{$k}{macro_gross} += $_ for @{$pwm{$k}{macro}}; # cm^-3 source^-1
        
        #
        # (2) Multiply the components outside the integral with
        #     the PWM obtained at (1), which will
        #     then be the yield of the product radionuclide.
        #
        # $calc_conds{product_nucl}: e.g. $mo{'99'}, $tc{'99m'}
        # Look up the 'key' and 'dec_const' keys of $mo{'99'} and $tc{'99m'}
        # to see what their values are and thereby how they are used here.
        #
        $mo_targets{$k}{$calc_conds{product_nucl}{key}}{yield} =
            (
                1 - exp(
                    -$calc_conds{product_nucl}{dec_const}  # h^-1
                    * $calc_conds{end_of_irr}{val}         # h
                )
            )
            * $mo_targets{$k}{mo_tar}{vol}                 # cm^3
            * ($consts{micro_amp} * $memorized{beam_curr}) # source s^-1
            * $pwm{$k}{macro_gross};                       # cm^-3 source^-1
        
        #
        # (3) Bq --> GBq
        #
        $mo_targets{$k}{$calc_conds{product_nucl}{key}}{yield} *= 1e-9;
        
        #
        # (4) Obtain the specific yield of the product radionuclide
        #     by dividing its yield by the mass of "Mo element"
        #     of a Mo target.
        #     > Caution: You must use the mass of Mo element,
        #       not that of a Mo target that would also contain
        #       oxygen mass if the Mo target is nonmetallic.
        #
        $mo_targets{$k}{$calc_conds{product_nucl}{key}}{sp_yield} =
            $mo_targets{$k}{$calc_conds{product_nucl}{key}}{yield}
            / $mo_targets{$k}{mo_elem}{mass}; # NOT {mo_tar}{mass}!
    }
}


sub adjust_num_of_decimal_places {
    my($ref_to_list) = @_;
    
    # Element and its isotopes
    if (ref $ref_to_list eq HASH) {
        foreach my $attr (keys %format_specifiers) {
            foreach my $subcomp (@{$ref_to_list->{isotopes}}, 'elem') {
                $ref_to_list->{$subcomp}{$attr} = sprintf(
                    "$format_specifiers{$attr}",
                    $ref_to_list->{$subcomp}{$attr}
                ) if $ref_to_list->{$subcomp}{$attr};
            }
        }
    }
    
    # Mo target and its subcomponents
    my $subcomps = [
        'mo_tar',
        'mo_elem',
        'mo_'.$mo_isot_of_int, # e.g. mo_100
    ];
    # $calc_conds{product_nucl}{key}: e.g. mo_99, tc_99m
    push @$subcomps, $calc_conds{product_nucl}{key} if $yield_for;
    if (ref $ref_to_list eq ARRAY) {
        foreach my $attr (keys %format_specifiers) {
            foreach my $target (@$ref_to_list) {
                foreach my $subcomp (@$subcomps) {
                    $mo_targets{$target}{$subcomp}{$attr} = sprintf(
                        "$format_specifiers{$attr}",
                        $mo_targets{$target}{$subcomp}{$attr}
                    ) if $mo_targets{$target}{$subcomp}{$attr};
                }
            }
        }
    }
}


sub write_to_data_files {
    my($k) = @_;
    my $arr_ref_to_data = $data_array_refs{$k};
    
    my $enrimo_flag = "$prog_info{titl}$mo_isot_of_int";
    my $subdir      = "./$enrimo_flag";
    mkdir $subdir unless -e $subdir;
    chdir $subdir;
    
    reduce_data(
        { # Settings
            rpt_formats => [
                'gp',
#                'tex',
#                'csv',
                'xlsx',
#                'json',
#                'yaml',
            ],
            rpt_bname => $yield_for ?
                sprintf(
                    "%s_%s_%s",
                    $enrimo_flag,
                    $calc_conds{reaction}{val},
                    $k
                ) : sprintf(
                    "%s_%s",
                    $enrimo_flag,
                    $k
                ),
            begin_msg => "collecting data info...",
            prog_info => \%prog_info,
            cmt_arr   => $yield_for ? [
                "-" x 69,
                " Yield calculation conditions",
                "-" x 69,
                # Reaction
                " Target:   $mo{$mo_isot_of_int}{symb}",
                " Reaction: $memorized{reaction}",
                "",
                # Beam parameters
                " Beam energy:        $memorized{beam_erg} eV",
                " Beam current:       $memorized{beam_curr} uA",
                " Beam radius (FWHM): $memorized{beam_rad} cm",
                " Irradiation time:   $memorized{end_of_irr} h",
                "",
                # Converter target
                $memorized{reaction} !~ /^p/i ? (
                    " Converter:     $memorized{converter}",
                    " Converter rad: $memorized{converter_rad}",
                    " Converter hgt: $memorized{converter_hgt}",
                    "",
                ) : "",
                # Mo target
                " Mo target:     $mo_targets{$k}{mo_tar}{symb}",
                " Mo target rad: $memorized{mo_tar_rad}",
                " Mo target hgt: $memorized{mo_tar_hgt}",
                " Mo target vol: $memorized{$k}{mo_tar}{vol}",
                "",
                # nps
                " maxcas: $memorized{maxcas}",
                " maxbch: $memorized{maxbch}",
                "",
                # xs and MC fluence energy range
                " emin: $memorized{emin}",
                " emax: $memorized{emax}",
                " ne:   $memorized{ne}",
                "",
                # Data files
                " Microscopic xs data: $memorized{micro_xs_dat}",
                " MC fluence data:     $memorized{$k}{mc_flue_dat}",
                "-" x 69,
            ] : [],
        },
        { # Columnar
            size     => $yield_for ? 13 : 9, # Used for column size validation
            heads    => $yield_for ?
                [
                    "Mass fraction of $mo{$mo_isot_of_int}{symb}",
                    "Mass fraction of $mo{elem}{symb}",
                    "Mass density of $mo_targets{$k}{mo_tar}{symb}",
                    "Number density of $mo_targets{$k}{mo_tar}{symb}",
                    "Mass density of $mo{elem}{symb}",
                    "Number density of $mo{elem}{symb}",
                    "Mass density of $mo{$mo_isot_of_int}{symb}",
                    "Number density of $mo{$mo_isot_of_int}{symb}",
                    "Density change coefficient of $mo{$mo_isot_of_int}{symb}",
                    # Yield-specific
                    "Yield of $calc_conds{product_nucl}{symb}",
                    "$mo_targets{$k}{mo_tar}{symb} mass",
                    "$mo{elem}{symb} mass",
                    (
#                        $memorized{reaction} =~ /^p/i ? # Equivalent
                        $calc_conds{product_nucl}{symb} =~ /^tc/i ?
                            "Yield of $calc_conds{product_nucl}{symb}".
                            " per Mo mass" :
                            "Specific yield of $calc_conds{product_nucl}{symb}"
                    ),
                ] : [
                    "Mass fraction of $mo{$mo_isot_of_int}{symb}",
                    "Mass fraction of $mo{elem}{symb}",
                    "Mass density of $mo_targets{$k}{mo_tar}{symb}",
                    "Number density of $mo_targets{$k}{mo_tar}{symb}",
                    "Mass density of $mo{elem}{symb}",
                    "Number density of $mo{elem}{symb}",
                    "Mass density of $mo{$mo_isot_of_int}{symb}",
                    "Number density of $mo{$mo_isot_of_int}{symb}",
                    "Density change coefficient of $mo{$mo_isot_of_int}{symb}",
                ],
            subheads => $yield_for ?
                [
                    "",
                    "",
                    "(g cm^{-3})",
                    "(cm^{-3})",
                    "(g cm^{-3})",
                    "(cm^{-3})",
                    "(g cm^{-3})",
                    "(cm^{-3})",
                    "(Initial $mo{$mo_isot_of_int}{symb} mass frac: $dcc_init)",
                    # Yield-specific
                    sprintf(
                        "(GBq %suA^{-1})",
                        $memorized{beam_curr} > 1 ?
                            "$memorized{beam_curr}-" : ""
                    ),
                    "(g)",
                    "(g)",
                    sprintf(
                        "(GBq %suA^{-1} g^{-1})",
                        $memorized{beam_curr} > 1 ?
                            "$memorized{beam_curr}-" : ""
                    ),
                ] : [
                    "",
                    "",
                    "(g cm^{-3})",
                    "(cm^{-3})",
                    "(g cm^{-3})",
                    "(cm^{-3})",
                    "(g cm^{-3})",
                    "(cm^{-3})",
                    "(Initial $mo{$mo_isot_of_int}{symb} mass frac: $dcc_init)",
                ],
            data_arr_ref              => $arr_ref_to_data,
#            sum_idx_multiples         => [3..5], # Can be discrete,
#            ragged_left_idx_multiples => [2..5], # but must be increasing
            space_bef                 => {gp => " ", tex => " "},
            heads_sep                 => {gp => "|", csv => ","},
            space_aft                 => {gp => " ", tex => " "},
            data_sep                  => {gp => " ", csv => ","},
        }
    );
    
    chdir $where_prog_began;
}


sub write_to_pwm_data_files {
    my($k) = @_;
    
    my $erg_unit = 'MeV'; # eV, MeV
    
    my $enrimo_flag = "$prog_info{titl}$mo_isot_of_int";
    my $subdir      = "./$enrimo_flag";
    mkdir $subdir unless -e $subdir;
    chdir $subdir;
    
    foreach my $enri_of_int (@{$pwm_enris_of_int{matched}}) {
        my $arr_ref_to_data = [];
        (my $fname_flag = $enri_of_int) =~ s/[.]/p/;
        
        for (my $i=0; $i<=$#{$pwm{$k}{$enri_of_int}{xs_erg_ev}}; $i++) {
            push @$arr_ref_to_data,
                $pwm{$k}{$enri_of_int}{
                    $erg_unit eq 'MeV' ?
                        'xs_erg_mega_ev' : 'xs_erg_ev'
                }[$i],
                $pwm{$k}{$enri_of_int}{xs_micro}{barn}[$i],
                $pwm{$k}{$enri_of_int}{xs_micro}{'cm^2'}[$i],
                $pwm{$k}{$enri_of_int}{'mo_'.$mo_isot_of_int},
                $pwm{$k}{$enri_of_int}{xs_macro}{'cm^-1'}[$i],
                $pwm{$k}{$enri_of_int}{
                    $erg_unit eq 'MeV' ?
                        'mc_flues_erg_mega_ev' : 'mc_flues_erg_ev'
                }[$i],
                $pwm{$k}{$enri_of_int}{mc_flues}[$i],
                $pwm{$k}{$enri_of_int}{pwm_micro}[$i],
                $pwm{$k}{$enri_of_int}{pwm_macro}[$i],
                $pwm{$k}{$enri_of_int}{beam_curr}[$i],
                $pwm{$k}{$enri_of_int}{source_rate}[$i],
                $pwm{$k}{$enri_of_int}{reaction_rate_per_vol}[$i],
                $pwm{$k}{$enri_of_int}{mo_tar_vol}[$i],
                $pwm{$k}{$enri_of_int}{reaction_rate}[$i];
        }
        
        reduce_data(
            { # Settings
                rpt_formats => [
                    'gp',
#                    'tex',
#                    'csv',
                    'xlsx',
#                    'json',
#                    'yaml',
                ],
                rpt_bname => sprintf(
                    "%s_%s_%s_enri%s",
                    $enrimo_flag,
                    $calc_conds{reaction}{val},
                    $k,
                    $fname_flag
                ),
                begin_msg => "collecting PWM data info...",
                prog_info => \%prog_info,
                cmt_arr   => [
                    "-" x 69,
                    " Yield calculation conditions",
                    "-" x 69,
                    # Reaction
                    (
                        " Target:   $mo{$mo_isot_of_int}{symb}".
                        " (Enrichment ratio: $enri_of_int)"
                    ),
                    " Reaction: $memorized{reaction}",
                    "",
                    # Beam parameters
                    " Beam energy:        $memorized{beam_erg} eV",
                    " Beam current:       $memorized{beam_curr} uA",
                    " Beam radius (FWHM): $memorized{beam_rad} cm",
                    " Irradiation time:   $memorized{end_of_irr} h",
                    "",
                    # Converter target
                    $memorized{reaction} !~ /^p/i ? (
                        " Converter:     $memorized{converter}",
                        " Converter rad: $memorized{converter_rad}",
                        " Converter hgt: $memorized{converter_hgt}",
                        "",
                    ) : "",
                    # Mo target
                    " Mo target:     $mo_targets{$k}{mo_tar}{symb}",
                    " Mo target rad: $memorized{mo_tar_rad}",
                    " Mo target hgt: $memorized{mo_tar_hgt}",
                    " Mo target vol: $memorized{$k}{mo_tar}{vol}",
                    "",
                    # nps
                    " maxcas: $memorized{maxcas}",
                    " maxbch: $memorized{maxbch}",
                    "",
                    # xs and MC fluence energy range
                    " emin: $memorized{emin}",
                    " emax: $memorized{emax}",
                    " ne:   $memorized{ne}",
                    "",
                    # Data files
                    " Microscopic xs data: $memorized{micro_xs_dat}",
                    " MC fluence data:     $memorized{$k}{mc_flue_dat}",
                    "-" x 69,
                ],
            },
            { # Columnar
                size     => 14, # Used for column size validation
                heads    => [
                    "xs energy",
                    "Microscopic xs",
                    "Microscopic xs",
                    "Number density of $mo{$mo_isot_of_int}{symb}",
                    "Macroscopic xs",
                    "MC fluence energy",
                    "MC fluence",
                    "PWM for microscopic xs",
                    "PWM for macroscopic xs",
                    "Beam current",
                    "Source rate",
                    "Reaction rate per $mo_targets{$k}{mo_tar}{symb} volume",
                    "Volume of $mo_targets{$k}{mo_tar}{symb}",
                    "Reaction rate",
                ],
                subheads => [
                    $erg_unit eq 'MeV' ? "(MeV)" : "(eV)",
                    "(b)",
                    "(cm^{2})",
                    "(cm^{-3})",
                    "(cm^{-1})",
                    $erg_unit eq 'MeV' ? "(MeV)" : "(eV)",
                    "(cm^{-2} source^{-1})",
                    "(source^{-1})",
                    "(cm^{-3} source^{-1})",
                    "(uA)",
                    "(source s^{-1})",
                    "(cm^{-3} s^{-1})",
                    "(cm^{3})",
                    "(s^{-1} or Bq)",
                ],
                data_arr_ref              => $arr_ref_to_data,
                sum_idx_multiples         => [6..8, 11, 13], # Can be discrete,
#                ragged_left_idx_multiples => [2..5], # but must be increasing
                space_bef                 => {gp => " ", tex => " "},
                heads_sep                 => {gp => "|", csv => ","},
                space_aft                 => {gp => " ", tex => " "},
                data_sep                  => {gp => " ", csv => ","},
            }
        );
    }
    
    chdir $where_prog_began;
}


#
# Subroutines from My::Toolset
#
sub show_front_matter {
    my $hash_ref = shift; # Arg 1: To be %_prog_info
    
    #
    # Data type validation and deref: Arg 1
    #
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be a hash ref!"
        unless ref $hash_ref eq HASH;
    my %_prog_info = %$hash_ref;
    
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
    my @_fm;
    my $k = 0;
    my $border_len = $lead_symb ? 69 : 70;
    my %borders = (
        '+' => $lead_symb.('+' x $border_len).$newline,
        '*' => $lead_symb.('*' x $border_len).$newline,
    );
    
    # Top rule
    if ($is_prog or $is_auth) {
        $_fm[$k++] = $borders{'+'};
    }
    
    # Program info, except the usage
    if ($is_prog) {
        $_fm[$k++] = sprintf(
            "%s%s %s: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $_prog_info{titl},
            $_prog_info{vers},
            $_prog_info{expl},
            $newline
        );
        $_fm[$k++] = sprintf(
            "%s%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            'Last update:'.($is_timestamp ? '  ': ' '),
            $_prog_info{date_last},
            $newline
        );
    }
    
    # Timestamp
    if ($is_timestamp) {
        my %_datetimes = construct_timestamps('-');
        $_fm[$k++] = sprintf(
            "%sCurrent time: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $_datetimes{ymdhms},
            $newline
        );
    }
    
    # Author info
    if ($is_auth) {
        $_fm[$k++] = $lead_symb.$newline if $is_prog;
        $_fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $_prog_info{auth}{$_},
            $newline
        ) for qw(name posi affi mail);
    }
    
    # Bottom rule
    if ($is_prog or $is_auth) {
        $_fm[$k++] = $borders{'+'};
    }
    
    # Program usage: Leading symbols are not used.
    if ($is_usage) {
        $_fm[$k++] = $newline if $is_prog or $is_auth;
        $_fm[$k++] = $_prog_info{usage};
    }
    
    # Feed a blank line at the end of the front matter.
    if (not $is_no_trailing_blkline) {
        $_fm[$k++] = $newline;
    }
    
    #
    # Print the front matter.
    #
    if ($is_copy) {
        return @_fm;
    }
    elsif (not $is_copy) {
        print for @_fm;
    }
}


sub show_elapsed_real_time {
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
    @opts    = grep !$dels{$_}, @opts;
    
    # Optional strings printing
    print for @opts;
    
    # Elapsed real time printing
    my $elapsed_real_time = sprintf("Elapsed real time: [%s s]", time - $^T);
    
    # Return values
    say    $elapsed_real_time if not $is_return_copy;
    return $elapsed_real_time if     $is_return_copy;
}


sub construct_timestamps {
    # Optional setting for the date component separator
    my $_date_sep  = '';
    
    # Terminate the program if the argument passed
    # is not allowed to be a delimiter.
    my @_delims = ('-', '_');
    if ($_[0]) {
        $_date_sep = $_[0];
        my $is_correct_delim = grep $_date_sep eq $_, @_delims;
        croak "The date delimiter must be one of: [".join(', ', @_delims)."]"
            unless $is_correct_delim;
    }
    
    # Construct and return a datetime hash.
    my $_dt  = DateTime->now(time_zone => 'local');
    my $_ymd = $_dt->ymd($_date_sep);
    my $_hms = $_dt->hms(($_date_sep ? ':' : ''));
    (my $_hm = $_hms) =~ s/[0-9]{2}$//;
    
    my %_datetimes = (
        none   => '', # Used for timestamp suppressing
        ymd    => $_ymd,
        hms    => $_hms,
        hm     => $_hm,
        ymdhms => sprintf("%s%s%s", $_ymd, ($_date_sep ? ' ' : '_'), $_hms),
        ymdhm  => sprintf("%s%s%s", $_ymd, ($_date_sep ? ' ' : '_'), $_hm),
    );
    
    return %_datetimes;
}


sub construct_range {
    my $array_ref  = $_[0]; # Arg 1: To be @_range
    my $scalar_ref = $_[1]; # Arg 2: (OPTIONAL) To be $_line
    
    #
    # Data type validation and deref: Arg 1
    #
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be an array ref!"
        unless ref $array_ref eq ARRAY;
    my @_range = @$array_ref;
    
    #
    # Data type validation and deref: Arg 2
    #
    my $_line;
    if ($scalar_ref) {
        croak "The 2nd arg to [$_sub_name] must be a scalar ref!"
            unless ref $scalar_ref eq SCALAR;
        $_line = $$scalar_ref;
    }
    
    #
    # Terminate the program if more than one decimal point
    # has been passed for a single number.
    #
    foreach (@_range) {
        if (/[.]{2,}/) {
            print $_line ? "=> [$_line]" : "";
            croak "More than one decimal point! Terminating";
        }
    }
    
    #
    # Check if the given list of numbers contains a decimal.
    # This affects many of the following statements.
    #
    my @num_of_decimals = grep /[.]/, @_range;
    
    #
    # Pad "integer" 0 to the omitted for correct range construction.
    #
    if (@num_of_decimals) {
        foreach (@_range) {
            s/(^[.][0-9]+)/0$1/ if /^[.][0-9]+/;
        }
    }
    
    #
    # Populate min, max, (and optionally) incre.
    # (Dependent on whether a decimal is involved)
    #
    my $_range_num_input = @_range;
    my($min, $incre, $max);
    
    if ($_range_num_input == 3) {
        ($min, $incre, $max) = @_range;
        #
        # Terminate the program if $max is zero.
        #
        if (not $max) {
            print $_line ? "=> [$_line]" : "";
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
    if ($_range_num_input == 2 or $incre == -1) {
        ($min, $max) = @_range[0, -1]; # Slicing for empty $incre
        
        # Define the increment.
        # (i)  For decimals, the longest decimal places are used.
        #      e.g. 0.1,  0.20 --> Increment: 0.01
        #           0.05, 0.2  --> Increment: 0.01
        #           0.3,  0.5  --> Increment: 0.1
        # (ii) For integers, the increment is 1.
        if (@num_of_decimals) {
            my $power_of_ten;
            my $power_of_ten_largest = 0;
            
            foreach (@_range) {
                $power_of_ten = index((reverse $_), '.');
                $power_of_ten_largest = $power_of_ten > $power_of_ten_largest ?
                    $power_of_ten : $power_of_ten_largest;
            }
            $incre = 10**-$power_of_ten_largest;
        }
        elsif (not @num_of_decimals) {
            $incre  = 1;
        }
    }
    unless ($_range_num_input == 3 or $_range_num_input == 2) {
        print $_line ? "=> [$_line]" : "";
        croak "We need 2 or 3 numbers to construct a range! Terminating";
    }
    
    #
    # Terminate the program if the number passed as the min
    # is bigger than the number passed as the max.
    #
    if ($min > $max) {
        print $_line ? "=> [$_line]" : "";
        croak "$min is bigger than $max! Terminating";
    }
    
    #
    # Find the lengthiest number to construct a convert.
    # (Dependent on whether a decimal is involved)
    #
    my $lengthiest = '';
    foreach (@_range) {
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
    # If a decimal is involved, increase the powers of 10 of the list of
    # numbers by a equal factor such that the decimal with the largest decimal
    # places becomes an integer.
    # e.g. 0.10,0.001,0.11 => 100, 1, 110
    # The powers of 10 of the list of numbers will then be decreased
    # to the original ones after range construction by a C-like for loop.
    # This is done because floating numbers cannot be correctly compared.
    #
    if (@num_of_decimals) {
        $_ *= 10**length($lengthiest) for ($min, $incre, $max);
    }
    
    @{$_[0]} = (); # Empty the array ref for its refilling.
    for (my $i=$min; $i<=$max; $i+=$incre) {
        push @{$_[0]}, sprintf(
            "$conv",
            (
                @num_of_decimals ?
                    $i / 10**length($lengthiest):
                    $i
            )
        );
    }
}


sub validate_argv {
    my $hash_ref  = shift; # Arg 1: To be %_prog_info
    my $array_ref = shift; # Arg 2: To be @_argv
    my $num_of_req_argv;   # Arg 3: (OPTIONAL) Number of required args
    $num_of_req_argv = shift if defined $_[0];
    
    #
    # Data type validation and deref: Arg 1
    #
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be a hash ref!"
        unless ref $hash_ref eq HASH;
    my %_prog_info = %$hash_ref;
    
    #
    # Data type validation and deref: Arg 2
    #
    croak "The 2nd arg to [$_sub_name] must be an array ref!"
        unless ref $array_ref eq ARRAY;
    my @_argv = @$array_ref;
    
    #
    # Terminate the program if the number of required arguments passed
    # is not sufficient.
    # (performed only when the 3rd optional argument is given)
    #
    if ($num_of_req_argv) {
        my $num_of_req_argv_passed = grep $_ !~ /-/, @_argv;
        if ($num_of_req_argv_passed < $num_of_req_argv) {
            say $_prog_info{usage};
            say "    | You have input $num_of_req_argv_passed required args,".
                " but we need $num_of_req_argv.";
            say "    | Please refer to the usage above.";
            exit;
        }
    }
    
    #
    # Count the number of correctly passed options.
    #
    
    # Non-fnames
    my $num_of_corr_opts = 0;
    foreach my $arg (@_argv) {
        foreach my $v (values %{$_prog_info{opts}}) {
            if ($arg =~ /$v/i) {
                $num_of_corr_opts++;
                next;
            }
        }
    }
    
    # Fname-likes
    my $num_of_fnames = 0;
    $num_of_fnames = grep $_ !~ /^-/, @_argv;
    $num_of_corr_opts += $num_of_fnames;
    
    # Warn if "no" correct options have been passed.
    if ($num_of_corr_opts == 0) {
        say $_prog_info{usage};
        say "    | None of the command-line options was correct.";
        say "    | Please refer to the usage above.";
        exit;
    }
}


sub pause_shell {
    my $notif = $_[0] ? $_[0] : "Press enter to exit...";
    
    print $notif;
    while (<STDIN>) { last; }
}


sub reduce_data {
    #
    # Available formats
    # [1] gp
    #   - Can be plotted by gnuplot
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
        gp   => qr/^gp$/i,
        tex  => qr/^tex$/i,
        csv  => qr/^csv$/i,
        xlsx => qr/^xlsx$/i,
        json => qr/^json$/i,
        yaml => qr/^yaml$/i,
    );
    my %sets = (
        rpt_formats => ['gp', 'tex'],
        rpt_bname   => "rpt",
        begin_msg   => "generating data reduction reports...",
    );
    my %cols;
    my %rows;
    my %strs = ( # Not to be modified via the user arguments
        symbs    => {gp => "#",    tex => "%"   },
        eofs     => {gp => "#eof", tex => "%eof"},
        nan      => {
            gp   => "NaN",
            tex  => "{}",
            csv  => "",
            xlsx => "",
            json => "", # Not related to its 'null'
            yaml => "", # Not related to its '~'
        },
        newlines => {
            gp   => "\n",
            tex  => " \\\\\n",
            csv  => "\n",
        },
        indents  => {gp => "", tex => "  "},
        rules    => {
            gp   => {}, # To be constructed
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
    
    #
    # Argument data type validation and dereferencing
    # Some of the default attributes of %sets and %cols,
    # if given, are overridden here.
    #
    my $sets_hash_ref = shift;
    my $cols_hash_ref = shift;
    my $_sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg to [$_sub_name] must be a hash ref!"
        unless ref $sets_hash_ref eq HASH;
    croak "The 2nd arg to [$_sub_name] must be a hash ref!"
        unless ref $cols_hash_ref eq HASH;
    $sets{$_} = $sets_hash_ref->{$_} for keys %$sets_hash_ref;
    $cols{$_} = $cols_hash_ref->{$_} for keys %$cols_hash_ref;
    
    #
    # Data format validation
    #
    foreach my $rpt_format (@{$sets{rpt_formats}}) {
        next if (first { $rpt_format =~ $_ } values %flags);
        croak
            "[$_sub_name]: [$rpt_format]".
            " is not a valid element of rpt_formats.\n".
            "Available formats are: ".
            join(", ", sort keys %flags)."\n";
    }
    
    #
    # Column size validation
    #
    croak "[$_sub_name]: Column size must be provided via the size key."
        unless defined $cols{size};
    croak "[$_sub_name]: Column size must be a positive integer."
        if $cols{size} <= 0 or $cols{size} =~ /[.]/;
    foreach (qw(heads subheads data_arr_ref)) {
        unless (@{$cols{$_}} % $cols{size} == 0) {
            croak
                "[$_sub_name]\nColumn size [$_] is found to be".
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
    #   Original: space_bef => {gp => " ", tex => " "}
    #   User-arg: space_bef => {gp => " "}
    #   Defined:  space_bef => {gp => " "}
    #   The tex => " " pair would not be available hereafter.
    # > To avoid such loss, default key-val pairs are defined
    #   altogether below.
    # > This also allows the TeX separators, which must be
    #   the ampersand (&), immutable. That is, even if the following
    #   arguments are passed, the TeX separators will remain unchanged:
    #   User-arg: heads_sep => {gp => "|", csv => ";", tex => "|"}
    #             data_sep  => {gp => " ", csv => ";", tex => " "}
    #   Defined:  heads_sep => {gp => "|", csv => ";", tex => "&"}
    #             data_sep  => {gp => " ", csv => ";", tex => "&"}
    # > Finally, the headings separators for gnuplot and TeX are
    #   enclosed with the designated space characters.
    #   (i.e. space_bef and space_aft)
    # > CSV separators can be set via the user arguments,
    #   as its module defines such a method,
    #   but are not surrounded by any space characters.
    # > XLSX, as written in binaries, has nothing to do here.
    #
    
    # gnuplot
    $cols{space_bef}{gp}  = " " unless exists $cols{space_bef}{gp};
    $cols{heads_sep}{gp}  = "|" unless exists $cols{heads_sep}{gp};
    $cols{space_aft}{gp}  = " " unless exists $cols{space_aft}{gp};
    $cols{data_sep}{gp}   = " " unless exists $cols{data_sep}{gp};
    # TeX
    $cols{space_bef}{tex} = " " unless exists $cols{space_bef}{tex};
    $cols{heads_sep}{tex} = "&"; # Immutable
    $cols{space_aft}{tex} = " " unless exists $cols{space_aft}{tex};
    $cols{data_sep}{tex}  = "&"; # Immutable
    # gnuplot, TeX
    foreach (qw(gp tex)) {
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
    say "#"." [$_sub_name] $sets{begin_msg}";
    say "#".('=' x 69);
    
    #
    # Multiplex outputting
    # IO::Tee intentionally not used for avoiding its additional installation
    #
    
    # Define filehandle refs and corresponding filenames.
    my($gp_fh, $tex_fh, $csv_fh, $xlsx_fh);
    my %rpt_formats = (
        gp   => {fh => $gp_fh,   fname => $sets{rpt_bname}.".dat" },
        tex  => {fh => $tex_fh,  fname => $sets{rpt_bname}.".tex" },
        csv  => {fh => $csv_fh,  fname => $sets{rpt_bname}.".csv" },
        xlsx => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".xlsx"},
        json => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".json"},
        yaml => {fh => $xlsx_fh, fname => $sets{rpt_bname}.".yaml"},
    );
    
    # Multiple invocations of the writing routine
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
        say "[$rpt_formats{$_}{fname}] generated.";
    }
    
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
            
            # As of v0.98, a format property can be added in the middle,
            # but cannot be overridden. The author of this routine therefore
            # use cellwise formats to specify "ruled" and "aligned" cells.
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
        }
        
        #
        # Data construction
        #
        
        # [gnuplot] Prepend comment symbols to the first headings.
        if ($_flag =~ $_flags{gp}) {
            $_cols{heads}[0]    = $_strs{symbs}{$_flag}." ".$_cols{heads}[0];
            $_cols{subheads}[0] = $_strs{symbs}{$_flag}." ".$_cols{subheads}[0];
        }
        if ($_flag !~ $_flags{gp}) { # Make it unaffected by the prev gp call
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
        # [gnuplot] Border construction
        #
        if ($_flag =~ $_flags{gp}) {
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
        # [JSON][YAML]:   Via their dumping commands.
        # [gnuplot][TeX]: Via the output filehandle.
        # [CSV][XLSX]:    Via their output methods.
        #
        
        # [JSON][YAML][gnuplot][TeX] Change the output filehandle from STDOUT.
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
        
        # [gnuplot][TeX] OPTIONAL blocks
        if ($_flag =~ /$_flags{gp}|$_flags{tex}/) {
            # Prepend the program information, if given.
            if ($_sets{prog_info}) {
                show_front_matter(
                    $_sets{prog_info},
                    'prog',
                    'auth',
                    'timestamp',
                    ($_strs{symbs}{$_flag} // $_strs{symbs}{gp}),
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
        
        # [gnuplot][TeX] Top rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{top}, "\n"
            if $_flag =~ /$_flags{gp}|$_flags{tex}/;
        
        #
        # Headings and subheadings
        #
        
        # [gnuplot][TeX]
        for (my $j=0; $j<=$#{$_cols{heads}}; $j++) {
            if ($_flag =~ /$_flags{gp}|$_flags{tex}/) {
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
            if ($_flag =~ /$_flags{gp}|$_flags{tex}/) {
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
        
        # [gnuplot][TeX] Middle rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{mid}, "\n"
            if $_flag =~ /$_flags{gp}|$_flags{tex}/;
        
        #
        # Data
        #
        # > [XLSX] is now handled together with [gnuplot][TeX]
        #   to allow columnwise alignment. That is, the write() method
        #   is used instead of the write_row() one.
        # > Although MS Excel by default aligns numbers ragged left,
        #   the author wanted to provide this routine with more flexibility.
        # > According to the Excel::Writer::XLSX manual,
        #   AutoFit can only be performed from within Excel.
        #   By the use of write(), however, pseudo-AutoFit is also realized:
        #   The author has created this routine initially for gnuplot and
        #   TeX tabular data, and for them he added an automatic conversion
        #   creation functionality. Utilizing the conversion width,
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
            # [gnuplot][TeX][XLSX]
            $xlsx_col = $xlsx_col_init;
            for (my $j=0; $j<=$_cols{idx_multiple}; $j++) {
                # [gnuplot][TeX]
                if ($_flag =~ /$_flags{gp}|$_flags{tex}/) {
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
        
        # [gnuplot][TeX] Bottom rule
        print $_strs{indents}{$_flag}, $_strs{rules}{$_flag}{bot}, "\n"
            if $_flag =~ /$_flags{gp}|$_flags{tex}/;
        
        #
        # Append the data sums.
        #
        if (defined $_cols{sum_idx_multiples}) {
            #
            # [gnuplot] Columns "up to" the beginning of the data sums
            #
            if ($_flag =~ $_flags{gp}) {
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
            
            # [gnuplot][TeX][XLSX]
            my $the_beginning = $_flag !~ $_flags{gp} ?
                0 : $_cols{sum_idx_multiples}[0];
            $xlsx_col = $xlsx_col_init;
            for (my $j=$the_beginning; $j<=$_cols{sum_idx_multiples}[-1]; $j++)
            {
                # [gnuplot][TeX]
                if ($_flag =~ /$_flags{gp}|$_flags{tex}/) {
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
        
        # [gnuplot][TeX] EOF
        print $_strs{eofs}{$_flag} if $_flag =~ /$_flags{gp}|$_flags{tex}/;
        
        # [JSON][YAML][gnuplot][TeX] Restore the output filehandle to STDOUT.
        select(STDOUT);
        
        # Close the filehandle.
        # the XLSX filehandle must be closed via its close method!
        close $_fh         if $_flag !~ $_flags{xlsx};
        $workbook->close() if $_flag =~ $_flags{xlsx};
    }
}


sub calculate_volume {
    my($geom, @dims) = @_;
    my $vol;
    my $_sub_name = join('::', (caller(0))[0, 3]);
    
    # Right circular cylinder (RCC)
    if ($geom =~ /rcc/i) {
        my($rad, $hgt) = @dims;
        
        $vol = PI * $rad**2 * $hgt;
    }
    
    # Truncated right circular cylinder cone (TRC)
    # a.k.a. A conical frustum, a frustum of a cone
    elsif ($geom =~ /trc/i) {
        my($rad1, $rad2, $hgt) = @dims;
        
        $vol = PI/3 * $rad1**2 + $rad1*$rad2 + $rad2**2 * $hgt;
    }
    
    else { say "[$_sub_name] cannot calculate [$geom]."; }
    
    return $vol;
}


#
# Subroutines from My::Nuclear
#
sub enrich_or_deplete {
    my(
        $hash_ref_to_elem, # A hash ref containing $isot_of_int as its key
        $isot_of_int,      # The isotope that will be enriched or depleted
        $new_mass_frac,    # The requested enrichment ratio of the isotope
        $is_verbose        # Display the redistribution status in real time
    ) = @_;
    my(
        $to_be_transferred,      # Mass frac for arithmetic operations
        $to_be_transferred_copy, # Mass frac to be added to the isotope of int
        $remainder               # New value of $to_be_transferred
    );
    $to_be_transferred      =
    $to_be_transferred_copy =
        $new_mass_frac - $hash_ref_to_elem->{$isot_of_int}{mass_frac};
    my $old_mass_frac; # Printing purposes only
    
    #
    # Show the isotope of interest and its planned mass fraction change
    #
    if ($is_verbose) {
        printf(
            "\n%s()\n".
            "redistributing mass fractions...\n\n",
            join('::', (caller(0))[0, 3]),
        );
        print "=" x 70, "\n";
        printf(
            "Isotope of interest: [%s]\n".
            "mass_frac: [%.5f] --> [%.5f]\n",
            $hash_ref_to_elem->{$isot_of_int}{symb},
            $hash_ref_to_elem->{$isot_of_int}{mass_frac},
            $new_mass_frac
        );
        print "=" x 70, "\n";
        # Reporting
        printf(
            "%-18s: [%.5f]\n",
            'mass_frac',
            $hash_ref_to_elem->{$isot_of_int}{mass_frac}
        );
        printf(
            "%-18s: [%.5f]\n",
            '$to_be_transferred',
            $to_be_transferred
        );
        print "\n";
    }
    
    #
    # Redistribute the mass fractions of the isotopes.
    #
    foreach my $isot (@{$hash_ref_to_elem->{isotopes}}) {
        # Remember the mass fraction of an isotope before its redistribution.
        $old_mass_frac = $hash_ref_to_elem->{$isot}{mass_frac};
        
        # Show the current isotope.
        if ($is_verbose) {
            print "-" x 70, "\n";
            print "Isotope: [$hash_ref_to_elem->{$isot}{symb}]\n";
            print "-" x 70, "\n";
        }
        
        #
        # Arithmetics for the isotope of interest (to be enriched or depleted)
        #
        if ($isot =~ /$isot_of_int/i) {
            $hash_ref_to_elem->{$isot}{mass_frac} += $to_be_transferred_copy;
            if ($is_verbose) {
                printf(
                    "%-18s: [%.5f] --> [%.5f]\n",
                    'mass_frac',
                    $old_mass_frac,
                    $hash_ref_to_elem->{$isot}{mass_frac}
                );
                print "\n";
            }
            # The mass fraction of the isotope of interest has already been 
            # modified above (see +=); jump to the next isotope.
            next;
        }
        
        #
        # Arithmetics for the rest of the isotopes
        #
        # (i)  c = a - b for a >= b
        # (ii) c = b - a for b >  a
        # where
        # c
        #   > $remainder
        #   > The one that will be the value of $to_be_transferred or 'a'
        #     at the next isotope
        # a
        #   > $to_be_transferred
        #   > The amount of mass fraction to be transferred
        #     from the current isotope to the isotope of interest
        # b
        #   > $hash_ref_to_elem->{$isot}{mass_frac}
        #   > The mass fraction of the current isotope
        #
        
        # (i) c = a - b for a >= b
        if ($to_be_transferred >= $hash_ref_to_elem->{$isot}{mass_frac}) {
            # c = a - b
            $remainder =
                $to_be_transferred - $hash_ref_to_elem->{$isot}{mass_frac};
            # b = 0, meaning that the current isotope has been depleted.
            $hash_ref_to_elem->{$isot}{mass_frac} = 0;
            # a = c
            $to_be_transferred = $remainder;
            # Reporting
            if ($is_verbose) {
                printf(
                    "%-18s: [%.5f] --> [%.5f]\n",
                    'mass_frac',
                    $old_mass_frac,
                    $hash_ref_to_elem->{$isot}{mass_frac}
                );
                printf(
                    "%-18s: [%.5f]\n",
                    '$to_be_transferred',
                    $to_be_transferred
                );
                print "\n";
            }
        }
        
        # (ii) c = b - a for b > a
        elsif ($to_be_transferred < $hash_ref_to_elem->{$isot}{mass_frac}) {
            if ($is_verbose) {
                printf(
                    "The isotope possesses a larger mass fraction, [%.5f],\n".
                    "than the mass fraction to be transferred,     [%.5f].\n".
                    "Hence, we now subtract [%.5f] from [%.5f].\n",
                    $hash_ref_to_elem->{$isot}{mass_frac},
                    $to_be_transferred,
                    $to_be_transferred,
                    $hash_ref_to_elem->{$isot}{mass_frac}
                );
            }
            # c = b - a
            $remainder =
                $hash_ref_to_elem->{$isot}{mass_frac} - $to_be_transferred;
            # b = c
            $hash_ref_to_elem->{$isot}{mass_frac} = $remainder;
            # a = 0, meaning that no mass fraction is left to be transferred.
            $to_be_transferred = 0;
            # Reporting
            if ($is_verbose) {
                printf(
                    "%-18s: [%.5f] --> [%.5f]\n",
                    'mass_frac',
                    $old_mass_frac,
                    $hash_ref_to_elem->{$isot}{mass_frac}
                );
                printf(
                    "%-18s: [%.5f]\n",
                    '$to_be_transferred',
                    $to_be_transferred
                );
                print "\n";
            }
        }
    }
    
    pause_shell("Press enter to continue...") if $is_verbose;
}
#eof