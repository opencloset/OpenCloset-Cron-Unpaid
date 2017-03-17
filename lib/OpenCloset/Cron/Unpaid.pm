package OpenCloset::Cron::Unpaid;

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
