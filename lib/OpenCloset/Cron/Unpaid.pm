package OpenCloset::Cron::Unpaid;

require Exporter;
@ISA       = qw/Exporter/;
@EXPORT_OK = qw/unpaid_cond unpaid_attr is_holiday commify/;

use strict;
use warnings;
use Config::INI::Reader;
use Date::Holidays::KR ();

use OpenCloset::Common::Unpaid ();

sub unpaid_cond {
    my ( $dtf, $dt_start, $dt_end ) = @_;
    return unless $dtf;
    return unless $dt_start;
    return unless $dt_end;

    my $cond = OpenCloset::Common::Unpaid::unpaid_cond();
    $cond->{'me.return_date'} = { -between => [ $dtf->format_datetime($dt_start), $dtf->format_datetime($dt_end) ] };

    return $cond;
}

sub unpaid_attr {
    return OpenCloset::Common::Unpaid::unpaid_attr();
}

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

sub commify {
    local $_ = shift;
    1 while s/((?:\A|[^.0-9])[-+]?\d+)(\d{3})/$1,$2/s;
    return $_;
}

1;

=encoding utf8

=head1 NAME

OpenCloset::Cron::Unpaid - 미납금과 관련된 cronjob

=head1 SYNOPSIS

    perl bin/opencloset-cron-unpaid.pl /path/to/app.conf

=head1 DESCRIPTION

=over

=item *

반납 3일후에 미납금 문자전송

=item *

반납 7일후에 미납금 문자전송

=item *

반납 2주 후에 미납금이 남아 있다면 불납으로 변경

=back

=head1 COPYRIGHT and LICENSE

The MIT License (MIT)

Copyright (c) 2017 열린옷장

=cut
