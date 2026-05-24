-- Run by the MariaDB container's first-init step (anything in
-- /docker-entrypoint-initdb.d/ executes as root before the container is
-- marked healthy).
--
-- MARIADB_DATABASE auto-creates `attu_wiki` and grants the attu user access.
-- This script fills in the second database YOURLS uses (attu_links) and
-- grants the same attu user access — same credential, two databases.
-- Required because MARIADB_DATABASE only takes a single value, and the
-- mariadb-dump from source uses the attu user (not root) so it can't
-- create databases or issue grants when loading.

CREATE DATABASE IF NOT EXISTS attu_links
    DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL ON attu_links.* TO 'attu'@'%';
FLUSH PRIVILEGES;
