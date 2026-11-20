require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'BoostyourappCapacitor'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['homepage']
  s.author = package['author']
  s.source = { :git => 'https://github.com/tals-enterprise/boostyourapp-sdk.git', :tag => s.version.to_s }
  # Pont Capacitor et cœur iOS du SDK (dossier Core)
  s.source_files = 'ios/Sources/**/*.swift'
  s.resource_bundles = { 'BoostyourappCapacitorPrivacy' => ['ios/Sources/BoostNetworkPlugin/PrivacyInfo.xcprivacy'] }
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
end
