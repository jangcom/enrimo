# enrimo

<?xml version="1.0" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<link rev="made" href="mailto:" />
</head>

<body>



<ul id="index">
  <li><a href="#NAME">NAME</a></li>
  <li><a href="#SYNOPSIS">SYNOPSIS</a></li>
  <li><a href="#DESCRIPTION">DESCRIPTION</a></li>
  <li><a href="#OPTIONS">OPTIONS</a></li>
  <li><a href="#EXAMPLES">EXAMPLES</a></li>
  <li><a href="#REQUIREMENTS">REQUIREMENTS</a></li>
  <li><a href="#SEE-ALSO">SEE ALSO</a></li>
  <li><a href="#AUTHOR">AUTHOR</a></li>
  <li><a href="#COPYRIGHT">COPYRIGHT</a></li>
  <li><a href="#LICENSE">LICENSE</a></li>
</ul>

<h1 id="NAME">NAME</h1>

<p>enrimo - Investigate the influence of an enriched Mo isotope</p>

<h1 id="SYNOPSIS">SYNOPSIS</h1>

<pre><code>    perl enrimo.pl [-materials=mo_mat ...] [-isotope=mo_isot]
                   [-enri_lev_type=frac_type] [-enri_lev_range=frac_range]
                   [-min_depl_lev_global=enri_lev] [-depl_order=option]
                   [-inp=fname] [-out_path=path] [-out_fmts=ext ...]
                   [-projectiles=particle ...]
                   [-verbose] [-nofm] [-nopause]</code></pre>

<h1 id="DESCRIPTION">DESCRIPTION</h1>

<pre><code>    This Perl program generates datasets for investigating the influence of
    an enriched Mo isotope on its associated Mo material, Mo element,
    and companion isotopes.
    The following quantities, as functions of the enrichment level of
    the Mo isotope to be enriched, are calculated for a Mo material:
    - Amount fractions and and mass fractions of Mo and O isotopes
    - Mass fractions of Mo and O elements
    - Mass and number densities of the Mo material, Mo and O elements,
      and their isotopes
    - Density change coefficients (DCCs) of Mo and O isotopes</code></pre>

<h1 id="OPTIONS">OPTIONS</h1>

<pre><code>    Multiple values are separated by the comma (,).

    -materials=mo_mat ... (short: -mats, default: momet)
        all
            All of the following mo_mat&#39;s.
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
        mo98  &lt;= Mo-98(n,g)Mo-99
        mo100 &lt;= Mo-100(g,n)Mo-99, Mo-100(n,2n)Mo-99, Mo-100(p,2n)Tc-99m

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
            All of the following ext&#39;s.
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
            Photon &lt;= Mo-100(g,n)Mo-99
        n
            Neutron &lt;= Mo-98(n,g)Mo-99, Mo-100(n,2n)Mo-99
        p
            Proton &lt;= Mo-100(p,2n)Tc-99m

    -verbose (short: -verb)
        Display the calculation process in real time. This will pause
        the shell each time a core calculation routine is called; use it
        only when debugging or checking part of the calculation process.

    -nofm
        The front matter will not be displayed at the beginning of program.

    -nopause
        The shell will not be paused at the end of program.
        Use it for a batch run.</code></pre>

<h1 id="EXAMPLES">EXAMPLES</h1>

<pre><code>    perl enrimo.pl -type=mass_frac -range=0,0.00001,1
    perl enrimo.pl -mats=moo3 -global=0.0005 -verb
    perl enrimo.pl -mats=momet,moo3 -range=0.0974,0.0001,0.9739 -inp=0p9739.enr</code></pre>

<h1 id="REQUIREMENTS">REQUIREMENTS</h1>

<pre><code>    Perl 5
        Text::CSV, Excel::Writer::XLSX, JSON, YAML</code></pre>

<h1 id="SEE-ALSO">SEE ALSO</h1>

<p><a href="https://github.com/jangcom/enrimo">enrimo on GitHub</a></p>

<p><a href="https://doi.org/10.5281/zenodo.2628760">enrimo on Zenodo</a></p>

<p><a href="https://iopscience.iop.org/article/10.1088/2399-6528/ab1d6b">enrimo in a paper: <i>J. Phys. Commun.</i> <b>3</b>, 055015</a></p>

<h1 id="AUTHOR">AUTHOR</h1>

<p>Jaewoong Jang &lt;jangj@korea.ac.kr&gt;</p>

<h1 id="COPYRIGHT">COPYRIGHT</h1>

<p>Copyright (c) 2018-2019 Jaewoong Jang</p>

<h1 id="LICENSE">LICENSE</h1>

<p>This software is available under the MIT license; the license information is found in &#39;LICENSE&#39;.</p>


</body>

</html>
