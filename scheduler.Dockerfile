# supercronic builder
FROM golang:latest AS gobuilder
RUN go install github.com/aptible/supercronic@latest

# Scheduler
FROM fedora:latest AS scheduler

ENV TZ='America/New_York'
ENV APP_HOME='/app'

USER root
WORKDIR $APP_HOME

RUN set -eux; \
    dnf install --assumeyes --setopt=install_weak_deps=False \
        git \
        glibc-langpack-en \
        openssh-clients \
        neovim \
        python \
        python-pip \
        sshpass \
        zsh; \
    useradd --home-dir /app --uid 1000 --shell /usr/bin/zsh --groups adm doom;

ENV LANG='en_US.UTF-8'
ENV LANGUAGE='en_US:en'
ENV LC_ALL='en_US.UTF-8'

COPY --from=gobuilder /go/bin/supercronic /usr/bin/supercronic

COPY --chown=doom:doom --chmod=770 ./scripts $APP_HOME/scripts/
COPY --chown=doom:doom ./config/wiki.crontab $APP_HOME/wiki.crontab

RUN set -eux; \
    python -m venv .venv; \
    source .venv/bin/activate; \
    ls -al $APP_HOME; \
    pip install -r scripts/requirements.txt; \
    chown doom:doom $APP_HOME -R;

USER doom
CMD ["zsh", "./scripts/entry.zsh"]
