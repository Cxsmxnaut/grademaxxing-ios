#!/usr/bin/env python3
"""Headless source/archive checks. A pass is not App Store approval or completed device QA."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PRODUCTION = 'https://grademaxxing.app'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def plist(path):
    with path.open('rb') as file:
        return plistlib.load(file)


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.STDOUT)


def check_privacy(path):
    manifest = plist(path)
    require(manifest.get('NSPrivacyTracking') is False, 'Tracking must remain disabled.')
    require(manifest.get('NSPrivacyTrackingDomains') == [], 'Unexpected tracking domains.')
    entries = {item['NSPrivacyCollectedDataType']: item
               for item in manifest.get('NSPrivacyCollectedDataTypes', [])}
    for suffix in ('UserID', 'ProductInteraction', 'CoarseLocation'):
        item = entries.get('NSPrivacyCollectedDataType' + suffix, {})
        require(item.get('NSPrivacyCollectedDataTypeLinked') is True,
                f'{suffix} must disclose account-linked backend usage.')
        require(item.get('NSPrivacyCollectedDataTypeTracking') is False,
                f'Unexpected tracking for {suffix}.')
        require('NSPrivacyCollectedDataTypePurposeAnalytics'
                in item.get('NSPrivacyCollectedDataTypePurposes', []),
                f'{suffix} must disclose the analytics purpose.')


def source_checks():
    run(sys.executable, 'scripts/generate-project.py', '--check')
    run(sys.executable, 'scripts/bundle-notices.py', '--check')
    project = json.loads(run('plutil', '-convert', 'json', '-o', '-', '--',
                             str(ROOT / 'Grademaxxing.xcodeproj/project.pbxproj')))
    objects = project['objects']
    app = next(item for item in objects.values()
               if item.get('isa') == 'PBXNativeTarget' and item.get('name') == 'Grademaxxing')
    configurations = objects[app['buildConfigurationList']]['buildConfigurations']
    settings = {objects[key]['name']: objects[key]['buildSettings'] for key in configurations}
    release = settings['Release']
    require(release.get('GRADEMAXXING_API_ORIGIN') == PRODUCTION,
            'Release must use the production HTTPS origin.')
    require(settings['Debug'].get('GRADEMAXXING_API_ORIGIN') == 'https://dev.grademaxxing.app',
            'Debug must stay on pre-production.')
    require(re.fullmatch(r'\d+\.\d+\.\d+', release.get('MARKETING_VERSION', '')),
            'Release marketing version must have three numeric components.')
    require(re.fullmatch(r'\d+(\.\d+){0,2}', release.get('CURRENT_PROJECT_VERSION', '')),
            'Release build number must be numeric.')
    info = plist(ROOT / 'App/Info.plist')
    for key, value in {
        'GrademaxxingAPIOrigin': '$(GRADEMAXXING_API_ORIGIN)',
        'CFBundleShortVersionString': '$(MARKETING_VERSION)',
        'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
        'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'ITSAppUsesNonExemptEncryption': False,
    }.items():
        require(info.get(key) == value, f'Unexpected source Info.plist setting: {key}')
    require(not info.get('NSAppTransportSecurity'), 'Review unexpected ATS exceptions before release.')
    check_privacy(ROOT / 'App/PrivacyInfo.xcprivacy')
    icons = ROOT / 'App/Assets.xcassets/AppIcon.appiconset'
    entries = json.loads((icons / 'Contents.json').read_text())['images']
    require(len(entries) == 1 and entries[0].get('size') == '1024x1024',
            'A universal 1024 × 1024 app icon is required.')
    data = (icons / entries[0]['filename']).read_bytes()
    require(data[:8] == b'\x89PNG\r\n\x1a\n', 'App icon must be a PNG.')
    width, height, depth, color = struct.unpack('>IIBB', data[16:26])
    require((width, height, depth, color) == (1024, 1024, 8, 2),
            'App icon must be 1024 × 1024, 8-bit RGB without alpha.')
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        require(data[offset + 4:offset + 8] != b'tRNS', 'App icon must not use PNG transparency.')
        offset += length + 12
    scheme = ET.parse(ROOT / 'Grademaxxing.xcodeproj/xcshareddata/xcschemes/Grademaxxing.xcscheme')
    archive = scheme.getroot().find('ArchiveAction')
    require(archive is not None and archive.get('buildConfiguration') == 'Release',
            'Archives must use Release.')
    require(archive.get('revealArchiveInOrganizer') == 'NO', 'Archives must remain headless.')
    metadata = json.loads((ROOT / 'AppStore/en-US.json').read_text())
    for field, limit in {
        'name': 30, 'subtitle': 30, 'promotional_text': 170, 'keywords': 100,
        'description': 4000, 'whats_new': 4000, 'review_notes': 4000,
    }.items():
        require(isinstance(metadata.get(field), str) and 0 < len(metadata[field]) <= limit,
                f'App Store {field} must contain 1–{limit} characters.')
    require(metadata['privacy_policy_url'] == PRODUCTION + '/privacy',
            'Unexpected App Store privacy policy URL.')
    print('PASS source release configuration, opaque icon, privacy disclosures, bundled notices, project, metadata limits')
    return release


def archive_checks(path, release, allow_unsigned):
    app = path / 'Products/Applications/Grademaxxing.app'
    require(app.is_dir(), 'Archive does not contain Grademaxxing.app.')
    info = plist(app / 'Info.plist')
    for key, expected in {
        'GrademaxxingAPIOrigin': PRODUCTION,
        'CFBundleIdentifier': release['PRODUCT_BUNDLE_IDENTIFIER'],
        'CFBundleShortVersionString': release['MARKETING_VERSION'],
        'CFBundleVersion': release['CURRENT_PROJECT_VERSION'],
        'ITSAppUsesNonExemptEncryption': False,
        'UIDeviceFamily': [1],
    }.items():
        require(info.get(key) == expected, f'Archived {key} does not match Release: {expected}')
    require(int(info.get('DTXcode', '0')) >= 2600, 'Archive requires Xcode 26 or later.')
    sdk = re.fullmatch(r'iphoneos(\d+)(?:\.\d+)*', info.get('DTSDKName', ''))
    require(sdk and int(sdk[1]) >= 26, 'Archive requires an iPhoneOS 26 or later SDK.')
    require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'A device archive is required.')
    require(bool(info.get('CFBundleIcons')), 'Compiled app icon is missing.')
    require(not info.get('NSAppTransportSecurity'), 'Archived app has unexpected ATS exceptions.')
    check_privacy(app / 'PrivacyInfo.xcprivacy')
    require((app / 'Assets.car').is_file(), 'Compiled asset catalog is missing.')
    executable = app / info['CFBundleExecutable']
    require('arm64' in run('lipo', '-archs', str(executable)).split(), 'Device arm64 binary is missing.')
    require((path / 'dSYMs/Grademaxxing.app.dSYM/Contents/Resources/DWARF/Grademaxxing').is_file(),
            'Release debug symbols are missing.')
    if not allow_unsigned:
        run('codesign', '--verify', '--deep', '--strict', str(app))
        signature = run('codesign', '--display', '--verbose=4', str(app))
        require(re.search(r'TeamIdentifier=[A-Z0-9]{10}\b', signature),
                'Archive needs a real signing team; an ad-hoc signature is insufficient.')
    print('PASS device archive configuration, SDK, privacy resources, icon, arm64 binary, debug symbols')
    print('Unsigned engineering archive only.' if allow_unsigned else
          'Signature verified. Distribution export/provisioning and App Store validation remain separate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--allow-unsigned', action='store_true', help='For CI engineering archives only')
    args = parser.parse_args()
    require(not args.allow_unsigned or args.archive, '--allow-unsigned requires --archive.')
    release = source_checks()
    if args.archive:
        archive_checks(args.archive.resolve(), release, args.allow_unsigned)
    print('See RELEASE.md for remaining device, privacy, signing, and submission gates.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f'FAIL release preflight: {error}', file=sys.stderr)
        sys.exit(1)
