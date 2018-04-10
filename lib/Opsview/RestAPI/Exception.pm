use 5.12.1;
use strict;
use warnings;

package Opsview::RestAPI::Exception;

# ABSTRACT: Opsview::RestAPI Exception object

=head1 SYNOPSIS

use Carp qw(croak confess);
use Opsview::RestAPI::Exception;

# exception 
croak(Opsview::RestAPI::Exception->new( message => 'some text', http_code => 404));

# exception with stack trace
confess(Opsview::RestAPI::Exception->new( message => 'some text', http_code => 404));

=head1 DESCRIPTION

Exception objects created when Opsview::RestAPI encountered problems

=cut

use overload
    bool => sub {1},
    eq   => sub { $_[0]->as_string },
    '""' => sub { $_[0]->as_string },
    "0+" => sub {1};

=head2 METHODS

=over 4

=item $object = Opsview::RestAPI::Exception->new( ... )

Create a new exception object.  By default will add in package, filename and line the exception occurred on

=cut

sub new {
    my ( $class, %args ) = @_;

    my @caller_keys
        = (
        qw/ package filename line subroutine hasargs wantarray evaltext is_require hints bitmask hinthash /
        );

    bless { %args, map { $caller_keys[$_] => ( caller(0) )[$_] } ( 0 .. 10 ), }, $class;
}

=item $line = $object->line;

=item $path = $object->path;

=item $filename = $object->filename;

=item $package = $object->package;

Return the line, path and package the exception occurred in

=cut

sub line     { $_[0]->{line} }
sub path     { $_[0]->{filename} }
sub filename { $_[0]->{filename} }
sub package  { $_[0]->{package} }

=item $message = $object->message;

Return the message provided when the object was created

=cut

sub message {
    return $_[0]->{message};
}

=item $message = $object->http_code;

Return the http_code provided when the object was created

=cut

sub http_code {
    return $_[0]->{http_code};
}

=item $string = $object->as_string

Concatinate the message, path and line into a string string

=cut

sub as_string {
    my $self = shift;
    return sprintf( "%s at %s line %s.\n",
        $self->message, $self->path, $self->line );
}

=back

=cut

1;
