use 5.12.1;
use strict;
use warnings;

use Test::More;
use Test::Trap qw/ :on_fail(diag_all_once) /;

my %opsview = (
    url      => 'http://localhost',
    username => 'admin',
    password => 'initial',
);

for my $var (qw/ url username password /) {
    my $envvar = 'OPSVIEW_' . uc($var);
    if ( !$ENV{$envvar} ) {
        diag "Using default '$envvar' value of '$opsview{$var}' for testing.";
    }
    else {
        $opsview{$var} = $ENV{$envvar};
        note "Using provided '$envvar' for testing.";
    }
}

use_ok("Opsview::RestAPI");
use_ok("Opsview::RestAPI::Exception");

my $rest;
my $output;

$rest = trap {
    Opsview::RestAPI->new(%opsview);
};
isa_ok( $rest, 'Opsview::RestAPI' );
$trap->did_return(" ... returned");
$trap->quiet(" ... quietly");
isa_ok( $rest->{client}, 'REST::Client' );
is( $rest->url,      $opsview{url},      "URL set on object correctly" );
is( $rest->username, $opsview{username}, "Username set on object correctly" );
is( $rest->password, $opsview{password}, "Password set on object correctly" );

$output = trap {
    $rest->api_version();
};

SKIP: {
# object was created, we tried to access it, but the URL was not to an Opsview server
    if ( $trap->die && ref( $trap->die ) eq 'Opsview::RestAPI::Exception' ) {
        if (   $trap->die->message =~ m/was not found on this server/
            || $trap->die->http_code != 200 )
        {
            my $message
                = "HTTP STATUS CODE: "
                . $trap->die->http_code
                . " MESSAGE: "
                . $trap->die->message;
            $message =~ s/\n/ /g;

            my $exit_msg = 
                "The configured URL '$opsview{url}' does NOT appear to be an opsview server: "
                . $message;
            diag $exit_msg;
            skip $exit_msg;
        }
    }

    $trap->did_return("api_version was returned");
    $trap->quiet("no further errors on api_version");
    is( ref($output), 'HASH', ' ... got a HASH in response' );

    like( $output->{api_min_version},
        qr/^\d\.\d$/, "api_version 'api_min_version' returned okay" );
    like( $output->{api_version},
        qr/^\d\.\d+$/, "api_version 'api_version' returned okay" );
    like( $output->{easyxdm_version},
        qr/^\d\.\d\.\d+$/, "api_version 'easyxdm_version' returned okay" );

    note( "Got 'api_version' from '$opsview{url}' of "
            . $output->{api_version} );

    # try to get rest/info, which auth is required for
    $output = trap {
        $rest->opsview_info;
    };
    $trap->did_die("Could not fetch opsview_info when not logged in");
    $trap->quiet("No extra output");
    isa_ok( $trap->die, 'Opsview::RestAPI::Exception' );
    is( $trap->die,
        "Not logged in",
        "Exception stringified to 'Not logged in' correctly"
    );

    # Now log in and try to get rest info again
    trap {
        $rest->login;
    };
    $trap->did_return("Logged in okay");
    $trap->quiet("no further errors on login");

    $output = trap {
        $rest->opsview_info;
    };
    $trap->did_return("Got opsview_info when logged in");
    $trap->quiet("No extra output");

    like( $output->{opsview_version},
        qr/^\d\.\d+\.\d$/, "opsview_info 'opsview_version' returned okay" );
    like( $output->{opsview_build},
        qr/^\d\.\d+\.\d\.\d+$/,
        "opsview_info 'opsview_build' returned okay" );
    like( $output->{opsview_edition},
        qr/^\w+$/, "opsview_info 'opsview_edition' returned okay" );
    like(
        $output->{uuid},
        qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/,
        "opsview_info 'uuid' returned okay"
    );

    # Now log out and make sure we can no longer get the info
    trap {
        $rest->logout
    };
    $trap->did_return("Logged out okay");
    $trap->quiet("no further errors on logout");

    $output = trap {
        $rest->opsview_info;
    };
    $trap->did_die("Could not fetch opsview_info when not logged in");
    $trap->quiet("No extra output");
    isa_ok( $trap->die, 'Opsview::RestAPI::Exception' );
    is( $trap->die,
        "Not logged in",
        "Exception stringified to 'Not logged in' correctly"
    );
}

done_testing();
