/**
 * Config plugin Expo (npx expo prebuild) : le module natif est lié automatiquement ; ce plugin enregistre
 * en plus la clé de l'app dans la configuration native, pour appeler BoostNetwork.init() sans argument.
 *
 *   // app.json
 *   { "expo": { "plugins": [["@tals-enterprise/boostyourapp-react-native", { "appKey": "bya_…" }]] } }
 *
 * Android : meta-data com.boostyourapp.APP_KEY dans AndroidManifest.xml ; iOS : BoostNetworkAppKey dans Info.plist.
 */
const { AndroidConfig, createRunOncePlugin, withAndroidManifest, withInfoPlist } = require('expo/config-plugins');

const pkg = require('./package.json');

const META_DATA = 'com.boostyourapp.APP_KEY';
const INFO_PLIST_KEY = 'BoostNetworkAppKey';

function withBoostNetwork(config, props = {}) {
  const appKey = typeof props.appKey === 'string' ? props.appKey.trim() : '';
  if (!appKey) return config;
  if (!/^bya_[a-z0-9]+$/i.test(appKey)) {
    throw new Error(`@tals-enterprise/boostyourapp-react-native : appKey invalide (« ${appKey} »), attendu bya_…`);
  }

  config = withAndroidManifest(config, (modConfig) => {
    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(modConfig.modResults);
    AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, META_DATA, appKey);
    return modConfig;
  });

  config = withInfoPlist(config, (modConfig) => {
    modConfig.modResults[INFO_PLIST_KEY] = appKey;
    return modConfig;
  });

  return config;
}

module.exports = createRunOncePlugin(withBoostNetwork, pkg.name, pkg.version);
