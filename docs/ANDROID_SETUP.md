# Android build and update setup

The GitHub Actions workflow reads these repository Actions secrets:

- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEYSTORE_BASE64`

The workflow decodes the keystore only into the temporary runner directory, then supplies its path and credentials to Godot through documented Android export environment variables. No signing material belongs in the repository.

To add the secrets, open the repository's **Settings → Secrets and variables → Actions → New repository secret** and create each name above with its matching value.

Keep a secure offline backup of the signing key and passwords. Future APK builds need the same signing identity and Android package identifier to install as updates over earlier builds.

Start a build from **Actions → Android APK → Run workflow**. When it completes, download the `trajectory-works-apk` artifact from the run summary and install the APK on the Android device. The workflow run artifact is intended for testing; a GitHub Release can be added when we want a stable download page.
