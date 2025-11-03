FROM dunglas/frankenphp:1-php8.4 AS php-base

# FROM php:8.4-fpm AS mediawiki

ENV TZ='America/New_York'
ENV APP_HOME='/app'

ARG MEDIAWIKI_MAJOR_VERSION='1.44'
ARG MEDIAWIKI_BRANCH='REL1_44'
ARG BUILD_TYPE

# system packages
RUN --mount=type=cache,sharing=locked,target=/var/lib/apt \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        librsvg2-bin \
        libvips-tools \
        python3-minimal \
        python3-pip \
        zsh; \
    if [ "${BUILD_TYPE:-}" = "dev" ]; then \
        apt-get install -y --no-install-recommends \
            neovim; \
    fi; \
    bash -c 'mkdir -p $APP_HOME/{mediawiki,jobrunner,logs}'; \
    ln -s /dev/stdout /var/log/caddy.log;

# Python packages
# for SyntaxHighlight code highlighting
RUN set -eux; \
    pip3 install Pygments --break-system-packages;

# Executables
# required by EasyTimeline extension
COPY ./files/ploticus /usr/bin/ploticus

# PHP extensions
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN --mount=type=cache,sharing=locked,target=/var/lib/apt \
    install-php-extensions \
        @composer \
        apcu \
        calendar \
        exif \
        intl \
        luasandbox \
        mysqli \
        pcntl \
        redis \
        sockets \
        wikidiff2 \
        zip;

# php-fpm configuration tweaks
RUN set -eu; \
    printf '%s\n' \
        'error_reporting = E_ALL' \
        'log_errors = On' \
\
        >> /usr/local/etc/php/conf.d/zz-mediawiki.ini; \
    if [ "${BUILD_TYPE:-}" != "dev" ]; then \
        printf '%s\n' \
            'display_errors = On' \
            >> /usr/local/etc/php/conf.d/zz-mediawiki.ini; \
    fi;

# Setup user
RUN set -eux; \
    usermod --home $APP_HOME --shell /usr/bin/zsh www-data; \
    chown -R www-data:www-data $APP_HOME; \
    chmod -R +220 $APP_HOME;

USER www-data
WORKDIR $APP_HOME/mediawiki

# Code patches (as needed)
COPY --chown=www-data:www-data ./patches $APP_HOME/patches

# MediaWiki core and "included" extensions
RUN set -eu; \
    git clone --no-recurse-submodules --depth=1 --branch "$MEDIAWIKI_BRANCH" https://gerrit.wikimedia.org/r/mediawiki/core.git .; \
    git submodule update --init --recursive -- \
        skins/ \
        extensions/CategoryTree \
        extensions/Cite \
        extensions/CodeEditor \
        extensions/ConfirmEdit \
        extensions/Echo \
        extensions/InputBox \
        extensions/Interwiki \
        extensions/Math \
        extensions/PageImages \
        extensions/ParserFunctions \
        extensions/Scribunto \
        extensions/SyntaxHighlight_GeSHi \
        extensions/TemplateData \
        extensions/TemplateStyles \
        extensions/TextExtracts \
        extensions/TitleBlacklist \
        extensions/VisualEditor \
        extensions/WikiEditor; \
    git apply $APP_HOME/patches/mediawiki-deprecated-sidebar.patch; \
    mkdir ./trash; \
    if [ "${BUILD_TYPE:-}" != "dev" ]; then \
        composer update --no-dev; \
        rm -r ./.git; \
    else \
        composer update; \
    fi;

# --- skins ---
WORKDIR $APP_HOME/mediawiki/skins

RUN set -eu; \
    git clone --depth=1 https://github.com/StarCitizenTools/mediawiki-skins-Citizen.git Citizen; \
    git -C Citizen apply $APP_HOME/patches/citizen-viewport.patch;

# --- extensions ---
WORKDIR $APP_HOME/mediawiki/extensions

# https://www.mediawiki.org/wiki/Extension:TemplateStyles
RUN set -eu; \
    cd TemplateStyles; \
    composer install --no-dev;

# https://www.mediawiki.org/wiki/Extension:Drafts
# https://www.mediawiki.org/wiki/Extension:CreatePageUw
# https://www.mediawiki.org/wiki/Extension:EasyTimeline
# https://www.mediawiki.org/wiki/Extension:OpenGraphMeta
# https://www.mediawiki.org/wiki/Extension:ShortDescription
# https://www.mediawiki.org/wiki/Extension:StopForumSpam
# https://www.mediawiki.org/wiki/Extension:TemplateStylesExtender
# https://www.mediawiki.org/wiki/Extension:Thumbro
RUN set -eu; \
    git clone --depth=1 https://github.com/wikimedia/mediawiki-extensions-Drafts.git Drafts; \
    git -C Drafts apply $APP_HOME/patches/drafts-url-expand.patch; \
    \
    git clone --depth=1 https://gerrit.wikimedia.org/r/mediawiki/extensions/CreatePageUw CreatePageUw; \
    \
    git clone --depth=1 --branch "$MEDIAWIKI_BRANCH" https://gerrit.wikimedia.org/r/mediawiki/extensions/timeline.git EasyTimeline; \
    \
    git clone --depth=1 --branch "$MEDIAWIKI_BRANCH" https://gerrit.wikimedia.org/r/mediawiki/extensions/OpenGraphMeta OpenGraphMeta; \
    \
    git clone --depth=1 https://github.com/StarCitizenTools/mediawiki-extensions-ShortDescription.git ShortDescription; \
    \
    git clone --depth=1 --branch "$MEDIAWIKI_BRANCH" https://gerrit.wikimedia.org/r/mediawiki/extensions/StopForumSpam StopForumSpam; \
    \
    git clone --depth=1 https://github.com/octfx/mediawiki-extensions-TemplateStylesExtender TemplateStylesExtender; \
    \
    git clone --depth=1 https://github.com/StarCitizenTools/mediawiki-extensions-Thumbro.git Thumbro;

# https://github.com/jhnhnck/mediawiki-extensions-Discord
RUN set -eu; \
    if [ "${BUILD_TYPE:-}" != "dev" ]; then \
        git clone --depth=1 --branch "$MEDIAWIKI_BRANCH" https://github.com/jhnhnck/mediawiki-extensions-NovaDiscord NovaDiscord; \
        find .. -type d -name '.git' -exec rm -rf \{\} +; \
    fi;

# mediawiki assets and config
COPY --chown=www-data:www-data ./files/assets/ $APP_HOME/mediawiki/resources/assets
COPY --chown=www-data:www-data ./config/LocalSettings.php $APP_HOME/mediawiki/LocalSettings.php

# Dotfiles (mostly search engine stuff)
COPY --chown=www-data:www-data ./files/dotfiles/ $APP_HOME/mediawiki
COPY --chown=www-data:www-data ./config/robots.txt $APP_HOME/mediawiki

# Main image
FROM php-base AS mediawiki

USER root
WORKDIR $APP_HOME/mediawiki

# add and validate caddy config
COPY ./config/Caddyfile /etc/frankenphp/Caddyfile
RUN set -eux; \
    frankenphp validate --config /etc/frankenphp/Caddyfile; \
    ln -svf $APP_HOME/mediawiki/sitemap/sitemap-attuproject.org-NS_0-0.xml $APP_HOME/mediawiki/sitemap.xml;

# Job runner
FROM php-base AS jobrunner

USER root

USER www-data
WORKDIR $APP_HOME/jobrunner

# https://www.mediawiki.org/wiki/Redis
RUN set -eux; \
    git clone --depth=1 https://gerrit.wikimedia.org/r/mediawiki/services/jobrunner .; \
    composer install --no-dev; \
    cp /etc/zsh/zshrc $APP_HOME/.zshrc;

COPY --chown=www-data:www-data ./config/jobrunner.json $APP_HOME/jobrunner/config.json
COPY --chown=www-data:www-data --chmod=770 ./scripts/entry.zsh $APP_HOME/jobrunner/entry.zsh

CMD ["zsh", "./entry.zsh"]

# supercronic builder
FROM golang:latest AS gobuilder
RUN go install github.com/aptible/supercronic@latest

# Scheduler
FROM php-base AS scheduler

ENV TZ='America/New_York'
ENV APP_HOME='/app'

USER root
WORKDIR $APP_HOME

RUN set -eux; \
    apt-get install -y --no-install-recommends \
        bzip2 \
        mariadb-client \
        sudo-rs; \
    usermod --groups adm,sudo www-data; \
    sed -i '/%sudo/d' /etc/sudoers; \
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-group;

COPY --from=gobuilder /go/bin/supercronic /usr/bin/supercronic
COPY --chown=doom:doom --chmod=770 ./scripts $APP_HOME/scripts/
COPY --chown=doom:doom ./config/wiki.crontab $APP_HOME/wiki.crontab

RUN set -eux; \
    python -m venv .venv; \
    source .venv/bin/activate; \
    pip install -r scripts/requirements.txt; \
    cp /etc/zshrc $APP_HOME/.zshrc;

USER www-data
CMD ["zsh", "./scripts/entry.zsh"]
