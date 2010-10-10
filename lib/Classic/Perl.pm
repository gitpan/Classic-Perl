package Classic::Perl;

my %features = map +($_ => undef)  =>=>  qw< split $* >;

sub import{
 shift;
 for(@_) {
  die
    "$_ is not a feature Classic::Perl knows about at "
    . join(" line ", (caller)[1,2]) . ".\n"
   unless exists$features{$_};
  next if $] < 5.0089999;
  $_ eq '$*' and &_enable_multiline;
  next if $] < 5.0109999;
  $_ eq 'split' and $^H{Classic_Perl__split} = 1;
 }
 return if @_;
 return if $] < 5.0089999;
 &_enable_multiline;
 return if $] < 5.0109999;
 $^H{Classic_Perl__split} = 1;
 return;
}
sub _enable_multiline {
   $^H{'Classic_Perl__$*'} = 0,

   # It’s the autovivification of the ** glob that warns, so this is how we
   # have to suppress it. It only warns if it is created for the sake of
   # the $* variable, so ‘no warnings’ is not needed.
   *{"*"};
}
sub unimport {
 shift;
 for(@_) {
  die
    "$_ is not a feature Classic::Perl knows about at "
    . join(" line ", (caller)[1,2]) . ".\n"
   unless exists $features{$_};
  delete $^H{"Classic_Perl__$_"};
 }
 return if @_;
 if(exists $^H{'Classic_Perl__$*'} and $] > 5.0130069 and $INC{"re.pm"}) {
  unimport re:: "/m";
 }
 delete @^H{map "Classic_Perl__$_", keys %features};
 return;
}

BEGIN {
 $VERSION='0.02';
 if($]>5.0089999){
  require XSLoader;
  XSLoader::load(__PACKAGE__, $VERSION);
 }
}

package Classic::::Perl;

$INC{"Classic/Perl.pm"} = $INC{"Classic//Perl.pm"} = __FILE__;

sub VERSION {
 my @features;
 push @features, '$*'    if $_[1] < 5.0089999;
 push @features, 'split' if $_[1] < 5.0109999;
 Classic::Perl->import(@features) if @features;
}

__THE__=>__END__

=head1 NAME

Classic::Perl - Selectively reinstate deleted Perl features

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

  use Classic::Perl;
  # or
  use Classic::Perl 'split';

  split //, "smat";
  print join " ", @_; # prints "s m a t"

  no Classic::Perl;
  @_ = ();
  split //, "smat";
  print join " ", @_;
    # prints "s m a t" in perl 5.10.x; nothing in 5.12

  use Classic::Perl '$*';
  $* = 1;
  print "yes\n" if "foo\nbar" =~ /^bar/; # prints yes

=head1 DESCRIPTION

Classic::Perl restores some Perl features that have been deleted in the
latest versions. By 'classic' we mean as of perl 5.8.x.

The whole idea is that you can put C<use Classic::Perl> at the top of an
old script or module (or a new one, if you like the features that are out
of vogue) and have it continue to work.

In versions of perl prior to 5.10, this module simply does nothing.

=head1 ENABLING FEATURES

To enable all features, simply use C<use Classic::Perl;>. To disable
whatever Classic::Perl enabled, write C<no Classic::Perl;>. These are
lexically-scoped, so:

  {
     use Classic::Perl;
     # ... features on here ...
  }
  # ... features off here ...

To enable or disable a specific set of features, pass them as arguments to
C<use> or C<no>:

  use Classic::Perl qw< split $* >;

To enable features that still existed in a given version of perl, put
I<four> colons in your C<use> statement, followed by the perl version. Only
plain numbers (C<5.008>) are currently supported. Don't use v-strings
(C<v5.8.0>).

  use Classic::::Perl 5.012; # does nothing (yet)
  use Classic::::Perl 5.010; # enables split, but not $*
  use Classic::::Perl 5.008; # enables everything

This is not guaranteed to do anything reasonable if used with C<no>.

=head1 THE FEATURES THEMSELVES

=over

=item split

This features provides C<split> to C<@_> in void and scalar context.

This was removed from perl in 5.11.

=item $*

This feature provides the C<$*> variable, which, when set to an integer
other than zero, puts an implicit C</m> on every regular expression.

Unlike the C<$*> variable in perl 5.8 and earlier, this only works at
compile-time and is lexically
scoped (like C<$[> in 5.10-5.14). It only works with constant values.
C<$* = $val> does not work.

<$*> was removed in perl 5.9.

=back

=head1 BUGS

Please report any bugs you find via L<http://rt.cpan.org> or
L<bug-Classic-Perl@rt.cpan.org>.

=head1 ACKNOWLEDGEMENTS

About half the code in the XS file was stolen from Vincent Pit's
C<autovivification> module and tweaked. The F<ptable.h> file was taken
straight from his module without modifications. (I have been subsequently
informed that he stole it from B::Hooks::OP::Check, which pilfered it from
autobox, which filched it from perl. :-)

=head1 SINE QUIBUS NON

L<perl> 5 or higher

=head1 COPYRIGHT

Copyright (C) 2010 Father Chrysostomos

  use Classic'Perl;
  split / /, 'org . cpan @ sprout';
  print reverse "\n", @_;

This program is free software; you may redistribute it, modify it or both
under the same terms as perl.

=head1 SEE ALSO

L<perl>, L<C<split> in perlfunc|perlfunc/split>, C<UNIVERSAL>,
C<C<$*> in perlvar|perlvar/$*>

L<any::feature> is an experimental module that backports new Perl features
to older versions.

The L<Modern::Perl> module enables various pragmata which are currently
popular.
