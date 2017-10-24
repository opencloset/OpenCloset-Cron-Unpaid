#!/usr/bin/env perl
use utf8;
use strict;
use warnings;

use FindBin qw( $Script );
use Getopt::Long::Descriptive;

use DateTime;
use JSON qw/decode_json/;

use Iamport::REST::Client;
use OpenCloset::Common::Unpaid qw/unpaid2nonpaid merchant_uid create_vbank/;
use OpenCloset::Config;
use OpenCloset::Cron::Unpaid qw/unpaid_cond unpaid_attr is_holiday commify/;
use OpenCloset::Cron::Worker;
use OpenCloset::Cron;
use OpenCloset::Schema;

my $config_file = shift;
die "Usage: $Script <config path>\n" unless $config_file && -f $config_file;

my $CONF     = OpenCloset::Config::load($config_file);
my $APP_CONF = $CONF->{$Script};
my $DB_CONF  = $CONF->{database};
my $SMS_CONF = $CONF->{sms};
my $TIMEZONE = $CONF->{timezone};

die "$config_file: $Script is needed\n"    unless $APP_CONF;
die "$config_file: database is needed\n"   unless $DB_CONF;
die "$config_file: sms is needed\n"        unless $SMS_CONF;
die "$config_file: sms.driver is needed\n" unless $SMS_CONF && $SMS_CONF->{driver};
die "$config_file: timezone is needed\n"   unless $TIMEZONE;

my $DB = OpenCloset::Schema->connect(
    {
        dsn      => $DB_CONF->{dsn},
        user     => $DB_CONF->{user},
        password => $DB_CONF->{pass},
        %{ $DB_CONF->{opts} },
    }
);

our $SMS_FORMAT =
    "[열린옷장] %s님, 대여연장 혹은 반납연체로 발생된 미납 금액 %s원이 아직 입금되지 않았습니다. 금일 내로 지정계좌에 입금 요청드립니다. 국민은행 %s, 예금주: %s";
our $LOG_FORMAT = "id(%d), name(%s), phone(%s), return_date(%s), sum_final_price(%s)";

my $iamport = Iamport::REST::Client->new( key => $CONF->{iamport}{key}, secret => $CONF->{iamport}{secret} );

my $worker1 = do {
    my $w;
    $w = OpenCloset::Cron::Worker->new(
        name      => 'notify_unpaid_3_day_after', # 미납후 3일
        cron      => '30 10 * * *',
        time_zone => $TIMEZONE,
        cb        => sub {
            my $name = $w->name;
            my $cron = $w->cron;
            AE::log( info => "$name\[$cron] launched" );

            my $today = DateTime->today( time_zone => $TIMEZONE );
            my $dt_start = $today->clone->subtract( days => 3 );
            my $dt_end = $today->clone->subtract( days => 2 )->subtract( seconds => 1 );

            return if is_holiday($today);

            my $dtf  = $DB->storage->datetime_parser;
            my $cond = unpaid_cond( $dtf, $dt_start, $dt_end );
            my $attr = unpaid_attr();
            my $rs   = $DB->resultset('Order')->search( $cond, $attr );
            while ( my $order = $rs->next ) {
                my $user      = $order->user;
                my $user_info = $user->user_info;
                my $to        = $user_info->phone || q{};
                my $price     = $order->get_column('sum_final_price') || 0;
                next unless $price;

                my $params = {
                    merchant_uid => merchant_uid( "staff-%d-", $order->id ),
                    amount       => $price,
                    vbank_due      => time + 86400 * 3,                                         # +3d
                    vbank_holder   => '열린옷장-' . $user->name,
                    vbank_code     => '04',                                                     # 국민은행
                    name           => sprintf( "미납금#%d", $order->id ),
                    buyer_name     => $user->name,
                    buyer_email    => $user->email,
                    buyer_tel      => $user_info->phone,
                    buyer_addr     => $user_info->address2,
                    'notice_url[]' => 'https://staff.theopencloset.net/webhooks/iamport/unpaid',
                };

                my ( $payment_log, $error ) = create_vbank( $iamport, $order, $params );
                unless ($payment_log) {
                    AE::log( error => $error );
                    next;
                }

                my $data         = decode_json( $payment_log->detail );
                my $vbank_num    = $data->{response}{vbank_num};
                my $vbank_holder = $data->{response}{vbank_holder};

                my $msg = sprintf( $SMS_FORMAT, $user->name, commify($price), $vbank_num, $vbank_holder );
                my $log = sprintf( $LOG_FORMAT, $order->id, $user->name, $to, $order->return_date, commify($price) );
                AE::log( info => $log );

                send_sms( $to, $msg ) if $to;
            }
        }
    );
};

my $worker2 = do {
    my $w;
    $w = OpenCloset::Cron::Worker->new(
        name      => 'notify_unpaid_7_day_after', # 미납후 7일
        cron      => '35 10 * * *',
        time_zone => $TIMEZONE,
        cb        => sub {
            my $name = $w->name;
            my $cron = $w->cron;
            AE::log( info => "$name\[$cron] launched" );

            my $today = DateTime->today( time_zone => $TIMEZONE );
            my $dt_start = $today->clone->subtract( days => 7 );
            my $dt_end = $today->clone->subtract( days => 6 )->subtract( seconds => 1 );

            return if is_holiday($today);

            my $dtf  = $DB->storage->datetime_parser;
            my $cond = unpaid_cond( $dtf, $dt_start, $dt_end );
            my $attr = unpaid_attr();
            my $rs   = $DB->resultset('Order')->search( $cond, $attr );
            while ( my $order = $rs->next ) {
                my $user      = $order->user;
                my $user_info = $user->user_info;
                my $to        = $user_info->phone || q{};
                my $price     = $order->get_column('sum_final_price') || 0;
                next unless $price;

                my $params = {
                    merchant_uid => merchant_uid( "staff-%d-", $order->id ),
                    amount       => $price,
                    vbank_due      => time + 86400 * 3,                                         # +3d
                    vbank_holder   => '열린옷장-' . $user->name,
                    vbank_code     => '04',                                                     # 국민은행
                    name           => sprintf( "미납금#%d", $order->id ),
                    buyer_name     => $user->name,
                    buyer_email    => $user->email,
                    buyer_tel      => $user_info->phone,
                    buyer_addr     => $user_info->address2,
                    'notice_url[]' => 'https://staff.theopencloset.net/webhooks/iamport/unpaid',
                };

                my ( $payment_log, $error ) = create_vbank( $iamport, $order, $params );
                unless ($payment_log) {
                    AE::log( error => $error );
                    next;
                }

                my $data         = decode_json( $payment_log->detail );
                my $vbank_num    = $data->{response}{vbank_num};
                my $vbank_holder = $data->{response}{vbank_holder};

                my $msg = sprintf( $SMS_FORMAT, $user->name, commify($price), $vbank_num, $vbank_holder );
                my $log = sprintf( $LOG_FORMAT, $order->id, $user->name, $to, $order->return_date, commify($price) );
                AE::log( info => $log );

                send_sms( $to, $msg ) if $to;
            }
        }
    );
};

my $worker3 = do {
    my $w;
    $w = OpenCloset::Cron::Worker->new(
        name      => 'notify_unpaid_2_week_after', # 미납후 2주
        cron      => '40 10 * * *',
        time_zone => $TIMEZONE,
        cb        => sub {
            my $name = $w->name;
            my $cron = $w->cron;
            AE::log( info => "$name\[$cron] launched" );

            my $today = DateTime->today( time_zone => $TIMEZONE );
            my $dt_start = $today->clone->subtract( days => 14 );
            my $dt_end = $today->clone->subtract( days => 13 )->subtract( seconds => 1 );
            my $dtf  = $DB->storage->datetime_parser;
            my $cond = unpaid_cond( $dtf, $dt_start, $dt_end );
            my $attr = unpaid_attr();
            my $rs   = $DB->resultset('Order')->search( $cond, $attr );
            while ( my $order = $rs->next ) {
                unpaid2nonpaid($order);
                my $log = sprintf( "order(%d) unpaid -> nonpaid", $order->id );
                AE::log( info => $log );
            }
        }
    );
};

my $cron = OpenCloset::Cron->new(
    aelog   => $APP_CONF->{aelog},
    port    => $APP_CONF->{port},
    delay   => $APP_CONF->{delay},
    workers => [ $worker1, $worker2, $worker3, ],
);

$cron->start;

## TODO: OpenCloset-Cron-SMS 와 중복됨
sub send_sms {
    my ( $to, $text ) = @_;

    my $sms = $DB->resultset('SMS')->create(
        {
            from => $SMS_CONF->{ $SMS_CONF->{driver} }{_from},
            to   => $to,
            text => $text,
        }
    );
    return unless $sms;

    my %data = ( $sms->get_columns );
    return \%data;
}
