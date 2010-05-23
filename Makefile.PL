BEGIN{ require 5; } # use

use ExtUtils::MakeMaker;

open FH, ">Perl.xs" and close FH;


my $dist = 'Classic-Perl';

my %META = (
 configure_requires => {
  'ExtUtils::MakeMaker' => 0,
 },
 build_requires => {
  'ExtUtils::MakeMaker' => 0,
  'Test::More'          => 0,
 },
 resources => {
  bugtracker => "http://rt.cpan.org/NoAuth/ReportBug.html?Queue=$dist",
  license    => 'http://dev.perl.org/licenses/',
 },
);

WriteMakefile(
    NAME             => 'Classic::Perl',
    AUTHOR           => 'Father Chrysostomos <sprout at, er, cpan.org>',
    LICENSE          => 'perl',
    VERSION_FROM     => 'lib/Classic/Perl.pm',
    ABSTRACT_FROM    => 'lib/Classic/Perl.pm',
    PREREQ_PM        => {
         Test'More => 0,
        'XSLoader' => 0,
    },
    MIN_PERL_VERSION => 5,
    META_MERGE       => \%META,
    dist             => {
        COMPRESS => 'gzip -9f', SUFFIX => 'gz',
        TAR => 'COPYFILE_DISABLE=1 tar',
    },
    clean            => {
        FILES => "$dist-* *.gcov *.gcda *.gcno cover_db Perl.xs"
    },
);

unlink 'Perl.xs';

use File'Spec'Functions;
sub MY'postamble {
  my $xs_file = catfile("xs", $] < 5.012 ? 'old.xs' : 'new.xs');
  <<END;
Perl.xs : $xs_file
	perl -MFile::Copy "-ecopy '$xs_file', 'Perl.xs'"
END
}

