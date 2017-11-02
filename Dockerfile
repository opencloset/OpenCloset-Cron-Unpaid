FROM opencloset/perl:latest

RUN groupadd opencloset && useradd -g opencloset opencloset

WORKDIR /tmp
COPY cpanfile cpanfile
RUN cpanm --notest \
    --mirror http://www.cpan.org \
    --mirror http://cpan.theopencloset.net \
    --installdeps .

# Everything up to cached.
WORKDIR /home/opencloset/service/OpenCloset-Cron-Unpaid
COPY . .
RUN chown -R opencloset:opencloset .

USER opencloset

ENV PERL5LIB "./lib:$PERL5LIB"
ENV OPENCLOSET_CRON_SMS_PORT "5000"
ENV OPENCLOSET_EXTRA_HOLIDAYS "/home/opencloset/.opencloset-extra-holidays.ini"
# ENV OPENCLOSET_DATABASE_DSN "REQUIRED"
# ENV OPENCLOSET_IAMPORT_API_KEY "REQUIRED"
# ENV OPENCLOSET_IAMPORT_API_SECRET "REQUIRED"

CMD ["./bin/opencloset-cron-unpaid.pl", "./app.conf"]

EXPOSE 5000
