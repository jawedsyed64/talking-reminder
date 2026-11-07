"""Run after `flutter create` in CI: raise minSdk to 26 and sign with the fixed key,
so every new build installs over the previous one without losing data."""
import pathlib
import sys

p = pathlib.Path("android/app/build.gradle.kts")
if not p.exists():
    sys.exit("android/app/build.gradle.kts was not generated")
s = p.read_text()

if "minSdk = flutter.minSdkVersion" in s:
    s = s.replace("minSdk = flutter.minSdkVersion", "minSdk = 26")
elif "minSdk = 26" not in s:
    sys.exit("could not find minSdk line:\n" + s)

if 'create("fixed")' not in s:
    block = '''    signingConfigs {
        create("fixed") {
            storeFile = file("upload.jks")
            storePassword = "talkingreminder"
            keyAlias = "talkingreminder"
            keyPassword = "talkingreminder"
        }
    }

    buildTypes {'''
    if "    buildTypes {" not in s:
        sys.exit("could not find buildTypes:\n" + s)
    s = s.replace("    buildTypes {", block, 1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("fixed")')

p.write_text(s)
print(s)
