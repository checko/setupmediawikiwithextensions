<?php
if ( !defined( 'MEDIAWIKI' ) ) {
    exit;
}

$wgSitename = getenv( 'MW_SITE_NAME' ) ?: 'MyWiki';
$wgMetaNamespace = str_replace( ' ', '_', $wgSitename );
$wgServer = rtrim( getenv( 'MW_SITE_SERVER' ) ?: 'http://localhost:9090', '/' );
$wgScriptPath = '';
$wgResourceBasePath = $wgScriptPath;
$wgArticlePath = '/$1';

$wgEmergencyContact = 'admin@example.com';
$wgPasswordSender = 'admin@example.com';
$wgEnotifUserTalk = false;
$wgEnotifWatchlist = false;
$wgEmailAuthentication = false;

$wgDBtype = 'mysql';
$wgDBserver = getenv( 'MW_DB_HOST' ) ?: 'db';
$wgDBname = getenv( 'MW_DB_NAME' ) ?: 'wikidb';
$wgDBuser = getenv( 'MW_DB_USER' ) ?: 'wiki';
$wgDBpassword = getenv( 'MW_DB_PASS' ) ?: 'wiki_pass';
$wgDBprefix = '';
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=binary';

$wgLanguageCode = getenv( 'MW_LANG' ) ?: 'en';
$wgDefaultSkin = 'vector';
$wgEnableUploads = true;

$wgSecretKey = getenv( 'MW_SECRET_KEY' ) ?: 'change-me-secret-key';
$wgUpgradeKey = getenv( 'MW_UPGRADE_KEY' ) ?: 'change-me-upgrade-key';

$wgMainCacheType = CACHE_NONE;
$wgParserCacheType = CACHE_NONE;
$wgCacheDirectory = false;

wfLoadSkin( 'Vector' );
