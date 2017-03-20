use utf8;
use strict;
use warnings;

use FindBin qw( $Script );
use Getopt::Long::Descriptive;

use Config::INI::Reader;
use Date::Holidays::KR ();
use DateTime;

use OpenCloset::Config;
use OpenCloset::Cron::Unpaid qw/unpaid_cond unpaid_attr/;
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
    "[열린옷장] %s님, 대여연장 혹은 반납연체로 발생된 미납 금액 %s원이 아직 입금되지 않았습니다. 금일 내로 지정계좌에 입금 요청드립니다. 국민은행 205737-04-003013, 예금주: 사단법인 열린옷장";
our $LOG_FORMAT = "id(%d), name(%s), phone(%s), return_date(%s), sum_final_price(%s)";

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
                my $user  = $order->user;
                my $to    = $user->user_info->phone || q{};
                my $price = $order->get_column('sum_final_price') || 0;
                next unless $price;

                my $msg = sprintf( $SMS_FORMAT, $user->name, commify($price) );
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
                my $user  = $order->user;
                my $to    = $user->user_info->phone || q{};
                my $price = $order->get_column('sum_final_price') || 0;
                next unless $price;

                my $msg = sprintf( $SMS_FORMAT, $user->name, commify($price) );
                my $log = sprintf( $LOG_FORMAT, $order->id, $user->name, $to, $order->return_date, commify($price) );
                AE::log( info => $log );

                send_sms( $to, $msg ) if $to;
            }
        }
    );
};

my $cron = OpenCloset::Cron->new(
    aelog   => $APP_CONF->{aelog},
    port    => $APP_CONF->{port},
    delay   => $APP_CONF->{delay},
    workers => [ $worker1, $worker2, ],
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

## TODO: OpenCloset-Cron-SMS 와 중복됨
sub is_holiday {
    my $date = shift;
    return unless $date;

    my $year     = $date->year;
    my $month    = sprintf '%02d', $date->month;
    my $day      = sprintf '%02d', $date->day;
    my $holidays = Date::Holidays::KR::holidays($year);
    return 1 if $holidays->{ $month . $day };

    if ( my $ini = $ENV{OPENCLOSET_EXTRA_HOLIDAYS} ) {
        my $extra_holidays = Config::INI::Reader->read_file($ini);
        return $extra_holidays->{$year}{ $month . $day };
    }

    return;
}

## TODO: OpenCloset-Cron-SMS 와 중복됨
sub commify {
    local $_ = shift;
    1 while s/((?:\A|[^.0-9])[-+]?\d+)(\d{3})/$1,$2/s;
    return $_;
}
