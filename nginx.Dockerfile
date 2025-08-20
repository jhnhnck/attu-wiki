FROM nginx:latest

# Version
ARG MEDIAWIKI_MAJOR_VERSION='1.44'
ARG MEDIAWIKI_VERSION='1.44.0'
ARG MEDIAWIKI_BRANCH='REL1_44'

# System dependencies
RUN RUN --mount=type=cache,target=/var/lib/apt \
    set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
        netcat-traditional \
        gnupg \
        dirmngr \
        unzip \
        git;


RUN set -eux; \
    rm -r /etc/nginx/conf.d/*; \
    mkdir -p /etc/nginx/templates/ /var/www/mediawiki; \
	chown -R www-data:www-data /var/www; \
	chmod -R +220 /var/www;
    
USER www-data
WORKDIR /var/www/mediawiki

# MediaWiki setup
RUN set -eux; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -o mediawiki.tar.gz; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz.sig" -o mediawiki.tar.gz.sig; \
	export GNUPGHOME="$(mktemp -d)"; \
    curl -fsSL "https://www.mediawiki.org/keys/keys.txt" | gpg --import; \
  	gpg --batch --verify mediawiki.tar.gz.sig mediawiki.tar.gz; \
	tar -x --strip-components=1 -f mediawiki.tar.gz -C /var/www/mediawiki; \
	gpgconf --kill all; \
	rm -r "$GNUPGHOME" mediawiki.tar.gz.sig mediawiki.tar.gz;

# Replicate some skins and extensions on nginx so that their bundled assets can be accessed (e.g. icons/images/fonts)
# Skin:Citizen
RUN set -eux; \
    cd /var/www/mediawiki/skins; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-skins-Citizen.git Citizen; \
	rm -r ./Citizen/.git;

# Copy over static files into webroot
COPY --chown=www-data:www-data ./files/assets /var/www/mediawiki/resources/custom_assets

# Search engine stuff
COPY --chown=www-data:www-data ./files/BingSiteAuth.xml /var/www/mediawiki/BingSiteAuth.xml
COPY --chown=www-data:www-data ./files/google*.html /var/www/mediawiki/
COPY --chown=www-data:www-data ./files/robots.txt /var/www/mediawiki/robots.txt
COPY --chown=www-data:www-data ./files/well-known /var/www/mediawiki/.well-known

# Copy over nginx configs
COPY ./config/mediawiki.conf /etc/nginx/templates/mediawiki.conf.template
COPY ./config/nginx.conf /etc/nginx/nginx.conf

RUN set -eux; \
    ln -svf /var/www/mediawiki/sitemap/sitemap-attuproject.org-NS_0-0.xml /var/www/mediawiki/sitemap.xml;

USER root
