FROM nginx:latest

ENV APP_HOME="/app"

ARG MEDIAWIKI_MAJOR_VERSION='1.44'
ARG MEDIAWIKI_VERSION='1.44.0'
ARG MEDIAWIKI_BRANCH='REL1_44'

# System dependencies
RUN --mount=type=cache,target=/var/lib/apt \
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
    mkdir -p /etc/nginx/templates/ $APP_HOME/mediawiki; \
	chown -R www-data:www-data $APP_HOME; \
	chmod -R +220 $APP_HOME;

USER www-data
WORKDIR $APP_HOME

# MediaWiki setup
RUN set -eux; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" -o mediawiki.tar.gz; \
	curl -fSL "https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_MAJOR_VERSION}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz.sig" -o mediawiki.tar.gz.sig; \
	export GNUPGHOME="$(mktemp -d)"; \
    curl -fsSL "https://www.mediawiki.org/keys/keys.txt" | gpg --import; \
  	gpg --batch --verify mediawiki.tar.gz.sig mediawiki.tar.gz; \
	tar -x --strip-components=1 -f mediawiki.tar.gz -C $APP_HOME/mediawiki; \
	gpgconf --kill all; \
	rm -r "$GNUPGHOME" mediawiki.tar.gz.sig mediawiki.tar.gz;

# Replicate some skins and extensions on nginx so that their bundled assets can be accessed (e.g. icons/images/fonts)
# Skin:Citizen
RUN set -eux; \
    cd $APP_HOME/mediawiki/skins; \
	git clone --filter=blob:none https://github.com/StarCitizenTools/mediawiki-skins-Citizen.git Citizen; \
	rm -r ./Citizen/.git;

# Copy over static files into web root
COPY --chown=www-data:www-data ./files/assets/ $APP_HOME/mediawiki/resources/assets

# Dotfiles (mostly search engine stuff)
COPY --chown=www-data:www-data ./files/dotfiles/ $APP_HOME/mediawiki
COPY --chown=www-data:www-data ./config/robots.txt $APP_HOME/mediawiki

# Copy over nginx configs
COPY ./config/mediawiki.conf /etc/nginx/templates/mediawiki.conf.template
COPY ./config/nginx.conf /etc/nginx/nginx.conf

RUN set -eux; \
    ln -svf $APP_HOME/mediawiki/sitemap/sitemap-attuproject.org-NS_0-0.xml $APP_HOME/mediawiki/sitemap.xml;

USER root
