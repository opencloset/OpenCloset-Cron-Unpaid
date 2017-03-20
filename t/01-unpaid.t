use strict;
use warnings;
use Test::More;
use DateTime;
use DateTime::Format::MySQL;

use OpenCloset::Schema;

use_ok( 'OpenCloset::Cron::Unpaid', qw/unpaid_cond unpaid_attr is_holiday commify/ );

our $TIMEZONE = 'Asia/Seoul';

my $parser   = DateTime::Format::MySQL->new;
my $today    = DateTime->today( time_zone => $TIMEZONE );
my $dt_start = $today->clone->subtract( days => 3 );
my $dt_end   = $today->clone->subtract( days => 2 )->subtract( seconds => 1 );
my $cond     = unpaid_cond( $parser, $dt_start, $dt_end );
my $attr     = unpaid_attr();

is( $cond->{'-and'}[0], 'me.status_id' );
is( $cond->{'-and'}[1], 9 );
like( $parser->format_datetime($dt_start), qr/00:00:00/ );
like( $parser->format_datetime($dt_end),   qr/23:59:59/ );

is_deeply( $attr->{join}, [qw/order_details/] );

my $holiday = $parser->parse_datetime('2017-05-05 00:00:00');
is( is_holiday($holiday), 1 );
is( is_holiday( $holiday->clone->subtract( days => 1 ) ), undef );

is( commify('10000'), '10,000' );
done_testing();
