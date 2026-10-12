#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generation for the native app."""
from pathlib import Path
import hashlib
import sys

root = Path(__file__).resolve().parents[1]


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


objects = []


def add(name, isa, fields):
    key = identifier(name)
    objects.append(f'\t\t{key} /* {name} */ = {{\n\t\t\tisa = {isa};\n{fields}\n\t\t}};')
    return key


def fields(**values):
    return '\n'.join(f'\t\t\t{key} = {value};' for key, value in values.items())


def array(values):
    return '(\n' + ''.join(f'\t\t\t\t{value},\n' for value in values) + '\t\t\t)'


def settings(values):
    return '{\n' + ''.join(f'\t\t\t\t{key} = {quote(value)};\n' for key, value in values.items()) + '\t\t\t}'


sources, resources, children = [], [], []
for path in sorted((root / 'App').glob('*.swift')):
    ref = add(path.name, 'PBXFileReference', fields(lastKnownFileType='sourcecode.swift', path=quote(path.name), sourceTree='"<group>"'))
    children.append(ref)
    sources.append(add(path.name + ' in Sources', 'PBXBuildFile', fields(fileRef=ref)))
for name, kind in [('Assets.xcassets', 'folder.assetcatalog'), ('PrivacyInfo.xcprivacy', 'text.xml'), ('Info.plist', 'text.plist.xml')]:
    ref = add(name, 'PBXFileReference', fields(lastKnownFileType=kind, path=quote(name), sourceTree='"<group>"'))
    children.append(ref)
    if name != 'Info.plist':
        resources.append(add(name + ' in Resources', 'PBXBuildFile', fields(fileRef=ref)))

app_group = add('App', 'PBXGroup', fields(children=array(children), path='App', sourceTree='"<group>"'))
test_sources, test_children = [], []
for path in sorted((root / 'UITests').glob('*.swift')):
    ref = add(path.name, 'PBXFileReference', fields(lastKnownFileType='sourcecode.swift', path=quote(path.name), sourceTree='"<group>"'))
    test_children.append(ref)
    test_sources.append(add(path.name + ' in UI Tests', 'PBXBuildFile', fields(fileRef=ref)))
test_group = add('UITests', 'PBXGroup', fields(children=array(test_children), path='UITests', sourceTree='"<group>"'))
product = add('Grademaxxing.app', 'PBXFileReference', fields(explicitFileType='wrapper.application', includeInIndex='0', path='Grademaxxing.app', sourceTree='BUILT_PRODUCTS_DIR'))
test_product = add('GrademaxxingUITests.xctest', 'PBXFileReference', fields(explicitFileType='wrapper.cfbundle', includeInIndex='0', path='GrademaxxingUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR'))
products = add('Products', 'PBXGroup', fields(children=array([product, test_product]), name='Products', sourceTree='"<group>"'))
main_group = add('Main group', 'PBXGroup', fields(children=array([app_group, test_group, products]), sourceTree='"<group>"'))

local_package = add('Local Swift package', 'XCLocalSwiftPackageReference', fields(relativePath='"."'))
package_product = add('GrademaxxingCore', 'XCSwiftPackageProductDependency', fields(package=local_package, productName='GrademaxxingCore'))
framework_file = add('GrademaxxingCore in Frameworks', 'PBXBuildFile', fields(productRef=package_product))
source_phase = add('Sources', 'PBXSourcesBuildPhase', fields(buildActionMask='2147483647', files=array(sources), runOnlyForDeploymentPostprocessing='0'))
resource_phase = add('Resources', 'PBXResourcesBuildPhase', fields(buildActionMask='2147483647', files=array(resources), runOnlyForDeploymentPostprocessing='0'))
framework_phase = add('Frameworks', 'PBXFrameworksBuildPhase', fields(buildActionMask='2147483647', files=array([framework_file]), runOnlyForDeploymentPostprocessing='0'))
test_source_phase = add('UI Test Sources', 'PBXSourcesBuildPhase', fields(buildActionMask='2147483647', files=array(test_sources), runOnlyForDeploymentPostprocessing='0'))
test_framework_phase = add('UI Test Frameworks', 'PBXFrameworksBuildPhase', fields(buildActionMask='2147483647', files='()', runOnlyForDeploymentPostprocessing='0'))

project_configs, app_configs, test_configs = [], [], []
for name in ['Debug', 'Release']:
    base = {
        'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '6.0',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O',
        'ONLY_ACTIVE_ARCH': 'YES' if name == 'Debug' else 'NO',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY': 'YES' if name == 'Debug' else 'NO',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG $(inherited)' if name == 'Debug' else '$(inherited)',
    }
    project_configs.append(add('Project ' + name, 'XCBuildConfiguration', fields(buildSettings=settings(base), name=name)))
    app = {
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
        'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '0.1.0',
        'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'App/Info.plist',
        'PRODUCT_BUNDLE_IDENTIFIER': 'app.grademaxxing.native', 'PRODUCT_NAME': '$(TARGET_NAME)',
        'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'TARGETED_DEVICE_FAMILY': '1',
        'SUPPORTS_MACCATALYST': 'NO', 'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ENABLE_PREVIEWS': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
    }
    app_configs.append(add('App ' + name, 'XCBuildConfiguration', fields(buildSettings=settings(app), name=name)))
    test_settings = {
        'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES',
        'PRODUCT_BUNDLE_IDENTIFIER': 'app.grademaxxing.native.uitests', 'PRODUCT_NAME': '$(TARGET_NAME)',
        'TEST_TARGET_NAME': 'Grademaxxing', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
        'TARGETED_DEVICE_FAMILY': '1', 'SWIFT_VERSION': '6.0',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
    }
    test_configs.append(add('UI Tests ' + name, 'XCBuildConfiguration', fields(buildSettings=settings(test_settings), name=name)))

project_config_list = add('Project configurations', 'XCConfigurationList', fields(buildConfigurations=array(project_configs), defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
app_config_list = add('App configurations', 'XCConfigurationList', fields(buildConfigurations=array(app_configs), defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
test_config_list = add('UI Test configurations', 'XCConfigurationList', fields(buildConfigurations=array(test_configs), defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
target = add('Grademaxxing', 'PBXNativeTarget', fields(buildConfigurationList=app_config_list, buildPhases=array([source_phase, framework_phase, resource_phase]), buildRules='()', dependencies='()', name='Grademaxxing', packageProductDependencies=array([package_product]), productName='Grademaxxing', productReference=product, productType='"com.apple.product-type.application"'))
test_proxy = add('UI Tests app proxy', 'PBXContainerItemProxy', fields(containerPortal=identifier('Project'), proxyType='1', remoteGlobalIDString=target, remoteInfo='Grademaxxing'))
test_dependency = add('UI Tests app dependency', 'PBXTargetDependency', fields(target=target, targetProxy=test_proxy))
test_target = add('GrademaxxingUITests', 'PBXNativeTarget', fields(buildConfigurationList=test_config_list, buildPhases=array([test_source_phase, test_framework_phase]), buildRules='()', dependencies=array([test_dependency]), name='GrademaxxingUITests', productName='GrademaxxingUITests', productReference=test_product, productType='"com.apple.product-type.bundle.ui-testing"'))
project = add('Project', 'PBXProject', fields(attributes='{ LastUpgradeCheck = 1600; BuildIndependentTargetsInParallel = YES; }', buildConfigurationList=project_config_list, compatibilityVersion='"Xcode 14.0"', developmentRegion='en', hasScannedForEncodings='0', knownRegions='(en, Base)', mainGroup=main_group, packageReferences=array([local_package]), productRefGroup=products, projectDirPath='""', projectRoot='""', targets=array([target, test_target])))

contents = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {project};\n}}\n'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Grademaxxing.app" BlueprintName="Grademaxxing" ReferencedContainer="container:Grademaxxing.xcodeproj"/>
    </BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="GrademaxxingUITests.xctest" BlueprintName="GrademaxxingUITests" ReferencedContainer="container:Grademaxxing.xcodeproj"/>
    </BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="GrademaxxingUITests.xctest" BlueprintName="GrademaxxingUITests" ReferencedContainer="container:Grademaxxing.xcodeproj"/></TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Grademaxxing.app" BlueprintName="Grademaxxing" ReferencedContainer="container:Grademaxxing.xcodeproj"/></BuildableProductRunnable>
    <CommandLineArguments><CommandLineArgument argument="--demo" isEnabled="YES"/></CommandLineArguments>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Grademaxxing.app" BlueprintName="Grademaxxing" ReferencedContainer="container:Grademaxxing.xcodeproj"/></BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''

outputs = {
    root / 'Grademaxxing.xcodeproj/project.pbxproj': contents,
    root / 'Grademaxxing.xcodeproj/xcshareddata/xcschemes/Grademaxxing.xcscheme': scheme,
}
for path, content in outputs.items():
    if '--check' in sys.argv:
        if not path.exists() or path.read_text() != content:
            raise SystemExit(f'Project needs regeneration: {path.name}')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
print('Xcode project matches native sources.' if '--check' in sys.argv else 'Generated Grademaxxing.xcodeproj and shared demo scheme.')
