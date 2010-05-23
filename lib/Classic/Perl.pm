package Classic::Perl;

my %features = map +($_ => undef)  =>=>  < split >;

sub import{
 shift;
 for(@_) {
  die "$_ is not a feature Classic::Perl knows about" unless $features{$_}
 }
 return if $] < 5.012;
 $^H{Classic_Perl__split} = 1;
 return;
}
sub unimport {
 shift;
 for(@_) {
  die "$_ is not a feature Classic::Perl knows about" unless $features{$_}
 }
 return if $] < 5.012;
 delete $^H{Classic_Perl__split};
 return;
}

BEGIN {
 $VERSION='0.01';
 if($]>=5.012){
  require XSLoader;
  XSLoader::load(__PACKAGE__, $VERSION);
 }
}

__THE__=>__END__

=head1 NAME

Classic::Perl - Selectively reinstate deleted Perl features

=head1 VERSION

Version 0.01

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

=head1 DESCRIPTION

Classic::Perl restores some Perl features that have been deleted in the
latest versions. By 'Classic' we mean as of perl 5.10.1.

The whole idea is that you can put C<use Classic::Perl> at the top of an
old script or module (or a new one, if you like the features that are out
of vogue) and have it continue to work.

In versions of perl prior to 5.12, this module simply does nothing.

So far, the only feature this module provides is C<split> to C<@_> in void
and scalar context.

=head1 BUGS

Please report any bugs you find via L<http://rt.cpan.org> or
L<bug-Classic-Perl@rt.cpan.org>.

=head1 ACKNOWLEDGEMENTS

About half the code in the XS file was stolen from Vincent Pit's
C<autovivification> module and tweaked. The F<ptable.h> file was taken
straight from his module without modifications.

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

L<perl>, L<C<split> in perlfunc|perlfunc/split>
