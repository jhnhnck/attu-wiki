FROM php:8.3-fpm

# Version
ARG MEDIAWIKI_MAJOR_VERSION='1.43'
ARG MEDIAWIKI_VERSION='1.43.1'

# System dependencies
RUN set -eux; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		git \
		librsvg2-bin \
		imagemagick \
		libvips-tools \
		# ffmpeg \
		# webp \
		unzip \
		# openssh-client \
		# rsync \
		neovim \
		liblua5.1-0 \
		libzip4 \
		# s3cmd \
		python3 \
		python3-pip \
	; \
	rm -rf /var/lib/apt/lists/*

# Install the Python packages we need
RUN set -eux; \
	pip3 install Pygments --break-system-packages \
	;

# Install wikidiff2
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
	libicu-dev \
	libonig-dev \
	# libcurl4-gnutls-dev \
	# libmagickwand-dev \
	# libwebp7 \
	libzip-dev \
	liblua5.1-0-dev \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
	calendar \
	exif \
	intl \
	mbstring \
	mysqli \
	opcache \
	zip \
	; \
	\
	install-php-extensions wikidiff2; \
	\
	pecl install \
		APCu \
		luasandbox \
		# redis \
	; \
	docker-php-ext-enable \
		apcu \
		luasandbox \
		# redis \
	; \
	rm -r /tmp/pear; \
	\
	# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# MediaWiki setup
RUN set -eux; \
	fetchDeps=" \
		gnupg \
		dirmngr \
	"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $fetchDeps; \
	\
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -o mediawiki.tar.gz; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz.sig" -o mediawiki.tar.gz.sig; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --fetch-keys "https://www.mediawiki.org/keys/keys.txt"; \
	gpg --batch --verify mediawiki.tar.gz.sig mediawiki.tar.gz; \
	mkdir /var/www/mediawiki; \
	tar -x --strip-components=1 -f mediawiki.tar.gz -C /var/www/mediawiki; \
	gpgconf --kill all; \
	rm -r "$GNUPGHOME" mediawiki.tar.gz.sig mediawiki.tar.gz; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $fetchDeps; \
	rm -rf /var/lib/apt/lists/*

# COPY ./config/LocalSettings.php /var/www/mediawiki/LocalSettings.php
# COPY ./resources /var/www/mediawiki/resources

COPY ./config/php-config.ini /usr/local/etc/php/conf.d/php-config.ini
# COPY ./config/robots.txt /var/www/mediawiki/robots.txt

RUN set -eux; \
	# echo 'memory_limit = 512M' >> /usr/local/etc/php/conf.d/docker-php-memlimit.ini; \
	echo 'max_execution_time = 60' >> /usr/local/etc/php/conf.d/docker-php-executiontime.ini; \
	echo 'pm.max_children = 30' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.max_requests = 200' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.start_servers = 10' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.min_spare_servers = 10' >> /usr/local/etc/php-fpm.d/zz-docker.conf; \
	echo 'pm.max_spare_servers = 30' >> /usr/local/etc/php-fpm.d/zz-docker.conf;

# Executables
COPY --from=composer /usr/bin/composer /usr/bin/composer
COPY ./files/ploticus /usr/bin/ploticus

# Copy over static files into webroot
COPY ./skins/Citizen /var/www/mediawiki/skins/Citizen
COPY ./extensions/. /var/www/mediawiki/extensions/
COPY ./files/assets /var/www/mediawiki/resources/custom_assets
# COPY ./files/favicon.ico /var/www/mediawiki/favicon.ico

# # Search engine stuff
# COPY ./files/BingSiteAuth.xml /var/www/mediawiki/BingSiteAuth.xml
# COPY ./files/googleb824390e79cfa5c6.html /var/www/mediawiki/googleb824390e79cfa5c6.html
# COPY ./files/robots.txt /var/www/mediawiki/robots.txt
# COPY ./files/well-known /var/www/mediawiki/.well-known

COPY ./files/freefont-ttf /usr/share/fonts/truetype/freefont
# COPY ./files/listed_ip_30_all.txt /var/www/mediawiki/resources/listed_ip_30_all.txt

# COPY ./files/htaccess /var/www/mediawiki/.htaccess
# COPY ./files/remoteip.load /etc/apache2/mods-enabled/remoteip.load
# COPY ./files/security.conf /etc/apache2/conf-available/security.conf

RUN set -eux; \
	printf 'Set permissions on files: [chown: %s changes] [chmod: %s changes]\n' \
		"$(chown -Rc www-data:www-data /var/www | wc -l)" \
		"$(chmod -Rc +220 /var/www/mediawiki | wc -l)";

WORKDIR /var/www/mediawiki

USER www-data

CMD ["php-fpm"]
