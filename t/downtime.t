use 5.12.1;
use strict;
use warnings;

use FindBin qw($Bin $Script);
use lib "$Bin/lib";

use POSIX qw(strftime);
use Test::More;
use Test::Trap qw/ :on_fail(diag_all_once) /;
use Data::Dump qw(pp);
use ORA_Test;

SKIP: {
    my $ora_test = ORA_Test->new();
    skip $@ if $@;

    $ora_test->login();

    my $starttime = strftime( '%Y-%m-%d %H:%M:%S', localtime() );
    my $endtime = strftime( '%Y-%m-%d %H:%M:%S', localtime( time() + 3600 ) );

    # Add downtime just using parameters
    my $result = trap {
        $ora_test->rest->post(
            api    => 'downtime',
            params => {
                'svc.hostname'    => 'opsview',
                'svc.servicename' => 'Opsview Agent',
                starttime         => $starttime,
                endtime           => $endtime,
                comment => 'Downtime added by Opsview::RestAPI test: '
                    . $Script,
            },
        );
    };
    $trap->did_return(" ... returned");
    $trap->quiet(" ... quietly");
    is( $result->{summary}->{num_services}, 1, "Downtime set via params" );

    note( pp($result) );

    # Add downtime using JSON data
    $result = trap {
        $ora_test->rest->post(
            api    => 'downtime',
            params => {
                'svc.hostname'    => 'opsview',
                'svc.servicename' => 'Opsview Agent',
            },
            data => {
                starttime => $starttime,
                endtime   => $endtime,
                comment   => 'Downtime added by Opsview::RestAPI test: '
                    . $Script,
            },
        );
    };
    $trap->did_return(" ... returned");
    $trap->quiet(" ... quietly");
    is( $result->{summary}->{num_services}, 1, "Downtime set via params" );

    note( pp($result) );

    $ora_test->logout();
}

done_testing();
