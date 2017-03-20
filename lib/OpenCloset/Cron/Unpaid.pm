package OpenCloset::Cron::Unpaid;

require Exporter;
@ISA       = qw/Exporter/;
@EXPORT_OK = qw/unpaid_cond unpaid_attr/;

sub unpaid_cond {
    my ( $dtf, $dt_start, $dt_end ) = @_;
    return unless $dtf;
    return unless $dt_start;
    return unless $dt_end;

    ## OpenCloset::Web::Plugin::Helpers::get_dbic_cond_attr_unpaid
    return {
        -and => [
            'me.status_id'        => 9,
            'order_details.stage' => { '>' => 0 },
            -or                   => [ 'me.late_fee_pay_with' => '미납', 'me.compensation_pay_with' => '미납', ],
            'me.return_date'      => {
                -between => [ $dtf->format_datetime($dt_start), $dtf->format_datetime($dt_end) ],
            }
        ],
    };
}

sub unpaid_attr {
    return {
        join      => [qw/ order_details /],
        group_by  => [qw/ me.id /],
        having    => { 'sum_final_price' => { '>' => 0 } },
        '+select' => [ { sum => 'order_details.final_price', -as => 'sum_final_price' }, ],
    };
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
