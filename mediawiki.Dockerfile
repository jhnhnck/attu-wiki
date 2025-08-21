FROM php:8.4-fpm

# Version
ARG MEDIAWIKI_MAJOR_VERSION='1.44'
ARG MEDIAWIKI_VERSION='1.44.0'
ARG MEDIAWIKI_BRANCH='REL1_44'

# System dependencies
RUN --mount=type=cache,target=/var/lib/apt \
	set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		git \
		librsvg2-bin \
		imagemagick \
		libvips-tools \
		unzip \
		neovim \
		liblua5.1-0 \
		libzip5 \
		python3 \
		python3-pip \
		gnupg \
		dirmngr; \
	mkdir -p /var/www/mediawiki /var/log/mediawiki; \
	chown www-data:www-data /var/log/mediawiki;

# Install the Python packages we need
RUN set -eux; \
	pip3 install Pygments --break-system-packages;

# Executables
COPY --from=composer /usr/bin/composer /usr/bin/composer
COPY ./files/ploticus /usr/bin/ploticus

# Mediawiki dependencies
RUN --mount=type=cache,target=/var/lib/apt \
	set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libicu-dev \
		libzip-dev \
		libonig-dev \
		liblua5.1-0-dev;


# php extensions
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN set -eux; \
    install-php-extensions \
		calendar \
		exif \
		intl \
		mbstring \
		mysqli \
		opcache \
		zip \
		apcu \
		luasandbox \
		wikidiff2;

RUN set -eux; \
	echo 'max_execution_time = 60' >> /usr/local/etc/php/conf.d/docker-php-executiontime.ini; \
	printf '%s\n' 'pm.max_children = 30' \
		'pm.max_requests = 200' \
		'pm.start_servers = 10' \
		'pm.min_spare_servers = 10' \
		'pm.max_spare_servers = 30' \
			>> /usr/local/etc/php-fpm.d/zz-docker.conf;

# System files + build requirements
COPY ./files/freefont-ttf /usr/share/fonts/truetype/freefont
COPY ./config/php-config.ini /usr/local/etc/php/conf.d/php-config.ini
COPY ./patches /var/www/patches

RUN set -eux; \
	chown -R www-data:www-data /var/www; \
	chmod -R +220 /var/www;

USER www-data
WORKDIR /var/www/mediawiki

# MediaWiki setup
RUN set -eux; \
    git clone --recurse-submodules --depth=100 https://gerrit.wikimedia.org/r/mediawiki/core.git --branch "$MEDIAWIKI_BRANCH" .; \
    git apply /var/www/patches/mediawiki-deprecated-sidebar.patch; \
    composer update --no-dev; \
    mkdir -p ./mediawiki/trash;

WORKDIR /var/www/mediawiki/skins

RUN set -eux; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-skins-Citizen.git Citizen; \
	git -C Citizen apply /var/www/patches/citizen-viewport.patch; \
	rm -r ./Citizen/.git;

WORKDIR /var/www/mediawiki/extensions

# https://www.mediawiki.org/wiki/Extension:Drafts
RUN set -eux; \
	git clone --filter=blob:none https://github.com/wikimedia/mediawiki-extensions-Drafts.git Drafts; \
	git -C Drafts apply /var/www/patches/drafts-url-expand.patch; \
	rm -r ./Drafts/.git;

# https://www.mediawiki.org/wiki/Extension:CreatePageUw
RUN set -eux; \
	git clone --filter=blob:none https://gerrit.wikimedia.org/r/mediawiki/extensions/CreatePageUw CreatePageUw; \
	rm -r ./CreatePageUw/.git;

# https://github.com/jayktaylor/mw-discord
RUN set -eux; \
	git clone --filter=blob:none https://github.com/jhnhnck/mediawiki-extensions-Discord Discord; \
	rm -r ./Discord/.git;

# https://www.mediawiki.org/wiki/Extension:EasyTimeline
RUN set -eux; \
	git clone --filter=blob:none https://gerrit.wikimedia.org/r/mediawiki/extensions/timeline.git EasyTimeline; \
	git -C EasyTimeline checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./EasyTimeline/.git;

# https://www.mediawiki.org/wiki/Extension:OpenGraphMeta
RUN set -eux; \
	git clone --filter=blob:none https://gerrit.wikimedia.org/r/mediawiki/extensions/OpenGraphMeta OpenGraphMeta; \
	git -C OpenGraphMeta checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./OpenGraphMeta/.git;

# https://www.mediawiki.org/wiki/Extension:ShortDescription
RUN set -eux; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-extensions-ShortDescription.git ShortDescription; \
	rm -r ./ShortDescription/.git;

# https://www.mediawiki.org/wiki/Extension:StopForumSpam
RUN set -eux; \
	git clone --filter=blob:none https://gerrit.wikimedia.org/r/mediawiki/extensions/StopForumSpam StopForumSpam; \
	git -C StopForumSpam checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./StopForumSpam/.git;

# https://www.mediawiki.org/wiki/Extension:TemplateStylesExtender
RUN set -eux; \
	git clone --filter=blob:none https://github.com/octfx/mediawiki-extensions-TemplateStylesExtender TemplateStylesExtender; \
	rm -r ./TemplateStylesExtender/.git;

# https://www.mediawiki.org/wiki/Extension:Thumbro
RUN set -eux; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-extensions-Thumbro.git Thumbro; \
	rm -r ./Thumbro/.git;

# Copy over static files into webroot
COPY ./files/assets /var/www/mediawiki/resources/custom_assets

# Copy over wiki config
COPY ./config/LocalSettings.php /var/www/mediawiki/LocalSettings.php

WORKDIR /var/www/mediawiki
CMD ["php-fpm"]
