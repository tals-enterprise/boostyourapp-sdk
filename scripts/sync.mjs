#!/usr/bin/env node
// Synchronise les SDK à partir des deux cœurs natifs (sdk/android/network et sdk/ios) :
//
//   1. génère la configuration des cœurs (Config.kt, Config.swift) depuis sdk/android/gradle.properties :
//      URL et clé publique du projet Supabase du réseau, version du SDK ;
//   2. copie les cœurs dans les plugins, qui les embarquent sous forme de sources (ou d'AAR pour Cordova) :
//
//      node sdk/scripts/sync.mjs                       # tous les plugins
//      node sdk/scripts/sync.mjs capacitor cordova     # certains seulement
//      node sdk/scripts/sync.mjs --config              # configuration seule
//
// Les copies ne sont pas versionnées (.gitignore) : lancer ce script avant de construire ou publier un plugin
// (les scripts prepack des plugins le font).
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SDK = join(dirname(fileURLToPath(import.meta.url)), '..')
const ANDROID_PROJECT = join(SDK, 'android')
const ANDROID_CORE = join(ANDROID_PROJECT, 'network/src/main/java/com/boostyourapp/network')
const IOS_CORE = join(SDK, 'ios/Sources/BoostNetwork')
const PRIVACY = join(IOS_CORE, 'PrivacyInfo.xcprivacy')

const PLUGINS = {
  capacitor() {
    copySources(ANDROID_CORE, join(SDK, 'capacitor/android/src/main/java/com/boostyourapp/network'), '.kt')
    copySources(IOS_CORE, join(SDK, 'capacitor/ios/Sources/BoostNetworkPlugin/Core'), '.swift')
    copyFile(PRIVACY, join(SDK, 'capacitor/ios/Sources/BoostNetworkPlugin/PrivacyInfo.xcprivacy'))
  },

  cordova() {
    // Android : AAR du cœur (pas de plugin Kotlin à configurer dans l'app Cordova), pont en Java
    copyFile(buildAndroidAar(), join(SDK, 'cordova/src/android/boost-network.aar'))
    const files = copySources(IOS_CORE, join(SDK, 'cordova/src/ios/core'), '.swift')
    copyFile(PRIVACY, join(SDK, 'cordova/src/ios/PrivacyInfo.xcprivacy'))
    // plugin.xml liste chaque fichier source (pas de motifs) : bloc régénéré entre deux marqueurs
    const pluginXml = join(SDK, 'cordova/plugin.xml')
    const block = files.map(f => `        <source-file src="src/ios/core/${f}" />`).join('\n')
    const xml = readFileSync(pluginXml, 'utf8')
    const markers = /(<!-- core:ios:start -->)[\s\S]*?(<!-- core:ios:end -->)/
    if (!markers.test(xml)) throw new Error('Marqueurs core:ios absents de plugin.xml')
    writeIfChanged(pluginXml, xml.replace(markers, `$1\n${block}\n        $2`))
  },

  'react-native'() {
    copySources(ANDROID_CORE, join(SDK, 'react-native/android/src/main/java/com/boostyourapp/network'), '.kt')
    copySources(IOS_CORE, join(SDK, 'react-native/ios/core'), '.swift')
    copyFile(PRIVACY, join(SDK, 'react-native/ios/PrivacyInfo.xcprivacy'))
  }
}

// --- Configuration -------------------------------------------------------------------------------

function readProperties(file) {
  const result = {}
  for (const line of readFileSync(file, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([\w.]+)\s*=\s*(.*?)\s*$/)
    if (match) result[match[1]] = match[2]
  }
  return result
}

function generateConfig() {
  const props = readProperties(join(ANDROID_PROJECT, 'gradle.properties'))
  const config = { apiUrl: props['boost.apiUrl'], apiKey: props['boost.apiKey'], version: props['boost.version'] }
  for (const [key, value] of Object.entries(config)) {
    if (!value || /["\\$\n]/.test(value)) throw new Error(`boost.${key} manquant ou invalide dans gradle.properties`)
  }
  const header = '// Généré par sdk/scripts/sync.mjs depuis sdk/android/gradle.properties : ne pas modifier à la main.'

  writeIfChanged(join(ANDROID_CORE, 'Config.kt'), `${header}
package com.boostyourapp.network

/** Projet Supabase du réseau, intégré au SDK publié : URL et clé publique (sb_publishable_…). */
internal object BoostConfig {
    const val API_URL = "${config.apiUrl}"
    const val API_KEY = "${config.apiKey}"
    const val SDK_VERSION = "${config.version}"
}
`)

  writeIfChanged(join(IOS_CORE, 'Config.swift'), `${header}

/// Projet Supabase du réseau, intégré au SDK publié : URL et clé publique (sb_publishable_…).
enum BoostConfig {
    static let apiUrl = "${config.apiUrl}"
    static let apiKey = "${config.apiKey}"
    static let sdkVersion = "${config.version}"
}
`)

  // Version des paquets npm des plugins alignée sur celle du SDK
  for (const plugin of ['capacitor', 'cordova', 'react-native']) {
    const file = join(SDK, plugin, 'package.json')
    if (!existsSync(file)) continue
    const text = readFileSync(file, 'utf8')
    writeIfChanged(file, text.replace(/("version":\s*")[^"]*(")/, `$1${config.version}$2`))
  }
  const pluginXml = join(SDK, 'cordova/plugin.xml')
  if (existsSync(pluginXml)) {
    const xml = readFileSync(pluginXml, 'utf8')
    writeIfChanged(pluginXml, xml.replace(/(<plugin\b[^>]*\bversion=")[^"]*(")/, `$1${config.version}$2`))
  }

  if (config.apiUrl.includes('YOUR_PROJECT') || config.apiKey.includes('REPLACE_ME')) {
    console.warn('Attention : URL ou clé du réseau encore fictives dans sdk/android/gradle.properties')
  }
}

// --- Outils --------------------------------------------------------------------------------------

function writeIfChanged(file, content) {
  if (existsSync(file) && readFileSync(file, 'utf8') === content) return
  mkdirSync(dirname(file), { recursive: true })
  writeFileSync(file, content)
  console.log(`écrit  ${file.slice(SDK.length + 1)}`)
}

function copyFile(source, target) {
  mkdirSync(dirname(target), { recursive: true })
  copyFileSync(source, target)
  console.log(`copié  ${target.slice(SDK.length + 1)}`)
}

/** Remplace le dossier cible par les fichiers `extension` du dossier source ; renvoie leurs noms triés. */
function copySources(source, target, extension) {
  rmSync(target, { recursive: true, force: true })
  mkdirSync(target, { recursive: true })
  const files = readdirSync(source).filter(f => f.endsWith(extension)).sort()
  for (const file of files) copyFileSync(join(source, file), join(target, file))
  console.log(`copié  ${target.slice(SDK.length + 1)} (${files.length} fichiers)`)
  return files
}

function buildAndroidAar() {
  // Sans démon : un démon Gradle garderait ouverte la sortie du script (et bloquerait un `| grep`)
  const task = [':network:assembleRelease', '--quiet', '--no-daemon']
  const options = { cwd: ANDROID_PROJECT, stdio: ['ignore', 'inherit', 'inherit'] }
  const result = process.platform === 'win32'
    // Chemin complet entre guillemets (cmd /s retire la paire extérieure) : cmd ne cherche pas toujours dans le dossier courant
    ? spawnSync('cmd.exe', ['/d', '/s', '/c', `""${join(ANDROID_PROJECT, 'gradlew.bat')}" ${task.join(' ')}"`], { ...options, windowsVerbatimArguments: true })
    : spawnSync('./gradlew', task, options)
  if (result.status !== 0) throw new Error('Échec de la construction de l\'AAR Android (sdk/android)')
  return join(ANDROID_PROJECT, 'network/build/outputs/aar/network-release.aar')
}

// --- Main ----------------------------------------------------------------------------------------

const args = process.argv.slice(2)
generateConfig()
if (!args.includes('--config')) {
  const targets = args.filter(a => !a.startsWith('--'))
  for (const name of targets.length ? targets : Object.keys(PLUGINS)) {
    if (!PLUGINS[name]) throw new Error(`Plugin inconnu : ${name} (${Object.keys(PLUGINS).join(', ')})`)
    PLUGINS[name]()
  }
}
