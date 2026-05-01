#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "MusicGlass.xcodeproj" / "project.pbxproj"


def oid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest().upper()[:24]


def q(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    if all(c.isalnum() or c in "._/$-" for c in escaped):
        return escaped
    return f'"{escaped}"'


def isa_file_type(path: Path) -> str:
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.suffix == ".plist":
        return "text.plist.xml"
    return "text"


def build_configuration(config_id: str, name: str, settings: dict[str, str]) -> str:
    lines = [
        f"\t\t{config_id} = {{",
        "\t\t\tisa = XCBuildConfiguration;",
        f"\t\t\tbuildSettings = {{",
    ]
    for key, value in settings.items():
        lines.append(f"\t\t\t\t{key} = {value};")
    lines.extend([
        "\t\t\t};",
        f"\t\t\tname = {name};",
        "\t\t};",
    ])
    return "\n".join(lines)


def configuration_list(list_id: str, debug_id: str, release_id: str, default_name: str = "Release") -> str:
    return "\n".join([
        f"\t\t{list_id} = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{debug_id},",
        f"\t\t\t\t{release_id},",
        "\t\t\t);",
        f"\t\t\tdefaultConfigurationName = {default_name};",
        "\t\t};",
    ])


def main() -> None:
    app_sources = sorted((ROOT / "MusicGlass").rglob("*.swift"))
    test_sources = sorted((ROOT / "MusicGlassTests").rglob("*.swift"))
    app_file_refs = {path: oid(f"fileref:{path.relative_to(ROOT)}") for path in app_sources}
    test_file_refs = {path: oid(f"fileref:{path.relative_to(ROOT)}") for path in test_sources}
    app_build_files = {path: oid(f"buildfile:{path.relative_to(ROOT)}") for path in app_sources}
    test_build_files = {path: oid(f"buildfile:{path.relative_to(ROOT)}") for path in test_sources}

    info_plist = ROOT / "MusicGlass" / "Info.plist"
    info_ref = oid("fileref:MusicGlass/Info.plist")

    ids = {
        "project": oid("project"),
        "main_group": oid("group:main"),
        "app_group": oid("group:MusicGlass"),
        "tests_group": oid("group:MusicGlassTests"),
        "products_group": oid("group:Products"),
        "app_target": oid("target:MusicGlass"),
        "tests_target": oid("target:MusicGlassTests"),
        "app_product": oid("product:MusicGlass.app"),
        "tests_product": oid("product:MusicGlassTests.xctest"),
        "app_sources": oid("phase:app:sources"),
        "app_resources": oid("phase:app:resources"),
        "app_frameworks": oid("phase:app:frameworks"),
        "tests_sources": oid("phase:tests:sources"),
        "tests_resources": oid("phase:tests:resources"),
        "tests_frameworks": oid("phase:tests:frameworks"),
        "dependency": oid("dependency:tests-app"),
        "proxy": oid("proxy:tests-app"),
        "project_config_list": oid("configlist:project"),
        "app_config_list": oid("configlist:app"),
        "tests_config_list": oid("configlist:tests"),
        "project_debug": oid("config:project:debug"),
        "project_release": oid("config:project:release"),
        "app_debug": oid("config:app:debug"),
        "app_release": oid("config:app:release"),
        "tests_debug": oid("config:tests:debug"),
        "tests_release": oid("config:tests:release"),
    }

    objects: list[str] = []

    # Build files
    for path, build_id in {**app_build_files, **test_build_files}.items():
        ref_id = app_file_refs.get(path) or test_file_refs[path]
        objects.append("\n".join([
            f"\t\t{build_id} = {{",
            "\t\t\tisa = PBXBuildFile;",
            f"\t\t\tfileRef = {ref_id};",
            "\t\t};",
        ]))

    # File refs
    for path, ref_id in {**app_file_refs, **test_file_refs}.items():
        rel = path.relative_to(ROOT)
        objects.append("\n".join([
            f"\t\t{ref_id} = {{",
            "\t\t\tisa = PBXFileReference;",
            f"\t\t\tlastKnownFileType = {isa_file_type(path)};",
            f"\t\t\tpath = {q(str(rel))};",
            "\t\t\tsourceTree = SOURCE_ROOT;",
            "\t\t};",
        ]))
    objects.append("\n".join([
        f"\t\t{info_ref} = {{",
        "\t\t\tisa = PBXFileReference;",
        "\t\t\tlastKnownFileType = text.plist.xml;",
        "\t\t\tpath = MusicGlass/Info.plist;",
        "\t\t\tsourceTree = SOURCE_ROOT;",
        "\t\t};",
    ]))
    objects.append("\n".join([
        f"\t\t{ids['app_product']} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MusicGlass.app; sourceTree = BUILT_PRODUCTS_DIR; }};",
        f"\t\t{ids['tests_product']} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MusicGlassTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};",
    ]))

    # Groups
    objects.append("\n".join([
        f"\t\t{ids['main_group']} = {{",
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        f"\t\t\t\t{ids['app_group']},",
        f"\t\t\t\t{ids['tests_group']},",
        f"\t\t\t\t{ids['products_group']},",
        "\t\t\t);",
        "\t\t\tsourceTree = \"<group>\";",
        "\t\t};",
    ]))
    objects.append("\n".join([
        f"\t\t{ids['app_group']} = {{",
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        f"\t\t\t\t{info_ref},",
        *[f"\t\t\t\t{ref}," for ref in app_file_refs.values()],
        "\t\t\t);",
        "\t\t\tpath = MusicGlass;",
        "\t\t\tsourceTree = \"<group>\";",
        "\t\t};",
    ]))
    objects.append("\n".join([
        f"\t\t{ids['tests_group']} = {{",
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        *[f"\t\t\t\t{ref}," for ref in test_file_refs.values()],
        "\t\t\t);",
        "\t\t\tpath = MusicGlassTests;",
        "\t\t\tsourceTree = \"<group>\";",
        "\t\t};",
    ]))
    objects.append("\n".join([
        f"\t\t{ids['products_group']} = {{",
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        f"\t\t\t\t{ids['app_product']},",
        f"\t\t\t\t{ids['tests_product']},",
        "\t\t\t);",
        "\t\t\tname = Products;",
        "\t\t\tsourceTree = \"<group>\";",
        "\t\t};",
    ]))

    # Phases
    def phase(phase_id: str, isa: str, files: list[str]) -> str:
        return "\n".join([
            f"\t\t{phase_id} = {{",
            f"\t\t\tisa = {isa};",
            "\t\t\tbuildActionMask = 2147483647;",
            "\t\t\tfiles = (",
            *[f"\t\t\t\t{file_id}," for file_id in files],
            "\t\t\t);",
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
            "\t\t};",
        ])

    objects.extend([
        phase(ids["app_sources"], "PBXSourcesBuildPhase", list(app_build_files.values())),
        phase(ids["app_resources"], "PBXResourcesBuildPhase", []),
        phase(ids["app_frameworks"], "PBXFrameworksBuildPhase", []),
        phase(ids["tests_sources"], "PBXSourcesBuildPhase", list(test_build_files.values())),
        phase(ids["tests_resources"], "PBXResourcesBuildPhase", []),
        phase(ids["tests_frameworks"], "PBXFrameworksBuildPhase", []),
    ])

    # Dependency
    objects.append("\n".join([
        f"\t\t{ids['proxy']} = {{",
        "\t\t\tisa = PBXContainerItemProxy;",
        "\t\t\tcontainerPortal = " + ids["project"] + ";",
        "\t\t\tproxyType = 1;",
        "\t\t\tremoteGlobalIDString = " + ids["app_target"] + ";",
        "\t\t\tremoteInfo = MusicGlass;",
        "\t\t};",
        f"\t\t{ids['dependency']} = {{",
        "\t\t\tisa = PBXTargetDependency;",
        "\t\t\ttarget = " + ids["app_target"] + ";",
        "\t\t\ttargetProxy = " + ids["proxy"] + ";",
        "\t\t};",
    ]))

    # Targets
    objects.append("\n".join([
        f"\t\t{ids['app_target']} = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {ids['app_config_list']};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{ids['app_sources']},",
        f"\t\t\t\t{ids['app_frameworks']},",
        f"\t\t\t\t{ids['app_resources']},",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        "\t\t\tdependencies = ();",
        "\t\t\tname = MusicGlass;",
        "\t\t\tproductName = MusicGlass;",
        f"\t\t\tproductReference = {ids['app_product']};",
        "\t\t\tproductType = \"com.apple.product-type.application\";",
        "\t\t};",
    ]))
    objects.append("\n".join([
        f"\t\t{ids['tests_target']} = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {ids['tests_config_list']};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{ids['tests_sources']},",
        f"\t\t\t\t{ids['tests_frameworks']},",
        f"\t\t\t\t{ids['tests_resources']},",
        "\t\t\t);",
        "\t\t\tbuildRules = ();",
        "\t\t\tdependencies = (",
        f"\t\t\t\t{ids['dependency']},",
        "\t\t\t);",
        "\t\t\tname = MusicGlassTests;",
        "\t\t\tproductName = MusicGlassTests;",
        f"\t\t\tproductReference = {ids['tests_product']};",
        "\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";",
        "\t\t};",
    ]))

    # Project
    objects.append("\n".join([
        f"\t\t{ids['project']} = {{",
        "\t\t\tisa = PBXProject;",
        "\t\t\tattributes = {",
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
        "\t\t\t\tLastSwiftUpdateCheck = 2640;",
        "\t\t\t\tLastUpgradeCheck = 2640;",
        "\t\t\t\tTargetAttributes = {",
        f"\t\t\t\t\t{ids['app_target']} = {{ CreatedOnToolsVersion = 26.4.1; }};",
        f"\t\t\t\t\t{ids['tests_target']} = {{ CreatedOnToolsVersion = 26.4.1; TestTargetID = {ids['app_target']}; }};",
        "\t\t\t\t};",
        "\t\t\t};",
        f"\t\t\tbuildConfigurationList = {ids['project_config_list']};",
        "\t\t\tcompatibilityVersion = \"Xcode 15.0\";",
        "\t\t\tdevelopmentRegion = en;",
        "\t\t\thasScannedForEncodings = 0;",
        "\t\t\tknownRegions = (en, Base);",
        f"\t\t\tmainGroup = {ids['main_group']};",
        f"\t\t\tproductRefGroup = {ids['products_group']};",
        "\t\t\tprojectDirPath = \"\";",
        "\t\t\tprojectRoot = \"\";",
        "\t\t\ttargets = (",
        f"\t\t\t\t{ids['app_target']},",
        f"\t\t\t\t{ids['tests_target']},",
        "\t\t\t);",
        "\t\t};",
    ]))

    project_debug = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": "\"DEBUG=1 $(inherited)\"",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    }
    project_release = dict(project_debug)
    project_release.update({
        "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"",
        "ENABLE_TESTABILITY": "NO",
        "GCC_OPTIMIZATION_LEVEL": "s",
        "GCC_PREPROCESSOR_DEFINITIONS": "\"$(inherited)\"",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "ONLY_ACTIVE_ARCH": "NO",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"\"",
        "VALIDATE_PRODUCT": "YES",
    })
    app_settings = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "\"\"",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "MusicGlass/Info.plist",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.musicglass.app",
        "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
        "SUPPORTED_PLATFORMS": "\"iphoneos iphonesimulator\"",
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "\"1,2\"",
    }
    tests_settings = {
        "BUNDLE_LOADER": "\"$(TEST_HOST)\"",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "\"\"",
        "GENERATE_INFOPLIST_FILE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.musicglass.tests",
        "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
        "SUPPORTED_PLATFORMS": "\"iphoneos iphonesimulator\"",
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "\"1,2\"",
        "TEST_HOST": "\"$(BUILT_PRODUCTS_DIR)/MusicGlass.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MusicGlass\"",
    }
    objects.extend([
        build_configuration(ids["project_debug"], "Debug", project_debug),
        build_configuration(ids["project_release"], "Release", project_release),
        build_configuration(ids["app_debug"], "Debug", app_settings),
        build_configuration(ids["app_release"], "Release", app_settings),
        build_configuration(ids["tests_debug"], "Debug", tests_settings),
        build_configuration(ids["tests_release"], "Release", tests_settings),
        configuration_list(ids["project_config_list"], ids["project_debug"], ids["project_release"]),
        configuration_list(ids["app_config_list"], ids["app_debug"], ids["app_release"]),
        configuration_list(ids["tests_config_list"], ids["tests_debug"], ids["tests_release"]),
    ])

    content = "\n".join([
        "// !$*UTF8*$!",
        "{",
        "\tarchiveVersion = 1;",
        "\tclasses = {};",
        "\tobjectVersion = 60;",
        "\tobjects = {",
        *objects,
        "\t};",
        f"\trootObject = {ids['project']};",
        "}",
        "",
    ])
    PROJECT.write_text(content)


if __name__ == "__main__":
    main()
