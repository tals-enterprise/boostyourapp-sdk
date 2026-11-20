require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'BoostyourappReactNative'
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']
  s.homepage     = package['homepage']
  s.author       = package['author']
  s.source       = { :git => 'https://github.com/tals-enterprise/boostyourapp-sdk.git', :tag => s.version.to_s }
  s.platforms    = { :ios => '15.1' }
  s.swift_version = '5.0'

  # Pont React Native (Swift + déclaration Objective-C) et cœur iOS du SDK (dossier core, copié depuis sdk/ios)
  s.source_files = 'ios/**/*.{swift,h,m}'
  s.resource_bundles = { 'BoostyourappReactNativePrivacy' => ['ios/PrivacyInfo.xcprivacy'] }

  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency 'React-Core'
  end
end
