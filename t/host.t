use 5.12.1;
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";

use File::Temp;
use File::Basename;
use Test::More;
use Test::Trap qw/ :on_fail(diag_all_once) /;
use Data::Dump qw(pp);
use ORA_Test;

SKIP: {
    my $ora_test = ORA_Test->new();
    skip $@ if $@;

    $ora_test->login();
    my $result;

    $result = trap {
        $ora_test->rest->get( api => "config/host/1" );
    };
    $trap->did_return(" ... returned");
    $trap->quiet(" ... quietly");
    is( $result->{object}->{name},
        'opsview', "Pulled opview host configuration" );
    note( "result from import: ", pp($result) );

    $rest = $ora_test->logout();
}

done_testing();
