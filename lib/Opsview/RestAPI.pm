use 5.12.1;
use strict;
use warnings;

package Opsview::RestAPI;

# ABSTRACT: Interact with the Opsview Rest API interface

use Data::Dump qw(pp);
use Carp qw(croak confess);
use REST::Client;
use JSON;
use URI::Encode::XS qw(uri_encode);

use Opsview::RestAPI::Exception;

=head1 SYNOPSIS

  use Opsview::RestAPI;

  my $rest=Opsview::RestAPI();
  # equivalent to
  my $rest=Opsview::RestAPI(
      url => 'http://localhost',
      username => 'admin',
      password => 'initial',
  );

  my %api_version=$rest->api_version;
  $rest->login;
  my %opsview_version=$rest->opsview_version;
  $rest->logout;

=head1 DESCRIPTION

Allow for easier access to the Opsview Monitor Rest API, version 4.x and newer.
See L<https://knowledge.opsview.com/reference> for more details.

=head1 METHODS

=over 4

=item $rest = Opsview::RestAPI->new();

Create an object using default values for 'url', 'username' and 'password'.
Extra options are:

  ssl_verify_hostname => 1
  debug => 0

=cut

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {%args}, $class;

    $self->{url} ||= 'http://localhost';
    $self->{ssl_verify_hostname} //= 1;
    $self->{username} ||= 'admin';
    $self->{password} ||= 'initial';
    $self->{debug} //= 0;

    # Create the conenction here to info can be called before logging in
    $self->{json} = JSON->new->allow_nonref;

    $self->{client} = REST::Client->new();
    $self->_client->setHost( $self->{url} );
    $self->_client->addHeader( 'Content-Type', 'application/json' );

    # Set the SSL options for use with https connections
    $self->_client->getUseragent->ssl_opts(
        verify_hostname => $self->{ssl_verify_hostname} );

    # Make sure we follow any redirects if originally given
    # http but get redirected to https
    $self->_client->setFollow(1);

    # and make sure POST will also redirect correctly (doesn't by default)
    push @{ $self->_client->getUseragent->requests_redirectable }, 'POST';

    return $self;
}

# internal convenience functions
sub _client { return $_[0]->{client} }
sub _json   { return $_[0]->{json} }

sub _log {
    my ( $self, $level, @message ) = @_;
    say scalar(localtime), ': ', @message if ( $level <= $self->{debug} );
    return $self;
}

sub _dump {
    my ( $self, $level, $object ) = @_;
    say scalar(localtime), ': ', pp($object) if ( $level <= $self->{debug} );
    return $self;
}

=item $url = $rest->url;

=item $username = $rest->username;

=item $password = $rest->password;

Return the settings the object was configured with

=cut 

sub url      { return $_[0]->{url} }
sub username { return $_[0]->{username} }
sub password { return $_[0]->{password} }

sub _query {
    my ( $self, %args ) = @_;
    croak "Unknown type '$args{type}'"
        if ( $args{type} !~ m/^(GET|POST|PUT|DELETE)$/ );

    croak ( Opsview::RestAPI::Exception->new( message => "Not logged in" ) )
        unless ( $self->{token}
        || !defined( $args{api} )
        || !$args{api}
        || $args{api} =~ m/login/ );

    my $type   = $args{type};
    my $url    = "/rest/" . ( $args{api} || '' );
    my $params = join '&',
        map { "$_=" . $args{params}{$_} } keys( %{ $args{params} } );
    $url .= '?' . $params;
    my $data = $args{data} ? $self->_json->encode( $args{data} ) : undef;

    $self->_log( 2, "TYPE: $type URL: $url DATA: ", pp($data) );

    $self->_client->$type( $url, $data );

    my $deadlock_attempts = 0;
DEADLOCK: {
        $self->_log( 2, "Back from client call" );

        if ( $self->_client->responseCode ne 200 ) {
            if (   $deadlock_attempts < 5
                && $self->_client->responseContent =~ m/deadlock/i )
            {
                $deadlock_attempts++;
                warn "Encountered deadlock: ",
                    $self->_client->responseContent();
                warn "Retrying (count: $deadlock_attempts)";
                redo DEADLOCK;
            }
            else {
                my %json = eval {
                    $self->_json->decode( $self->_client->responseContent );
                };
                my %exception = (
                    type      => $type,
                    url       => $url,
                    http_code => $self->_client->responseCode,
                    %json,
                );

                # json parse failed; return the resonse content unmolested
                $exception{message} = $self->_client->responseContent
                    unless ( $exception{message} );
                confess( Opsview::RestAPI::Exception->new(%exception) );
            }
        }
    }

    my $result = $self->_client->responseContent();
    $self->_log( 3, "Raw response: ", $result );

    my $json_result;
    eval { $json_result = $self->_json->decode($result); };

    if ($@) {
        print "Failed to decode response from $self->{url}: $@", $/;
        exit 3;
    }

    $self->_log( 2, "result: ", pp($json_result) );

    return $json_result;
}

=item $rest->login

Authenticate with the Opsvsiew server using the credentials given in C<new()>.  
This must be done before any other calls (except C<api_version>) are performed.

=cut

sub login {
    my ($self) = @_;

    # make sure we are communicating with at least Opsview v4.0
    my $api_version = $self->api_version;
    if ( $api_version->{api_version} < 4.0 ) {
        croak(
            Opsview::RestPI::Exception->new(
                message => $self->{url}.
                " is running Opsview version "
                    . $api_version->{api_version}
                    . ".  Need at least version 4.0",
                http_code => 505,
            )
        );
    }

    $self->_log( 2, "About to login" );

    if ( $self->{token} ) {
        $self->_log( 1, "Already have token $self->{token}" );
        return $self;
    }

    my $result = eval {
        $self->post(
            api    => "login",
            params => {
                username => $self->{username},
                password => uri_encode( $self->{password} ),
            },
        );
    } or do {
        my $e = $@;
        $self->_log( 2, "Exception object:" );
        $self->_dump( 2, $e );
        die $e->message, $/;
    };

    $self->{token} = $result->{token};

    $self->_client->addHeader( 'X-Opsview-Username', $self->{username} );
    $self->_client->addHeader( 'X-Opsview-Token',    $result->{token} );

    $self->opsview_info();

    $self->_log( 1,
        "Successfully logged in to '$self->{url}' as '$self->{username}'" );

    return $self;
}

=item $api_version = $rest->api_version

Return a hash reference with details about the Rest API version in 
the Opsview Monitor instance.  May be called without being logged in.

Example hashref:

  {
    api_min_version => "2.0",
    api_version     => 5.005005,
    easyxdm_version => "2.4.19",
  },

=cut

sub api_version {
    my ($self) = @_;
    if ( !$self->{api_version} ) {
        $self->_log( 2, "Fetching api_version information" );
        $self->{api_version} = $self->get( api => '' );
    }
    return $self->{api_version};
}

=item $version = $rest->opsview_info

Return a hash reference contianing some details about the Opsview 
Monitor instance.

Example hashref:

  {
    hosts_limit            => "25",
    opsview_build          => "5.4.0.171741442",
    opsview_edition        => "commercial",
    opsview_version        => "5.4.0",
    server_timezone        => "Europe/London",
    server_timezone_offset => 0,
    uuid                   => "ABCDEF12-ABCD-ABCD-ABCD-ABCDEFABCDEF",
  }

=cut

sub opsview_info {
    my ($self) = @_;
    if(!$self->{opsview_info} ) {
        $self->_log( 2, "Fetching opsview_info information" );
        $self->{opsview_info} = $self->get( api => 'info' );
    }
    return $self->{opsview_info};
}

=item $build = $rest->opsview_build

Return the build number of the Opsview Monitor instance

=cut

sub opsview_build {
    my ($self) = @_;
    return $self->{opsview_info}->{opsview_build};
}

=item $interval = $rest->interval($seconds);

Return the interval to use when setting check_interval or retry_interval.  
Opsview 4.x used seconds whereas Opsview 5.x uses minutes.  

  ....
  check_interval         => $rest->interval(300),
  ....

will set an interval time of 5 minutes (300 seconds) in both 4.xand 5.x

  ....
  retry_check_interval   => $rest->interval(20),
  ....

On Opsview 5.x this will set an interval time of 20 seconds
On Opsview 4.x this will set an interval time of 1 minute

=cut 

sub interval {
    my ( $self, $interval ) = @_;

    # if this is a 4.6 system, adjust the interval to be minutes
    if ( $self->{api_version}->{api_version} < 5.0 ) {
        $interval = int( $interval / 60 );
        $interval += 1;
    }
    return $interval;
}

=item $result = $rest->get( api => ..., data => { ... }, params => { ... } );

=item $result = $rest->post( api => ..., data => { ... }, params => { ... } );

=item $result = $rest->put( api => ..., data => { ... }, params => { ... } );

=item $result = $rest->delete( api => ..., data => { ... }, params => { ... } );

Method call on the Rest API to interact with Opsview.  See the online
documentation at L<https://knowledge.opsview.com/reference> for more 
information.

The endpoint, data and parameters are all specified as a hash passed to the
method.  See L<examples/perldoc_examples> to see them in use.

To create a Host Template called 'AAA', for example:

  $rest->put(
    api  => 'config/servicegroup',
    data => { name => 'AAA' },
  );

To check if a plugin exists

  $result = $rest->get(
    api    => 'config/plugin/exists',
    params => { name => 'check_plugin_name', }
  );
  if ( $result->{exists} == 1 ) { .... }

To create a user:
  $rest->put(
    api  => 'config/contact',
    data => {       
    name        => 'userid',
    fullname    => 'User Name',
    password    => $some_secure_password,
    role        => { name => 'View all, change none', },
    enable_tips => 0,
    variables => 
      [ { name => "EMAIL", value => 'email@example.com' }, ],
    },
  );

To search for a host called 'MyHost0' and print specific details.  Note, some
API endpoints will always return an array, no matter how many objects are 
returned:

  $hosts = $rest->get(
    api => 'config/host',
    params => {
      'json_filter' => '{"name":"MyHost0"}',
    }
  );
  $myhost = $hosts->list->[0];
  print "Opsview Host ID: ", $myhost->{id}, $/;
  print "Hostgroup: ", $myhost->{hostgroup}->{name}, $/;
  print "IP Address: ", $myhost->{ip}, $/;

For some objects it may be useful to print out the returned data structure
so you can see what can be modified. Using the ID of the above host:

  use Data::Dump qw( pp );
  $hosts = $rest->get(
    api => 'config/host/2'
  );
  $myhost = $hosts->list->[0];
  print pp($host); # prints the data structure to STDOUT 

The data can then be modified and sent back using 'put' (put updates, 
post creates):

  $myhost->{ip} = '127.10.10.10';
  $result = $rest->put(
    api => 'config/host/2',
    data => { %$myhost },
  );
  print pp($result); # contains full updated host info from Opsview

=cut

sub post {
    my ( $self, %args ) = @_;
    return $self->_query( %args, type => 'POST' );
}

sub get {
    my ( $self, %args ) = @_;
    return $self->_query( %args, type => 'GET' );
}

sub put {
    my ( $self, %args ) = @_;
    return $self->_query( %args, type => 'PUT' );
}

sub delete {
    my ( $self, %args ) = @_;
    return $self->_query( %args, type => 'DELETE' );
}

=item $result = $rests->reload();

Make a request to initiate a synchronous reload.  An alias to

  $rest->post( api => 'reload' );

=cut

sub reload { return $_[0]->post( api => 'reload' ) }

=item  $result = $rest->logout();

Delete the login session held by Opsview Monitor and invalidate the 
internally stored data structures.

=cut

sub logout {
    my ($self) = @_;

    $self->_log( 2, "In logout" );

    return unless ( $self->{token} );
    $self->_log( 2, "found token, on to logout" );

    $self->post( api => 'logout' );
    $self->_log( 1, "Successfully logged out from $self->{url}" );

    # invalidate all the info held internally
    $self->{token} = undef;
    $self->{api_version} = undef;
    $self->{opsview_info} = undef;

    $self->_log( 2, "Token removed" );
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->_log( 2, "In DESTROY" );
    $self->logout if ( $self->_client );
}

=back

=cut

1;
