#!/usr/bin/env python3
"""Exercise packaging in an isolated Applications fixture, without touching an app."""

from pathlib import Path
from shlex import quote
import subprocess
import tempfile
import unittest


class BuildPackagingTests(unittest.TestCase):
    def run_packaging(self, *arguments, failure_mode=""):
        script = Path(__file__).with_name("build_and_run.sh").read_text()
        tail = script.split("\nsign_app_bundle\n", 1)[1]
        with tempfile.TemporaryDirectory(prefix="capturely packaging ") as temporary:
            root = Path(temporary)
            applications = root / "Applications"
            applications.mkdir()
            installed = applications / "Capturely.app"
            installed.mkdir()
            (installed / "version").write_text("old")
            stage = root / "signed-stage" / "Capturely.app"
            stage.mkdir(parents=True)
            (stage / "version").write_text("new")
            tail = tail.replace("/Applications/", str(applications) + "/")
            setup = f"""
APP_NAME=Capturely
STAGING_DIR={quote(str(stage.parent))}
APP_DIR={quote(str(stage))}
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
DIST_APP_DIR={quote(str(root / 'dist' / 'Capturely.app'))}
FAILURE_MODE={quote(failure_mode)}
"""
            stubs = r'''
set -euo pipefail
trap 'rm -rf "$STAGING_DIR"' EXIT
sign_app_bundle() { :; }
otool() { print -- '@executable_path/../Frameworks'; }
plutil() { :; }
test() { :; }
pkill() { print -- stop-running; }
open() { print -- "open:$argv[-1]"; }
ditto() {
  print -- "copy:$3:$4"
  [[ $FAILURE_MODE != copy || $4 == $DIST_APP_DIR ]] || return 1
  mkdir -p "${4:h}"
  cp -R "$3" "$4"
}
codesign() {
  local target=$argv[-1]
  if [[ $1 == --verify ]]; then
    print -- "verify:$target"
    [[ -d $target && $target != $DIST_APP_DIR ]] || return 1
    [[ $FAILURE_MODE != stage || $target != $APP_DIR ]] || return 1
    [[ $FAILURE_MODE != signature || $target == $APP_DIR ]] || return 1
    [[ $FAILURE_MODE != post-signature || $target != ${INSTALLED_APP:-} ]] || return 1
  else
    print -- 'Identifier=com.italianseasoning.capturely'
  fi
}
mv() {
  if [[ $1 == */.Capturely-install.*/Capturely.app ]]; then
    [[ $FAILURE_MODE != interrupt ]] || { kill -TERM $$; return 143; }
    [[ $FAILURE_MODE != rename && $FAILURE_MODE != rollback ]] || return 1
  fi
  [[ $FAILURE_MODE != rollback || $1 != */previous.app ]] || return 1
  command mv "$@"
}
'''
            result = subprocess.run(
                ["zsh", "-c", setup + stubs + tail, "packaging-self-check", *arguments],
                text=True, capture_output=True, check=False, timeout=10,
            )
            marker = installed / "version"
            snapshot = {
                "installed": marker.read_text() if marker.exists() else None,
                "backups": [p.read_text() for p in applications.glob(".Capturely-install.*/previous.app/version")],
                "staging_count": len(list(applications.glob(".Capturely-install.*"))),
            }
            return result, snapshot

    def test_verify_only_does_not_replace_or_stop_the_installed_app(self):
        result, snapshot = self.run_packaging("--verify")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(snapshot["installed"], "old")
        self.assertEqual(snapshot["staging_count"], 0)
        self.assertNotIn("stop-running", result.stdout)
        self.assertNotIn("open:", result.stdout)

    def test_successful_replacement_cleans_the_backup(self):
        result, snapshot = self.run_packaging()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(snapshot["installed"], "new")
        self.assertEqual(snapshot["staging_count"], 0)
        self.assertIn("open:", result.stdout)

    def test_candidate_and_rename_failures_preserve_the_previous_app(self):
        for mode in ["copy", "signature", "rename", "interrupt", "post-signature"]:
            with self.subTest(mode=mode):
                result, snapshot = self.run_packaging(failure_mode=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(snapshot["installed"], "old", result.stdout + result.stderr)
                self.assertEqual(snapshot["staging_count"], 0)
                self.assertNotIn("open:", result.stdout)
                if mode in ["copy", "signature"]:
                    self.assertNotIn("stop-running", result.stdout)

    def test_failed_rollback_keeps_the_recoverable_backup(self):
        result, snapshot = self.run_packaging(failure_mode="rollback")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(snapshot["backups"], ["old"], result.stdout + result.stderr)
        self.assertEqual(snapshot["staging_count"], 1)
        self.assertIn("previous app retained", result.stderr)
        self.assertNotIn("open:", result.stdout)

    def test_invalid_staging_signature_stops_before_copying(self):
        result, snapshot = self.run_packaging("--verify", failure_mode="stage")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(snapshot["installed"], "old")
        self.assertNotIn("copy:", result.stdout)


if __name__ == "__main__":
    unittest.main()
