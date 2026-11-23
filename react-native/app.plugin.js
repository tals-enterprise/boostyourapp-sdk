/**
 * Config plugin Expo (npx expo prebuild) : le module natif est lié automatiquement ; ce plugin enregistre
 * en plus la clé de l'app dans la configuration native, pour appeler BoostNetwork.init() sans argument.
 *
 *   // app.json : une clé par store (appKey seule : la même pour les deux plateformes)
 *   { "expo": { "plugins": [["@tals-enterprise/boostyourapp-react-native",
 *     { "androidAppKey": "bya_android…", "iosAppKey": "bya_ios…" }]] } }
 *
 * Android : meta-data com.boostyourapp.APP_KEY dans AndroidManifest.xml ; iOS : BoostNetworkAppKey dans Info.plist.
 */
const { AndroidConfig, createRunOncePlugin, withAndroidManifest, withInfoPlist } = require('expo/config-plugins');

const pkg = require('./package.json');

const META_DATA = 'com.boostyourapp.APP_KEY';
const INFO_PLIST_KEY = 'BoostNetworkAppKey';

/** Clé d'une option du plugin, vérifiée ; '' si absente */
function keyOption(props, name) {
  const value = typeof props[name] === 'string' ? props[name].trim() : '';
  if (value && !/^bya_[a-z0-9]+$/i.test(value)) {
    throw new Error(`@tals-enterprise/boostyourapp-react-native : ${name} invalide (« ${value} »), attendu bya_…`);
  }
  return value;
}

function withBoostNetwork(config, props = {}) {
  const shared = keyOption(props, 'appKey');
  const androidKey = keyOption(props, 'androidAppKey') || shared;
  const iosKey = keyOption(props, 'iosAppKey') || shared;

  if (androidKey) {
    config = withAndroidManifest(config, (modConfig) => {
      const application = AndroidConfig.Manifest.getMainApplicationOrThrow(modConfig.modResults);
      AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, META_DATA, androidKey);
      return modConfig;
    });
  }

  if (iosKey) {
    config = withInfoPlist(config, (modConfig) => {
      modConfig.modResults[INFO_PLIST_KEY] = iosKey;
      return modConfig;
    });
  }

  return config;
}

module.exports = createRunOncePlugin(withBoostNetwork, pkg.name, pkg.version);
