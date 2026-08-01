#!/usr/bin/env python3
"""
Patch otomatis folder android/ hasil `flutter create .` supaya:
1. AndroidManifest.xml berisi permission Kamera & Bluetooth yang dibutuhkan
   (mobile_scanner, blue_thermal_printer).
2. minSdkVersion di-set minimal 21 (dibutuhkan mobile_scanner / ML Kit),
   mendukung format build.gradle (Groovy) MAUPUN build.gradle.kts (Kotlin DSL)
   tergantung versi Flutter yang dipakai di runner GitHub Actions.

Script ini idempotent - aman dijalankan berkali-kali (tidak akan
menduplikasi permission jika sudah pernah dipatch sebelumnya).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
GRADLE_GROOVY_PATH = ROOT / "android" / "app" / "build.gradle"
GRADLE_KTS_PATH = ROOT / "android" / "app" / "build.gradle.kts"

PERMISSION_BLOCK = """
    <!-- === Ditambahkan otomatis oleh tool/patch_android.py === -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation"
        tools:targetApi="s" />
    <!-- === akhir blok otomatis === -->
"""

MARKER = "Ditambahkan otomatis oleh tool/patch_android.py"


def patch_manifest():
    if not MANIFEST_PATH.exists():
        print(f"[ERROR] Tidak ditemukan: {MANIFEST_PATH}")
        sys.exit(1)

    content = MANIFEST_PATH.read_text(encoding="utf-8")

    if MARKER in content:
        print("[SKIP] AndroidManifest.xml sudah pernah dipatch sebelumnya.")
        return

    # Pastikan xmlns:tools ada di tag <manifest ...>
    if "xmlns:tools=" not in content:
        content = re.sub(
            r"(<manifest\b[^>]*)(>)",
            r'\1 xmlns:tools="http://schemas.android.com/tools"\2',
            content,
            count=1,
        )

    # Sisipkan blok permission tepat setelah tag pembuka <manifest ...>
    content = re.sub(
        r"(<manifest\b[^>]*>)",
        r"\1" + PERMISSION_BLOCK,
        content,
        count=1,
    )

    MANIFEST_PATH.write_text(content, encoding="utf-8")
    print(f"[OK] Permission ditambahkan ke {MANIFEST_PATH}")


def patch_gradle_min_sdk(min_sdk: int = 21):
    if GRADLE_KTS_PATH.exists():
        path = GRADLE_KTS_PATH
        content = path.read_text(encoding="utf-8")

        if re.search(r"minSdk\s*=\s*\d+", content):
            new_content = re.sub(
                r"minSdk\s*=\s*\d+", f"minSdk = {min_sdk}", content
            )
        elif "flutter.minSdkVersion" in content:
            new_content = content.replace(
                "minSdk = flutter.minSdkVersion",
                f"minSdk = {min_sdk}",
            )
        else:
            print("[WARN] Pola minSdk tidak ditemukan di build.gradle.kts, "
                  "cek manual jika build gagal karena minSdkVersion.")
            return

        if new_content != content:
            path.write_text(new_content, encoding="utf-8")
            print(f"[OK] minSdk diset ke {min_sdk} di {path}")
        else:
            print("[SKIP] minSdk sudah sesuai / tidak perlu diubah.")

    elif GRADLE_GROOVY_PATH.exists():
        path = GRADLE_GROOVY_PATH
        content = path.read_text(encoding="utf-8")

        if re.search(r"minSdkVersion\s+\d+", content):
            new_content = re.sub(
                r"minSdkVersion\s+\d+", f"minSdkVersion {min_sdk}", content
            )
        elif "minSdkVersion flutter.minSdkVersion" in content:
            new_content = content.replace(
                "minSdkVersion flutter.minSdkVersion",
                f"minSdkVersion {min_sdk}",
            )
        else:
            print("[WARN] Pola minSdkVersion tidak ditemukan di build.gradle, "
                  "cek manual jika build gagal karena minSdkVersion.")
            return

        if new_content != content:
            path.write_text(new_content, encoding="utf-8")
            print(f"[OK] minSdkVersion diset ke {min_sdk} di {path}")
        else:
            print("[SKIP] minSdkVersion sudah sesuai / tidak perlu diubah.")
    else:
        print("[ERROR] build.gradle / build.gradle.kts tidak ditemukan.")
        sys.exit(1)


ROOT_GRADLE_KTS_PATH = ROOT / "android" / "build.gradle.kts"
ROOT_GRADLE_GROOVY_PATH = ROOT / "android" / "build.gradle"

NAMESPACE_FIX_MARKER = "namespace-fix-for-legacy-plugins"

NAMESPACE_FIX_KTS_IMPORT = "import com.android.build.gradle.LibraryExtension\n"

NAMESPACE_FIX_KTS_BLOCK = """
// === namespace-fix-for-legacy-plugins ===
// Beberapa plugin pub.dev lama (mis. blue_thermal_printer) belum menambahkan
// `namespace` di build.gradle mereka, padahal AGP 8+ mewajibkannya. Blok ini
// otomatis mengisi namespace fallback untuk SEMUA modul Android library yang
// belum mendeklarasikannya, supaya build tidak gagal karena plugin lama yang
// sudah tidak di-maintain.
subprojects {
    afterEvaluate {
        extensions.findByType(LibraryExtension::class.java)?.let { ext ->
            if (ext.namespace == null) {
                ext.namespace = "com.tokoanda.legacyfix." + project.name.replace("-", "_")
            }
        }
    }
}
"""

NAMESPACE_FIX_GROOVY_BLOCK = """
// === namespace-fix-for-legacy-plugins ===
// Beberapa plugin pub.dev lama (mis. blue_thermal_printer) belum menambahkan
// `namespace` di build.gradle mereka, padahal AGP 8+ mewajibkannya. Blok ini
// otomatis mengisi namespace fallback untuk SEMUA modul Android library yang
// belum mendeklarasikannya, supaya build tidak gagal karena plugin lama yang
// sudah tidak di-maintain.
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty('android')) {
            def androidExt = project.android
            if (androidExt.hasProperty('namespace') && androidExt.namespace == null) {
                androidExt.namespace = "com.tokoanda.legacyfix." + project.name.replace('-', '_')
            }
        }
    }
}
"""


def patch_root_namespace_fix():
    if ROOT_GRADLE_KTS_PATH.exists():
        path = ROOT_GRADLE_KTS_PATH
        content = path.read_text(encoding="utf-8")
        if NAMESPACE_FIX_MARKER in content:
            print("[SKIP] Namespace-fix sudah pernah dipatch di build.gradle.kts.")
            return
        if "import com.android.build.gradle.LibraryExtension" not in content:
            content = NAMESPACE_FIX_KTS_IMPORT + content
        content = content + "\n" + NAMESPACE_FIX_KTS_BLOCK
        path.write_text(content, encoding="utf-8")
        print(f"[OK] Namespace-fix ditambahkan ke {path}")

    elif ROOT_GRADLE_GROOVY_PATH.exists():
        path = ROOT_GRADLE_GROOVY_PATH
        content = path.read_text(encoding="utf-8")
        if NAMESPACE_FIX_MARKER in content:
            print("[SKIP] Namespace-fix sudah pernah dipatch di build.gradle.")
            return
        content = content + "\n" + NAMESPACE_FIX_GROOVY_BLOCK
        path.write_text(content, encoding="utf-8")
        print(f"[OK] Namespace-fix ditambahkan ke {path}")

    else:
        print("[ERROR] android/build.gradle(.kts) root tidak ditemukan untuk namespace-fix.")
        sys.exit(1)


if __name__ == "__main__":
    patch_manifest()
    patch_gradle_min_sdk(21)
    patch_root_namespace_fix()
    print("Selesai patch android/.")
