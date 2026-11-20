// Autolinking : paquet Android à enregistrer (iOS : podspec à la racine)
module.exports = {
  dependency: {
    platforms: {
      android: {
        packageImportPath: 'import com.boostyourapp.reactnative.BoostNetworkPackage;',
        packageInstance: 'new BoostNetworkPackage()',
      },
    },
  },
};
