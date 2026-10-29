"""Configure an isolated editor profile and an ARM64 Android debug export."""
from pathlib import Path
import subprocess, os, shutil

root = Path(__file__).resolve().parent.parent / 'MoonSweepers-Native-Rebuild'
tools = root / 'tools'
editor = tools / 'godot'
(editor / '_sc_').touch()
profile = editor / 'editor_data'; profile.mkdir(exist_ok=True)
keystore = tools / 'rebuild-debug.keystore'
java_exe = shutil.which('java')
jdk = Path(os.environ.get('JAVA_HOME') or (str(Path(java_exe).resolve().parent.parent) if java_exe else 'C:/Program Files/Java/jdk-17'))
sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or str(Path(os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local'))) / 'Android/Sdk'))
if not keystore.exists():
    subprocess.run([str(jdk / 'bin/keytool.exe'), '-genkeypair', '-keystore', str(keystore),
        '-alias', 'androiddebugkey', '-storepass', 'android', '-keypass', 'android',
        '-dname', 'CN=Local Android Rebuild,O=Local,C=IN', '-keyalg', 'RSA', '-keysize', '2048',
        '-validity', '10000'], check=True)
(profile / 'editor_settings-4.7.tres').write_text(f'''[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "{sdk.as_posix()}"
export/android/java_sdk_path = "{jdk.as_posix()}"
export/android/debug_keystore = "{keystore.as_posix()}"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
''')
(root / 'builds').mkdir(exist_ok=True)
(root / 'game/export_presets.cfg').write_text(f'''[preset.0]
name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.bin"
exclude_filter=""
export_path="../builds/MoonSweepers-Rebuild-arm64.apk"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]
custom_template/debug="{(tools / 'templates/android_debug.apk').as_posix()}"
custom_template/release=""
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=5
version/name="0.3.2-world"
package/unique_name="org.local.moonsweepers.rebuild"
package/name="Moon Sweepers"
package/signed=true
package/retain_data_on_uninstall=false
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_data_backup/allow=false
permissions/internet=false
''')
print('Configured isolated Godot editor profile and ARM64 export preset.')
