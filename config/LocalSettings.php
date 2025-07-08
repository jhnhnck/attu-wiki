<?php
# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
	exit;
}

# Basic site identity
$wgSitename = "Attu Project";
$wgMetaNamespace = "Attu_Project";

# URL configuration
$wgScriptPath = "";
$wgServer = "https://attuproject.org";
$wgInternalServer = "http://attu-nginx-prod";
$wgResourceBasePath = $wgScriptPath;
$wgArticlePath = "/wiki/$1";
$wgUsePathInfo = true;
$wgForceHTTPS = true;

# Logos and icons
$wgLogos = [
	'1x' => "$wgResourceBasePath/resources/custom_assets/attu_thick_olive.svg",
	'wordmark' => [
		"src" => "$wgResourceBasePath/resources/custom_assets/attu_wordmark_v4.svg",
		"width" => 168,
		"height" => 30,
	],
	'icon' => "$wgResourceBasePath/resources/custom_assets/favicon.ico",
];

# Language and time
$wgLanguageCode = "en";
$wgLocaltimezone = "America/New_York";

# Email settings
$wgEnableEmail = true;
$wgEnableUserEmail = true;
$wgEmergencyContact = "doom@attuproject.org";
$wgPasswordSender = "doom@attuproject.org";
$wgEmailAuthentication = true;
$wgEnotifUserTalk = true;
$wgEnotifWatchlist = true;
$wgSMTP = [
	"host" => "ssl://in-v3.mailjet.com",
	"port" => 465,
	"auth" => true,
	"username" => "{$_ENV['SMTP_USERNAME']}",
	"password" => "{$_ENV['SMTP_PASSWORD']}",
];

# Database settings
$wgDBtype = "mysql";
$wgDBserver = "attu-database-prod";
$wgDBname = "attu_wiki";
$wgDBuser = "attu";
$wgDBpassword = "{$_ENV['ATTU_DB_PASSWORD']}";
$wgDBprefix = "";
$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";
$wgSharedTables[] = "actor";

# Cache settings
$wgMainCacheType = CACHE_MEMCACHED;
$wgMemCachedServers = [ 'memcached:11211' ];
# $wgCacheDirectory = "$IP/cache"; # Optional

# Uploads and media
$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = "/usr/bin/convert";
$wgUseInstantCommons = true;
$wgTmpDirectory = "/var/www/mediawiki/images/folk-vending-cucumber";  # only on mediawiki box, not possible to access

# Security and authentication
$wgSecretKey = "{$_ENV['ATTU_SECRET_KEY']}";
$wgUpgradeKey = "{$_ENV['ATTU_UPGRADE_KEY']}";
$wgAuthenticationTokenVersion = "1";
$wgEmailConfirmToEdit = true;
$wgAllowConfirmedEmail = true;
$wgGroupPermissions['*']['edit'] = false;
$wgGroupPermissions['user']['move-rootuserpages'] = true;
$wgGroupPermissions['autoconfirmed']['skipcaptcha'] = true;
$wgGroupPermissions['sysop']['tboverride'] = false;
$wgUsePrivateIPs = true;
$wgCdnServers = [ '10.22.4.232', '172.18.0.1', '10.22.0.254' ];
$wgUseCdn = true;

# CAPTCHA and ConfirmEdit
wfLoadExtensions([ 'ConfirmEdit', 'ConfirmEdit/Turnstile' ]);
$wgTurnstileSiteKey = "{$_ENV['TURNSTILE_SITE_KEY']}";
$wgTurnstileSecretKey = "{$_ENV['TURNSTILE_SECRET_KEY']}";

# Title blacklist
wfLoadExtension( 'TitleBlacklist' );
$wgTitleBlacklistSources = [
	[
		'type' => 'localpage',
		'src'  => 'MediaWiki:TitleBlacklist'
	],
	[
		'type' => 'url',
		'src'  => 'https://meta.wikimedia.org/w/index.php?title=Title_blacklist&action=raw'
	]
];

# Skins
wfLoadSkin( 'Citizen' );
wfLoadSkin( 'MinervaNeue' );
wfLoadSkin( 'MonoBook' );
wfLoadSkin( 'Timeless' );
wfLoadSkin( 'Vector' );
$wgDefaultSkin = 'citizen';

# Extensions
wfLoadExtension( 'CodeEditor' );
wfLoadExtension( 'VisualEditor' );
wfLoadExtension( 'WikiEditor' );
wfLoadExtension( 'ParserFunctions' );
$wgPFEnableStringFunctions = true;

wfLoadExtension( 'Scribunto' );
$wgScribuntoDefaultEngine = 'luastandalone';
// $wgScribuntoEngineConf['luastandalone']['errorFile'] = '/tmp/mw-lua-errors.log';

wfLoadExtension( 'TemplateStyles' );
wfLoadExtension( 'TemplateStylesExtender' );
wfLoadExtension( 'TemplateData' );
wfLoadExtension( 'InputBox' );

wfLoadExtension( 'SyntaxHighlight_GeSHi' );

wfLoadExtension( 'Discord' );
$wgDiscordWebhookURL = [ "{$_ENV['ATTU_WEBHOOK']}" ];
$wgDiscordDisabledUsers = [ "127.0.0.1" ];
$wgDiscordNoBots = false;

wfLoadExtension( 'OpenGraphMeta' );
wfLoadExtension( 'Math' );

wfLoadExtension( 'StopForumSpam' );
$wgSFSIPListLocation = "{$wgInternalServer}/resources/listed_ip_30_all.txt";

wfLoadExtension( 'EasyTimeline' );
$wgTimelineFontDirectory = "/usr/share/fonts/truetype/freefont";
$wgTimelineFonts = "/usr/share/fonts/truetype/freefont/FreeSans.ttf";

wfLoadExtension( 'ShortDescription' );
$wgShortDescriptionExtendOpenSearchXml = true;
$wgCitizenSearchDescriptionSource = 'wikidata';

wfLoadExtension( 'PageImages' );
wfLoadExtension( 'TextExtracts' );

wfLoadExtension( 'Thumbro' );
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

wfLoadExtension( 'Interwiki' );
$wgGroupPermissions['sysop']['interwiki'] = true;

wfLoadExtension( 'CreatePageUw' );

# Namespaces
$wgExtraNamespaces[NS_TALK] = "Meta";
$wgNamespaceAliases['Talk'] = NS_TALK;

$wgNamespacesToBeSearchedDefault = [
	NS_MAIN => true,
	NS_TALK => true,
];

# Misc
$wgPingback = true;
$wgRightsPage = "";
$wgRightsUrl = "";
$wgRightsText = "";
$wgRightsIcon = "";
$wgDiff3 = "/usr/bin/diff3";
ini_set( 'post_max_size', '100M' );
ini_set( 'upload_max_filesize', '100M' );
$wgShowExceptionDetails = false;

$attuIsWikiDiff2Enabled = extension_loaded( 'wikidiff2' );
if ( $attuIsWikiDiff2Enabled ) {
	$wgDiffEngine = 'wikidiff2';
}

# Uncomment to restrict account creation
# $wgGroupPermissions['*']['createaccount'] = false;

# Uncomment for maintenance mode
# $wgReadOnly = 'This wiki is currently undergoing a hardware upgrade. Check back in a couple of hours.';

# Development Mode Overrides
if ( !empty($_ENV['ATTU_DEV_MODE']) ) {

	$wgServer = "https://dev.attuproject.org";
		$wgInternalServer = "http://attu-nginx-dev";
		$wgShowExceptionDetails = true;

	$wgDiscordWebhookURL = [ "{$_ENV['ATTU_ALT_WEBHOOK']}" ];
	$wgSFSIPListLocation = "{$wgInternalServer}/resources/listed_ip_30_all.txt";

		# Enable debug logging (adjust path as needed)
		# $wgDebugLogFile = "/var/log/mediawiki/debug-{$wgDBname}.log";

	$wgEnableEmail = false;
	$wgEnableUserEmail = false;
}

?>
