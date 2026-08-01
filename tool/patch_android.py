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

import os
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


DESUGAR_MARKER = "desugar_jdk_libs"
DESUGAR_LIB_COORDINATE = "com.android.tools:desugar_jdk_libs:2.1.4"


def patch_core_library_desugaring():
    """
    mobile_scanner (CameraX/ML Kit) MEWAJIBKAN core library desugaring
    diaktifkan di android/app/build.gradle(.kts). Tanpa ini, Gradle akan
    gagal dengan error:
        "Dependency ':mobile_scanner' requires core library desugaring
         to be enabled for :app."
    Ini SERING jadi penyebab `flutter build apk --release` gagal padahal
    tidak ada perubahan kode - karena versi Flutter/AGP baru menegakkan
    aturan ini lebih ketat. Fungsi ini idempotent.
    """
    if GRADLE_KTS_PATH.exists():
        path = GRADLE_KTS_PATH
        content = path.read_text(encoding="utf-8")
        if DESUGAR_MARKER in content:
            print("[SKIP] Core library desugaring sudah dipatch (kts).")
            return

        # 1. Aktifkan flag di dalam blok compileOptions.
        if re.search(r"compileOptions\s*\{", content):
            content = re.sub(
                r"(compileOptions\s*\{)",
                r"\1\n        isCoreLibraryDesugaringEnabled = true",
                content,
                count=1,
            )
        elif re.search(r"\bandroid\s*\{", content):
            content = re.sub(
                r"(android\s*\{)",
                r"\1\n    compileOptions {\n"
                r"        isCoreLibraryDesugaringEnabled = true\n"
                r"        sourceCompatibility = JavaVersion.VERSION_11\n"
                r"        targetCompatibility = JavaVersion.VERSION_11\n"
                r"    }\n",
                content,
                count=1,
            )
        else:
            print("[WARN] Tidak menemukan blok android{} di build.gradle.kts, lewati desugaring.")
            return

        # 2. Tambahkan dependency desugar_jdk_libs ke blok dependencies top-level.
        dep_line = f'    coreLibraryDesugaring("{DESUGAR_LIB_COORDINATE}")\n'
        matches = list(re.finditer(r"dependencies\s*\{", content))
        if matches:
            last = matches[-1]
            insert_at = last.end()
            content = content[:insert_at] + "\n" + dep_line + content[insert_at:]
        else:
            content += f'\ndependencies {{\n{dep_line}}}\n'

        path.write_text(content, encoding="utf-8")
        print(f"[OK] Core library desugaring diaktifkan di {path}")

    elif GRADLE_GROOVY_PATH.exists():
        path = GRADLE_GROOVY_PATH
        content = path.read_text(encoding="utf-8")
        if DESUGAR_MARKER in content:
            print("[SKIP] Core library desugaring sudah dipatch (groovy).")
            return

        if re.search(r"compileOptions\s*\{", content):
            content = re.sub(
                r"(compileOptions\s*\{)",
                r"\1\n        coreLibraryDesugaringEnabled true",
                content,
                count=1,
            )
        elif re.search(r"\bandroid\s*\{", content):
            content = re.sub(
                r"(android\s*\{)",
                r"\1\n    compileOptions {\n"
                r"        coreLibraryDesugaringEnabled true\n"
                r"        sourceCompatibility JavaVersion.VERSION_11\n"
                r"        targetCompatibility JavaVersion.VERSION_11\n"
                r"    }\n",
                content,
                count=1,
            )
        else:
            print("[WARN] Tidak menemukan blok android{} di build.gradle, lewati desugaring.")
            return

        dep_line = f"    coreLibraryDesugaring '{DESUGAR_LIB_COORDINATE}'\n"
        matches = list(re.finditer(r"dependencies\s*\{", content))
        if matches:
            last = matches[-1]
            insert_at = last.end()
            content = content[:insert_at] + "\n" + dep_line + content[insert_at:]
        else:
            content += f"\ndependencies {{\n{dep_line}}}\n"

        path.write_text(content, encoding="utf-8")
        print(f"[OK] Core library desugaring diaktifkan di {path}")

    else:
        print("[ERROR] build.gradle / build.gradle.kts (app) tidak ditemukan untuk desugaring.")
        sys.exit(1)


ROOT_GRADLE_KTS_PATH = ROOT / "android" / "build.gradle.kts"
ROOT_GRADLE_GROOVY_PATH = ROOT / "android" / "build.gradle"

LEGACY_MIN_COMPILE_SDK = 36
COMPILE_SDK_FIX_MARKER = "compilesdk-fix-for-legacy-plugins"

COMPILE_SDK_FIX_KTS_BLOCK = f"""
// === {COMPILE_SDK_FIX_MARKER} ===
// blue_thermal_printer (dan plugin pub.dev lama sejenis) meng-hardcode
// compileSdkVersion rendah (mis. 31) di build.gradle mereka sendiri.
// AndroidX versi baru yang ikut ter-bundle sebagai dependency transitif
// (androidx.fragment, androidx.window, androidx.lifecycle, dst) mewajibkan
// modul yang memakainya di-compile terhadap API >= 34. Karena kita tidak
// bisa mengedit source plugin pihak ketiga secara langsung, blok ini
// memaksa compileSdk semua modul Android library yang MASIH DI BAWAH
// {LEGACY_MIN_COMPILE_SDK} supaya dinaikkan otomatis - mencegah error
// "checkReleaseAarMetadata ... requires libraries and applications that
// depend on it to compile against version 34 or later".
subprojects {{
    val proj = this
    val applyCompileSdkFix: () -> Unit = {{
        proj.extensions.findByType(LibraryExtension::class.java)?.let {{ ext ->
            val current = ext.compileSdk
            if (current == null || current < {LEGACY_MIN_COMPILE_SDK}) {{
                ext.compileSdk = {LEGACY_MIN_COMPILE_SDK}
            }}
        }}
    }}
    if (proj.state.executed) {{
        applyCompileSdkFix()
    }} else {{
        proj.afterEvaluate {{ applyCompileSdkFix() }}
    }}
}}
"""

COMPILE_SDK_FIX_GROOVY_BLOCK = f"""
// === {COMPILE_SDK_FIX_MARKER} ===
// blue_thermal_printer (dan plugin pub.dev lama sejenis) meng-hardcode
// compileSdkVersion rendah (mis. 31) di build.gradle mereka sendiri.
// AndroidX versi baru yang ikut ter-bundle sebagai dependency transitif
// (androidx.fragment, androidx.window, androidx.lifecycle, dst) mewajibkan
// modul yang memakainya di-compile terhadap API >= 34. Blok ini memaksa
// compileSdk semua modul Android library yang MASIH DI BAWAH
// {LEGACY_MIN_COMPILE_SDK} supaya dinaikkan otomatis - mencegah error
// "checkReleaseAarMetadata ... requires libraries and applications that
// depend on it to compile against version 34 or later".
subprojects {{ proj ->
    def applyCompileSdkFix = {{
        if (proj.hasProperty('android')) {{
            def androidExt = proj.android
            if (androidExt.hasProperty('compileSdkVersion')) {{
                def current = androidExt.compileSdkVersion
                def currentNum = (current instanceof String) ? current.replaceAll('[^0-9]', '') : current
                if (currentNum == null || currentNum.toString().isEmpty() || (currentNum as Integer) < {LEGACY_MIN_COMPILE_SDK}) {{
                    androidExt.compileSdkVersion {LEGACY_MIN_COMPILE_SDK}
                }}
            }}
        }}
    }}
    if (proj.state.executed) {{
        applyCompileSdkFix()
    }} else {{
        proj.afterEvaluate {{ applyCompileSdkFix() }}
    }}
}}
"""


def patch_subprojects_compile_sdk():
    if ROOT_GRADLE_KTS_PATH.exists():
        path = ROOT_GRADLE_KTS_PATH
        content = path.read_text(encoding="utf-8")
        if COMPILE_SDK_FIX_MARKER in content:
            print("[SKIP] compileSdk-fix sudah pernah dipatch di build.gradle.kts.")
            return
        if "import com.android.build.gradle.LibraryExtension" not in content:
            content = NAMESPACE_FIX_KTS_IMPORT + content
        content = content + "\n" + COMPILE_SDK_FIX_KTS_BLOCK
        path.write_text(content, encoding="utf-8")
        print(f"[OK] compileSdk-fix ditambahkan ke {path}")

    elif ROOT_GRADLE_GROOVY_PATH.exists():
        path = ROOT_GRADLE_GROOVY_PATH
        content = path.read_text(encoding="utf-8")
        if COMPILE_SDK_FIX_MARKER in content:
            print("[SKIP] compileSdk-fix sudah pernah dipatch di build.gradle.")
            return
        content = content + "\n" + COMPILE_SDK_FIX_GROOVY_BLOCK
        path.write_text(content, encoding="utf-8")
        print(f"[OK] compileSdk-fix ditambahkan ke {path}")

    else:
        print("[ERROR] android/build.gradle(.kts) root tidak ditemukan untuk compileSdk-fix.")
        sys.exit(1)


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
    val proj = this
    val applyNamespaceFix: () -> Unit = {
        proj.extensions.findByType(LibraryExtension::class.java)?.let { ext ->
            if (ext.namespace == null) {
                ext.namespace = "com.tokoanda.legacyfix." + proj.name.replace("-", "_")
            }
        }
    }
    if (proj.state.executed) {
        // Project sudah selesai dievaluasi lebih dulu (tergantung urutan
        // konfigurasi Gradle) - afterEvaluate tidak bisa dipanggil lagi,
        // jadi jalankan fix-nya langsung.
        applyNamespaceFix()
    } else {
        proj.afterEvaluate { applyNamespaceFix() }
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
subprojects { proj ->
    def applyNamespaceFix = {
        if (proj.hasProperty('android')) {
            def androidExt = proj.android
            if (androidExt.hasProperty('namespace') && androidExt.namespace == null) {
                androidExt.namespace = "com.tokoanda.legacyfix." + proj.name.replace('-', '_')
            }
        }
    }
    if (proj.state.executed) {
        // Project sudah selesai dievaluasi lebih dulu (tergantung urutan
        // konfigurasi Gradle) - afterEvaluate tidak bisa dipanggil lagi,
        // jadi jalankan fix-nya langsung.
        applyNamespaceFix()
    } else {
        proj.afterEvaluate { applyNamespaceFix() }
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


def strip_legacy_package_attr_from_pub_cache():
    """
    Beberapa plugin pub.dev lama (mis. blue_thermal_printer) masih punya
    atribut `package="..."` di AndroidManifest.xml mereka sendiri - cara
    lama untuk mendeklarasikan namespace yang SUDAH TIDAK DIDUKUNG SAMA
    SEKALI oleh Android Gradle Plugin versi baru ("no longer supported").
    Fungsi ini mencari semua AndroidManifest.xml milik package pihak
    ketiga di pub-cache dan menghapus atribut tsb (namespace tetap
    diisi lewat jalur resmi Gradle oleh patch_root_namespace_fix()).
    """
    pub_cache_env = os.environ.get("PUB_CACHE")
    candidates = []
    if pub_cache_env:
        candidates.append(Path(pub_cache_env))
    candidates.append(Path.home() / ".pub-cache")

    pub_cache_dir = next((p for p in candidates if p.exists()), None)
    if pub_cache_dir is None:
        print("[WARN] Folder pub-cache tidak ditemukan, lewati strip package attr "
              "(mungkin belum pernah `flutter pub get`).")
        return

    hosted_dir = pub_cache_dir / "hosted" / "pub.dev"
    if not hosted_dir.exists():
        print(f"[WARN] {hosted_dir} tidak ditemukan, lewati strip package attr.")
        return

    pattern = re.compile(r'\s+package\s*=\s*"[^"]*"')
    pattern_sq = re.compile(r"\s+package\s*=\s*'[^']*'")

    changed_files = 0
    for manifest_file in hosted_dir.glob("*/android/src/main/AndroidManifest.xml"):
        content = manifest_file.read_text(encoding="utf-8")
        new_content = pattern.sub("", content)
        new_content = pattern_sq.sub("", new_content)
        if new_content != content:
            manifest_file.write_text(new_content, encoding="utf-8")
            changed_files += 1
            print(f"[OK] Atribut package= dihapus dari {manifest_file}")

    if changed_files == 0:
        print("[SKIP] Tidak ada AndroidManifest.xml package pihak ketiga yang "
              "perlu di-strip (sudah bersih / tidak ditemukan).")
    else:
        print(f"[OK] Total {changed_files} file AndroidManifest.xml package "
              "pihak ketiga sudah dipatch.")


if __name__ == "__main__":
    patch_manifest()
    patch_gradle_min_sdk(21)
    patch_core_library_desugaring()
    patch_root_namespace_fix()
    patch_subprojects_compile_sdk()
    strip_legacy_package_attr_from_pub_cache()
    print("Selesai patch android/.")
