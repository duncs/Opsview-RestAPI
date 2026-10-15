use 5.12.1;
use strict;
use warnings;

use Test::More;

# Keep in sync with bin/opsview_rest_api endpoint parsing.
sub parse_endpoint {
    my ($endpoint) = @_;

    $endpoint =~ s!^/rest/!!;
    $endpoint =~ s!^/!!;

    my ( $api, $query ) = split( /\?/, $endpoint, 2 );
    $api //= '';

    return ( $api, parse_query_string($query) );
}

sub parse_query_string {
    my ($query) = @_;
    my %params;

    return \%params unless defined $query && length $query;

    for my $pair ( split /&/, $query ) {
        next unless length $pair;
        my ( $key, $value ) = split /=/, $pair, 2;
        next unless defined $key && length $key;
        $value //= '';

        if ( exists $params{$key} ) {
            my $existing = $params{$key};
            if ( ref($existing) eq 'ARRAY' ) {
                push @{$existing}, $value;
            }
            else {
                $params{$key} = [ $existing, $value ];
            }
        }
        else {
            $params{$key} = $value;
        }
    }

    return \%params;
}

{
    my ( $api, $params ) = parse_endpoint(
        'config/hostgroup?json_filter={"name":"AAA MyHosts"}' );
    is( $api, 'config/hostgroup', 'api path' );
    is( $params->{json_filter}, '{"name":"AAA MyHosts"}', 'json_filter param' );
}

{
    my ( $api, $params ) = parse_endpoint(
        'status?servicecheck=Uptime Restart&state=2&rows=all' );
    is( $api, 'status', 'status api' );
    is( $params->{servicecheck}, 'Uptime Restart', 'servicecheck with space' );
    is( $params->{state},         '2',                'state' );
    is( $params->{rows},          'all',              'rows' );
}

{
    my ( $api, $params )
        = parse_endpoint('/rest/config/host?json_filter={"name":{"like":"x"}}');
    is( $api, 'config/host', 'strip /rest/ prefix' );
    ok( $params->{json_filter}, 'json_filter on stripped path' );
}

done_testing();
