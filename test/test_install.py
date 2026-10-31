"""Tests for install.sh: serve fake releases locally (latest redirect, packages, SHA256SUMS) and check what install.sh installs.

    python3 -m unittest discover -s test
"""

import hashlib
import http.server
import io
import os
import platform
import subprocess
import tarfile
import tempfile
import threading
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "install.sh")


def host_target():
    os_name = {"Darwin": "darwin", "Linux": "linux"}[platform.system()]
    arch = {"x86_64": "amd64", "amd64": "amd64", "arm64": "arm64", "aarch64": "arm64"}[platform.machine()]
    return os_name, arch


def fake_package(version):
    """A fake kusa-connect that only answers --version, packed like a release."""
    body = f"#!/bin/sh\necho kusa-connect {version}\n".encode()
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        info = tarfile.TarInfo("kusa-connect")
        info.size, info.mode = len(body), 0o755
        tar.addfile(info, io.BytesIO(body))
    return buf.getvalue()


class Releases:
    """Fake GitHub Releases: /latest redirects to /tag/v<latest>; /download/v<version>/<file> serves files."""

    def __init__(self, latest, versions, corrupt=False):
        os_name, arch = host_target()
        self.files = {}
        for v in versions:
            name = f"kusa-connect_{v}_{os_name}_{arch}.tar.gz"
            pkg = fake_package(v)
            sums = f"{hashlib.sha256(pkg).hexdigest()}  {name}\n".encode()
            if corrupt:
                pkg = pkg + b"x"
            self.files[f"/releases/download/v{v}/{name}"] = pkg
            self.files[f"/releases/download/v{v}/SHA256SUMS"] = sums
        files = self.files

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_HEAD(self):
                self.do_GET(head=True)

            def do_GET(self, head=False):
                if self.path == "/releases/latest":
                    self.send_response(302)
                    self.send_header("Location", f"/releases/tag/v{latest}")
                    self.end_headers()
                    return
                if self.path.startswith("/releases/tag/"):
                    self.send_response(200)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                data = files.get(self.path)
                if data is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if not head:
                    self.wfile.write(data)

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/releases"

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class InstallTest(unittest.TestCase):
    def run_install(self, releases, **env):
        home = tempfile.mkdtemp()
        dest = os.path.join(home, "bin")
        e = {"PATH": os.environ["PATH"], "HOME": home, "KUSA_CONNECT_RELEASES": releases.url, "KUSA_CONNECT_INSTALL_DIR": dest}
        e.update(env)
        p = subprocess.run(["sh", SCRIPT], env=e, capture_output=True, text=True, timeout=60)
        return p, os.path.join(dest, "kusa-connect")

    def test_latest(self):
        r = Releases("0.2.0", ["0.1.0", "0.2.0"])
        self.addCleanup(r.close)
        p, binary = self.run_install(r)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("kusa-connect 0.2.0", p.stdout)
        self.assertIn("is not on your PATH", p.stdout)
        out = subprocess.run([binary, "--version"], capture_output=True, text=True).stdout
        self.assertEqual(out, "kusa-connect 0.2.0\n")
        self.assertEqual(os.stat(binary).st_mode & 0o777, 0o755)

    def test_utf8_locale(self):
        # Most terminals use a UTF-8 locale; macOS /bin/sh (bash 3.2) once read multibyte text right after $version as part of the name.
        for lang in ("zh_CN.UTF-8", "en_US.UTF-8"):
            with self.subTest(lang=lang):
                r = Releases("0.2.0", ["0.2.0"])
                self.addCleanup(r.close)
                p, binary = self.run_install(r, LANG=lang, LC_ALL=lang)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertIn("Downloading kusa-connect 0.2.0 (", p.stdout)

    def test_pinned_version(self):
        r = Releases("0.2.0", ["0.1.0", "0.2.0"])
        self.addCleanup(r.close)
        p, binary = self.run_install(r, KUSA_CONNECT_VERSION="v0.1.0")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("kusa-connect 0.1.0", p.stdout)

    def test_checksum_mismatch(self):
        r = Releases("0.2.0", ["0.2.0"], corrupt=True)
        self.addCleanup(r.close)
        p, binary = self.run_install(r)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("SHA256 mismatch", p.stderr)
        self.assertFalse(os.path.exists(binary))

    def test_missing_version(self):
        r = Releases("0.2.0", ["0.2.0"])
        self.addCleanup(r.close)
        p, binary = self.run_install(r, KUSA_CONNECT_VERSION="9.9.9")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("couldn't download kusa-connect_9.9.9_", p.stderr)
        self.assertFalse(os.path.exists(binary))


if __name__ == "__main__":
    unittest.main()
