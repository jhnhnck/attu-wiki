<?php
/**
 * NovaDiscord - onPageSaveComplete Hook
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

# Namespaces
$wgExtraNamespaces[NS_TALK] = 'Meta';
$wgNamespaceAliases['Talk'] = NS_TALK;

$wgNamespacesToBeSearchedDefault = [
    NS_MAIN => true,
    NS_TALK => true,
    NS_CATEGORY => true,
    NS_STORY => true,
];

$wgContentNamespaces[] = NS_TALK;
$wgContentNamespaces[] = NS_STORY;

# URL configuration
$wgScriptPath = '';
$wgServer = 'https://attuproject.org';
$wgInternalServer = 'http://nginx';
$wgResourceBasePath = $wgScriptPath;
$wgArticlePath = '/wiki/$1';
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
$wgSessionName = 'brch_sesssion';

define('CACHE_REDIS', 'redis');
$wgMainCacheType = CACHE_REDIS;
$wgSessionCacheType = CACHE_REDIS;
$wgParserCacheType  = CACHE_REDIS;

# Uploads and media
$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = '/usr/bin/convert';
$wgUseInstantCommons = true;
$wgTmpDirectory =  "{$_ENV['APP_HOME']}/mediawiki/images/folk-vending-cucumber";  # only on mediawiki box, not possible to access

# Security and authentication
$wgSecretKey = "{$_ENV['ATTU_SECRET_KEY']}";
$wgUpgradeKey = "{$_ENV['ATTU_UPGRADE_KEY']}";
$wgAuthenticationTokenVersion = '1';
$wgEmailConfirmToEdit = true;
$wgAllowConfirmedEmail = true;
$wgGroupPermissions['*']['edit'] = false;
$wgGroupPermissions['user']['move-rootuserpages'] = true;
$wgGroupPermissions['autoconfirmed']['skipcaptcha'] = true;
$wgGroupPermissions['sysop']['tboverride'] = false;
$wgUsePrivateIPs = true;
$wgCdnServersNoPurge = ['172.16.0.0/12', '10.22.0.254'];
$wgAutoblockExemptions = ['172.16.0.0/12', '10.22.0.0/22'];
$wgUseCdn = true;
$wgShowExceptionDetails = false;

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

# CAPTCHA and ConfirmEdit
wfLoadExtensions(['ConfirmEdit', 'ConfirmEdit/Turnstile']);
$wgCaptchaClass = MediaWiki\Extension\ConfirmEdit\Turnstile\Turnstile::class;
$wgTurnstileSiteKey = "{$_ENV['TURNSTILE_SITE_KEY']}";
$wgTurnstileSecretKey = "{$_ENV['TURNSTILE_SECRET_KEY']}";

// # Title blacklist
// wfLoadExtension('TitleBlacklist');
// $wgTitleBlacklistSources = [
// 	[
// 		'type' => 'localpage',
// 		'src'  => 'MediaWiki:TitleBlacklist'
// 	],
// 	[
// 		'type' => 'url',
// 		'src'  => 'https://meta.wikimedia.org/w/index.php?title=Title_blacklist&action=raw'
// 	]
// ];

# Roles
$wgGroupPermissions['destroyer']['delete'] = true;
# Uncomment to restrict account creation
# $wgGroupPermissions['*']['createaccount'] = false;

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
wfLoadExtension('ParserFunctions');
$wgPFEnableStringFunctions = true;

# Other Extensions

wfLoadExtension('Scribunto');
$wgScribuntoDefaultEngine = 'luastandalone';
// $wgScribuntoEngineConf['luastandalone']['errorFile'] = '/tmp/mw-lua-errors.log';

wfLoadExtension('TemplateStyles');
wfLoadExtension('TemplateStylesExtender');
wfLoadExtension('TemplateData');
wfLoadExtension('InputBox');
wfLoadExtension('Cite');

# Notifications
wfLoadExtension('Echo');
$wgEchoUseJobQueue = true;
$wgEchoWatchlistNotifications = true;

wfLoadExtension('SyntaxHighlight_GeSHi');

wfLoadExtension('NovaDiscord');
$wgDiscordNoBots = false;

if (!$attuDevMode) {
    $wgDiscordWebhookURL = ["{$_ENV['ATTU_WIKI_WEBHOOK']}"];
    $wgDiscordDisabledUsers = ['127.0.0.1'];
} else {
    $wgDiscordWebhookURL = ["{$_ENV['ATTU_WIKI_WEBHOOK_ALT']}"];
}

wfLoadExtension('OpenGraphMeta');
wfLoadExtension('Math');

wfLoadExtension('StopForumSpam');
$wgSFSIPListLocation = "{$wgInternalServer}/resources/listed_ip_30_all.txt";

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

wfLoadExtension('Thumbro');
$wgThumbnailEpoch = 20250601000000;
// $wgThumbroOptions['value']['image/png'] = [
//     'enabled' => true,
//     'library' => 'libvips',
//     'inputOptions' => [],
//     'outputOptions' => [
//         'strip' => 'true',
//         'filter' => 'VIPS_FOREIGN_PNG_FILTER_ALL',
//         'resize' => 'x1500>'
//     ]
// ];

wfLoadExtension('Interwiki');
$wgGroupPermissions['sysop']['interwiki'] = true;

wfLoadExtension('CreatePageUw');

# Misc
$wgPingback = true;
$wgRightsPage = '';
$wgRightsUrl = '';
$wgRightsText = '';
$wgRightsIcon = '';
$wgDiff3 = '/usr/bin/diff3';
ini_set('post_max_size', '100M');
ini_set('upload_max_filesize', '100M');

$attuIsWikiDiff2Enabled = extension_loaded('wikidiff2');
if ( $attuIsWikiDiff2Enabled ) {
    $wgDiffEngine = 'wikidiff2';
}
