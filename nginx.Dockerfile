FROM nginx:latest

# Version
ARG MEDIAWIKI_MAJOR_VERSION='1.43'
ARG MEDIAWIKI_VERSION='1.43.0'
ARG MEDIAWIKI_RELEASE_BRANCH='REL1_43'

# System dependencies
RUN set -eux; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
        netcat-traditional \
        gnupg \
        dirmngr \
        unzip \
	; \
	rm -rf /var/lib/apt/lists/*

# MediaWiki setup
RUN set -eux; \
    curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -o mediawiki.tar.gz; \
    curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz.sig" -o mediawiki.tar.gz.sig; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --fetch-keys "https://www.mediawiki.org/keys/keys.txt"; \
    gpg --batch --verify mediawiki.tar.gz.sig mediawiki.tar.gz; \
	mkdir -p /var/www/mediawiki; \
    tar -x --strip-components=1 -f mediawiki.tar.gz -C /var/www/mediawiki; \
    gpgconf --kill all; \
    # Replicate some skins and extensions on nginx so that their bundled assets can be accessed (e.g. icons/images/fonts)
    # Skin:Citizen
    curl -fSL "https://github.com/StarCitizenTools/mediawiki-skins-Citizen/archive/main.zip" -o skin-citizen.zip; \
    unzip skin-citizen.zip -d /var/www/mediawiki/skins; \
    mv /var/www/mediawiki/skins/mediawiki-skins-Citizen-main /var/www/mediawiki/skins/Citizen; \
    rm -r "$GNUPGHOME" mediawiki.tar.gz.sig mediawiki.tar.gz skin-citizen.zip; \
    mkdir -p /etc/nginx/templates/;

# TODO: Copy over configs
COPY ./config/mediawiki.conf /etc/nginx/templates/mediawiki.conf.template
COPY ./config/nginx.conf /etc/nginx/nginx.conf

# Copy over static files into webroot
COPY ./files/assets /var/www/mediawiki/resources/custom_assets

# Search engine stuff
COPY ./files/BingSiteAuth.xml /var/www/mediawiki/BingSiteAuth.xml
COPY ./files/google*.html /var/www/mediawiki/
COPY ./files/robots.txt /var/www/mediawiki/robots.txt
COPY ./files/well-known /var/www/mediawiki/.well-known

RUN set -eux; \
    ln -svf /var/www/mediawiki/sitemap/sitemap-attuproject.org-NS_0-0.xml /var/www/mediawiki/sitemap.xml; \
    chown -R www-data:www-data /var/www & \
    chmod -R +220 /var/www/mediawiki; \
    rm -r /etc/nginx/conf.d/*;
