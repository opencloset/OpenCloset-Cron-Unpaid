# OpenCloset-Cron-Unpaid #

[![Build Status](https://travis-ci.org/opencloset/OpenCloset-Cron-Unpaid.svg?branch=v0.1.1)](https://travis-ci.org/opencloset/OpenCloset-Cron-Unpaid)

미납금과 관련된 cronjob

- 반납 3일후에 미납금 문자전송 (AM 10:30)
- 반납 7일후에 미납금 문자전송 (AM 10:35)
- 반납 2주 후에 미납금이 남아 있다면 불납으로 변경 (AM 10:40)

## Build docker image ##

    $ docker build -t opencloset/cron/unpaid .
