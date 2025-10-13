FROM php:8.4-fpm AS mediawiki

ENV TZ='America/New_York'
ENV APP_HOME='/app'
ENV LANG='en_US.UTF-8'

ARG MEDIAWIKI_MAJOR_VERSION='1.44'
ARG MEDIAWIKI_BRANCH='REL1_44'
ARG NOVADISCORD_TAG='2.0.8'
ARG BUILD_TYPE

# system packages
RUN --mount=type=cache,sharing=locked,target=/var/lib/apt \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        imagemagick \
        librsvg2-bin \
        libvips-tools \
        neovim \
        python3-minimal \
        python3-pip \
        zsh; \
    bash -c 'mkdir -p $APP_HOME/{mediawiki,jobrunner,logs}';

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
COPY ./config/php-config.ini /usr/local/etc/php/conf.d/php-config.ini
RUN set -eu; \
    printf '%s\n' \
        'pm.max_children = 30' \
        'pm.max_requests = 200' \
        'pm.start_servers = 10' \
        'pm.min_spare_servers = 10' \
        'pm.max_spare_servers = 30' \
            >> /usr/local/etc/php-fpm.d/zz-docker.conf;

RUN set -eux; \
    usermod -d $APP_HOME www-data; \
    chown -R www-data:www-data $APP_HOME; \
    chmod -R +220 $APP_HOME;

USER www-data
WORKDIR $APP_HOME/mediawiki

# Code patches (as needed)
COPY --chown=www-data:www-data ./patches $APP_HOME/patches

# MediaWiki core and "included" extensions
RUN set -eux; \
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

RUN set -eux; \
    git clone --depth=1 https://github.com/StarCitizenTools/mediawiki-skins-Citizen.git Citizen; \
    git -C Citizen apply $APP_HOME/patches/citizen-viewport.patch;

# --- extensions ---
WORKDIR $APP_HOME/mediawiki/extensions

# https://www.mediawiki.org/wiki/Extension:TemplateStyles
RUN set -eux; \
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
RUN set -eux; \
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
RUN set -eux; \
    if [ "${BUILD_TYPE:-}" != "dev" ]; then \
        git clone --depth=1 --branch "$MEDIAWIKI_BRANCH" https://github.com/jhnhnck/mediawiki-extensions-NovaDiscord NovaDiscord; \
        find .. -type d -name '.git' -exec rm -rf \{\} +; \
    fi;

# static assets
COPY --chown=www-data:www-data ./files/assets/ $APP_HOME/mediawiki/resources/assets
COPY --chown=www-data:www-data ./files/freefont-ttf $APP_HOME/fonts/freefont
# MediaWki config
COPY --chown=www-data:www-data ./config/LocalSettings.php $APP_HOME/mediawiki/LocalSettings.php

# Main image
FROM mediawiki AS fpm

WORKDIR $APP_HOME/mediawiki
CMD ["php-fpm"]

# Job runner
FROM mediawiki AS jobrunner

USER www-data
WORKDIR $APP_HOME/jobrunner

# https://www.mediawiki.org/wiki/Redis
RUN set -eux; \
    git clone --depth=1 https://gerrit.wikimedia.org/r/mediawiki/services/jobrunner .; \
    composer install --no-dev;

COPY --chown=www-data:www-data ./config/jobrunner.json $APP_HOME/jobrunner/config.json
COPY --chown=www-data:www-data --chmod=770 ./scripts/jobrunner-entry.sh $APP_HOME/jobrunner/jobrunner-entry.sh

CMD ["bash", "./jobrunner-entry.sh"]
