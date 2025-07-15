FROM php:8.4-fpm

# Version
ARG MEDIAWIKI_MAJOR_VERSION='1.44'
ARG MEDIAWIKI_VERSION='1.44.0'
ARG MEDIAWIKI_BRANCH='REL1_44'

# System dependencies
RUN set -eux; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		git \
		librsvg2-bin \
		imagemagick \
		libvips-tools \
		unzip \
		neovim \
		liblua5.1-0 \
		libzip4 \
		python3 \
		python3-pip \
		gnupg \
		dirmngr \
	; \
	rm -rf /var/lib/apt/lists/*; \
	mkdir -p /var/www/mediawiki /var/www/mediawiki/trash;

# Install the Python packages we need
RUN set -eux; \
	pip3 install Pygments --break-system-packages;

# Install wikidiff2
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Executables
COPY --from=composer /usr/bin/composer /usr/bin/composer
COPY ./files/ploticus /usr/bin/ploticus

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
	libicu-dev \
	libonig-dev \
	libzip-dev \
	liblua5.1-0-dev; \
	rm -rf /var/lib/apt/lists/*;

RUN set -eux; \
	docker-php-ext-install -j "$(nproc)" \
	calendar \
	exif \
	intl \
	mbstring \
	mysqli \
	opcache \
	zip;

RUN set -eux; \
	install-php-extensions wikidiff2; \
	pecl install APCu luasandbox; \
	docker-php-ext-enable apcu luasandbox; \
	rm -r /tmp/pear;

RUN set -eux; \
	echo 'max_execution_time = 60' >> /usr/local/etc/php/conf.d/docker-php-executiontime.ini; \
	echo 'pm.max_children = 30' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.max_requests = 200' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.start_servers = 10' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.min_spare_servers = 10' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.max_spare_servers = 30' >> /usr/local/etc/php-fpm.d/zz-docker.conf;

COPY ./files/freefont-ttf /usr/share/fonts/truetype/freefont

# Copy over static files into webroot
COPY ./files/assets /var/www/mediawiki/resources/custom_assets

# Copy over config
COPY ./config/php-config.ini /usr/local/etc/php/conf.d/php-config.ini
COPY ./config/LocalSettings.php /var/www/mediawiki/LocalSettings.php
COPY ./patches /var/www/patches

RUN set -eux; \
	chown -R www-data:www-data /var/www; \
	chmod -R +220 /var/www;

USER www-data
WORKDIR /var/www/mediawiki

# MediaWiki setup
RUN set -eux; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -o mediawiki.tar.gz; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz.sig" -o mediawiki.tar.gz.sig; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --fetch-keys "https://www.mediawiki.org/keys/keys.txt"; \
	gpg --batch --verify mediawiki.tar.gz.sig mediawiki.tar.gz; \
	tar -x --strip-components=1 -f mediawiki.tar.gz -C /var/www/mediawiki; \
	gpgconf --kill all; \
	rm -r "$GNUPGHOME" mediawiki.tar.gz.sig mediawiki.tar.gz;

WORKDIR /var/www/mediawiki/skins

RUN set -eux; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-skins-Citizen.git Citizen; \
	git -C Citizen apply /var/www/patches/citizen-viewport.patch; \
	rm -r ./Citizen/.git;

WORKDIR /var/www/mediawiki/extensions

# https://www.mediawiki.org/wiki/Extension:Drafts
RUN set -eux; \
	git clone --filter=blob:none https://github.com/wikimedia/mediawiki-extensions-Drafts.git Drafts; \
	git -C Drafts apply /var/www/patches/drafts-namespaced-types.patch; \
	git -C Drafts apply /var/www/patches/drafts-urlutils-expand.patch; \
	rm -r ./Drafts/.git;

# https://www.mediawiki.org/wiki/Extension:CreatePageUw
RUN set -eux; \
	git clone --filter=blob:none https://gerrit.wikimedia.org/r/mediawiki/extensions/CreatePageUw CreatePageUw; \
	# git -C CreatePageUw checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./CreatePageUw/.git;

# https://github.com/jayktaylor/mw-discord
RUN set -eux; \
	git clone --filter=blob:none https://github.com/jayktaylor/mw-discord Discord; \
	# git -C Discord checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
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
	# git -C ShortDescription checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./ShortDescription/.git;

# https://www.mediawiki.org/wiki/Extension:StopForumSpam
RUN set -eux; \
	git clone --filter=blob:none https://gerrit.wikimedia.org/r/mediawiki/extensions/StopForumSpam StopForumSpam; \
	git -C StopForumSpam checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./StopForumSpam/.git;

# https://www.mediawiki.org/wiki/Extension:TemplateStylesExtender
RUN set -eux; \
	git clone --filter=blob:none https://github.com/octfx/mediawiki-extensions-TemplateStylesExtender TemplateStylesExtender; \
	# git -C TemplateStylesExtender checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./TemplateStylesExtender/.git;

# https://www.mediawiki.org/wiki/Extension:Thumbro
RUN set -eux; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-extensions-Thumbro.git Thumbro; \
	# git -C Thumbro checkout -b "${MEDIAWIKI_BRANCH}" "origin/${MEDIAWIKI_BRANCH}"; \
	rm -r ./Thumbro/.git;

WORKDIR /var/www/mediawiki
CMD ["php-fpm"]
