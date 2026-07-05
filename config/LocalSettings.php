<?php
/**
 * Attu Project Wiki - MediaWiki Local Settings file
 * This file is licensed under the MIT License; See LICENSE for full text.
 */

# Protect against web entry
if (!defined('MEDIAWIKI')) {
    exit;
}

# Basic site identity
$wgSitename = 'Attu Project';
$wgMetaNamespace = 'Attu_Project';

# Story Namespace
define('NS_STORY', 100);
define('NS_STORY_TALK', 101);
$wgExtraNamespaces[NS_STORY] = 'Story';
$wgExtraNamespaces[NS_STORY_TALK] = 'Story_talk';
$wgContentNamespaces[] = NS_STORY;

# Record Namespace
define('NS_RECORD', 102);
define('NS_RECORD_TALK', 103);
$wgExtraNamespaces[NS_RECORD] = 'Record';
$wgExtraNamespaces[NS_RECORD_TALK] = 'Record_talk';
$wgContentNamespaces[] = NS_RECORD;

# Dictionary Namespace
define('NS_DICT', 104);
define('NS_DICT_TALK', 105);
$wgExtraNamespaces[NS_DICT] = 'Dict';
$wgExtraNamespaces[NS_DICT_TALK] = 'Dict_talk';
$wgContentNamespaces[] = NS_DICT;

# Rename Talk Namespace to Meta
$wgExtraNamespaces[NS_TALK] = 'Meta';
$wgNamespaceAliases['Talk'] = NS_TALK;
$wgContentNamespaces[] = NS_TALK;

$wgNamespacesToBeSearchedDefault = [
    NS_MAIN => true,
    NS_TALK => true,
    NS_CATEGORY => true,
    NS_STORY => true,
    NS_RECORD => true,
    NS_DICT => true,
];

# URL configuration
$wgScriptPath = '';
$wgServer = 'https://attuproject.org';
$wgInternalServer = 'http://mediawiki:8080';
$wgResourceBasePath = $wgScriptPath;
$wgArticlePath = '/wiki/$1';
$wgScript = '/wiki';
$wgUsePathInfo = true;
$wgForceHTTPS = true;

# Logos and icons
$wgLogos = [
    '1x' => "{$wgResourceBasePath}/resources/assets/attu-olive.svg",
    'wordmark' => [
        'src' => "{$wgResourceBasePath}/resources/assets/attu-wordmark.svg",
        'width' => 168,
        'height' => 30,
    ],
    'icon' => "{$wgResourceBasePath}/resources/assets/favicon.ico",
];

# Language and time
$wgLanguageCode = 'en';
$wgLocaltimezone = 'America/New_York';

# Email settings
$wgEnableEmail = true;
$wgEnableUserEmail = true;
$wgEmergencyContact = 'doom@attuproject.org';
$wgPasswordSender = 'doom@attuproject.org';
$wgEmailAuthentication = true;
$wgEnotifUserTalk = true;
$wgEnotifWatchlist = true;

// edit protection
$wgEmailConfirmToEdit = true;
$wgAllowConfirmedEmail = true;

# Not well documented; code reference: <https://github.com/pear/Mail/blob/master/Mail/smtp.php>
$wgSMTP = [
    'host' => 'smtp.protonmail.ch',
    'port' => 587,
    'auth' => true,
    'starttls' => true,
    'username' => "{$_ENV['SMTP_USERNAME']}",
    'password' => "{$_ENV['SMTP_PASSWORD']}",
];

# Database settings
$wgDBtype = 'mysql';
$wgDBserver = 'database';
$wgDBname = 'attu_wiki';
$wgDBuser = 'attu';
$wgDBpassword = "{$_ENV['ATTU_DB_PASSWORD']}";
$wgDBprefix = '';
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=binary';
$wgSharedTables[] = 'actor';

# Cache settings
$attuRedisServer = 'redis';
$wgCachePrefix = 'attu_wiki';
$wgSessionName = 'brch_session';

define('CACHE_REDIS', 'redis');
$wgMainCacheType = CACHE_REDIS;
$wgSessionCacheType = CACHE_REDIS;
$wgParserCacheType  = CACHE_REDIS;

# Uploads and media
$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = '/usr/bin/convert';
$wgUseInstantCommons = true;
$wgTmpDirectory =  "/tmp";

# Security and authentication
$wgSecretKey = "{$_ENV['ATTU_SECRET_KEY']}";
$wgUpgradeKey = "{$_ENV['ATTU_UPGRADE_KEY']}";
$wgAuthenticationTokenVersion = '1';
$wgShowExceptionDetails = false;

// Upstream info
$wgUsePrivateIPs = true;
$wgCdnServersNoPurge = ['172.16.0.0/12', '10.22.0.254'];
$wgUseCdn = true;

// blocking
$wgAutoblockExemptions = ['127.0.0.0/8', '172.16.0.0/12', '10.0.0.0/8', '100.64.0.0/10'];
$wgBlockAllowsUTEdit = false;  // disable ban appeals

# Development Mode Overrides
$attuDevMode = !empty($_ENV['BUILD_TYPE']) && $_ENV['BUILD_TYPE'] == 'dev';

if ($attuDevMode) {
    $wgServer = 'https://dev.attuproject.org';
    $wgShowExceptionDetails = true;

    # Enable debug logging
    $wgDebugLogFile = "{$_ENV['APP_HOME']}/logs/debug-{$wgDBname}.log";

    $wgEnableEmail = false;
    $wgEnableUserEmail = false;
}

$wgObjectCaches['redis'] = [
    'class' => 'RedisBagOStuff',
    'servers' => [$attuRedisServer . ':6379'],
    'persistent' => true,
];

# Jobs
$wgJobRunRate = 0;
$wgJobTypeConf['default'] = [
    'class' => 'JobQueueRedis',
    'redisServer' => $attuRedisServer . ':6379',
    'redisConfig' => [],
    'claimTTL' => 3600,
    'daemonized' => true,
 ];

// Roles
$wgGroupPermissions['*']['edit'] = false;  // anon edits
$wgGroupPermissions['member']['move-rootuserpages'] = true;
$wgGroupPermissions['member']['edit'] = true;

$wgGroupPermissions['destroyer']['delete'] = true;

// CAPTCHA and ConfirmEdit
$wgGroupPermissions['autoconfirmed']['skipcaptcha'] = true;
wfLoadExtensions(['ConfirmEdit', 'ConfirmEdit/Turnstile']);
$wgCaptchaClass = MediaWiki\Extension\ConfirmEdit\Turnstile\Turnstile::class;
$wgTurnstileSiteKey = "{$_ENV['TURNSTILE_SITE_KEY']}";
$wgTurnstileSecretKey = "{$_ENV['TURNSTILE_SECRET_KEY']}";

# Skins
wfLoadSkin('Citizen');
wfLoadSkin('MinervaNeue');
wfLoadSkin('MonoBook');
wfLoadSkin('Timeless');
wfLoadSkin('Vector');
$wgDefaultSkin = 'citizen';

# Editors
wfLoadExtension('CodeEditor');
wfLoadExtension('VisualEditor');
$wgDefaultUserOptions['visualeditor-editor'] = 'visualeditor';
$wgDefaultUserOptions['visualeditor-newwikitext'] = 1;
$wgVisualEditorEnableDiffPage = true;
$wgVisualEditorEnableWikitext = true;
$wgVisualEditorUseSingleEditTab = true;
wfLoadExtension('WikiEditor');
// wfLoadExtension('AttuEditor'); // disabled until tree-editor build output is ready
wfLoadExtension('ParserFunctions');
$wgPFEnableStringFunctions = true;

# Other Extensions

## Extension Config
$wgGitRepositoryViewers['https://github.com/(.*?)(\.git)?'] = 'https://github.com/%R/commit/%H';

wfLoadExtension('Scribunto');
$wgScribuntoDefaultEngine = 'luastandalone';
// $wgScribuntoEngineConf['luastandalone']['errorFile'] = '/tmp/mw-lua-errors.log';

wfLoadExtension('TemplateStyles');
wfLoadExtension('TemplateStylesExtender');
wfLoadExtension('TemplateData');
wfLoadExtension('InputBox');
wfLoadExtension('Cite');

# Notifications
$wgAllowHTMLEmail = true;
wfLoadExtension('Echo');
$wgEchoUseJobQueue = true;
$wgEchoWatchlistNotifications = true;
$wgEchoAgentBlacklist = [ 'DoomBot' ];
$wgEchoEmailFooterAddress = "Powered by DoomBot.";
$wgNotificationSenderName = "{$wgSitename} Wiki";
$wgEchoMaxUpdateCount = 99999 + 1;

wfLoadExtension('SyntaxHighlight_GeSHi');

# btw this ones mine -jhn
wfLoadExtension('NovaDiscord');
$wgDiscordNoBots = false;
$wgDiscordPrivateExceptionAlerts = true;

$wgDiscordWebhooks = [['url' => "{$_ENV['ATTU_WIKI_WEBHOOK_ERROR']}", 'hooks' => ['LogException']]];

if (!$attuDevMode) {
    $wgDiscordWebhooks[] = ['url' => "{$_ENV['ATTU_WIKI_WEBHOOK']}"];
    $wgDiscordDisabledUsers = ['127.0.0.1'];
} else {
    $wgDiscordWebhooks[] = ['url' => "{$_ENV['ATTU_WIKI_WEBHOOK_ALT']}"];
}

$wgDiscordExceptionDenyList = [
    // Host workstation reboot windows; brief 5xx until DB container is healthy.
    // Going away with the planned server migration.
    ['class' => 'Wikimedia\Rdbms\DBConnectionError',
     'messageContains' => 'Connection refused'],
    ['class' => 'Wikimedia\Rdbms\DBQueryDisconnectedError',
     'messageContains' => 'MySQL server has gone away'],

    // Race between parallel runJobs.php workers updating page_links_updated.
    // Benign — link tables already updated, only the timestamp UPDATE collided.
    ['class' => 'Wikimedia\Rdbms\DBQueryError',
     'messageContains' => 'Error 1020'],
];

// route exceptions to a dedicated log file in both dev and prod
$wgDebugLogGroups['exception'] = "{$_ENV['APP_HOME']}/logs/exception-{$wgDBname}.log";

wfLoadExtension('OpenGraphMeta');
wfLoadExtension('Math');

wfLoadExtension('StopForumSpam');
$wgSFSIPListLocation = "$IP/resources/listed_ip_30_all.txt";

wfLoadExtension('EasyTimeline');
$wgTimelineFontDirectory = $_ENV['APP_HOME'] . '/fonts/freefont';
$wgTimelineFonts = $wgTimelineFontDirectory . '/FreeSans.ttf';
$wgTimelineFontFile = 'FreeSans';

wfLoadExtension('ShortDescription');
$wgShortDescriptionExtendOpenSearchXml = true;
$wgCitizenSearchDescriptionSource = 'wikidata';

wfLoadExtension('PageImages');
wfLoadExtension('TextExtracts');
wfLoadExtension('CategoryTree');
wfLoadExtension('Drafts');
$wgParsoidCacheConfig['StashType'] = CACHE_REDIS;
$wgParsoidCacheConfig['StashDuration'] = 7 * 24 * 60 * 60;

wfLoadExtension('Thumbro');
$wgGenerateThumbnailOnParse = true;
$wgThumbnailEpoch = 20250601000000;

wfLoadExtension('Interwiki');
$wgGroupPermissions['sysop']['interwiki'] = true;

wfLoadExtension('CreatePageUw');

wfLoadExtension('Linter');

# Misc
$wgPingback = true;
$wgRightsPage = '';
$wgRightsUrl = '';
$wgRightsText = '';
$wgRightsIcon = '';
$wgDiff3 = '/usr/bin/diff3';

$attuIsWikiDiff2Enabled = extension_loaded('wikidiff2');
if ( $attuIsWikiDiff2Enabled ) {
    $wgDiffEngine = 'wikidiff2';
}
