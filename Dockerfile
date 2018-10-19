#*****************************************************************************
#   Dockerfile for a GitHub email notifications server
#   Created on Tue 21 Aug 2018 10:26:40 CEST
#   Copyright 2018 by Till Hofmann <hofmann@kbsg.rwth-aachen.de>
#*****************************************************************************
#
#   Distributed under terms of the MIT license.
#
#*****************************************************************************

FROM tiangolo/uwsgi-nginx-flask:python3.7

RUN apt-get update && apt-get -y install git ssmtp curl jq
COPY ssmtp.conf /etc/ssmtp/
RUN pip install github-webhook
RUN bash -c "ssh-keyscan github.com 2>&1 | tee /etc/ssh/ssh_known_hosts"

COPY ./main.py /app/main.py
COPY ./notify.sh /usr/local/bin/
