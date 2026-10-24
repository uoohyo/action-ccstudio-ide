import subprocess
import tempfile
import unittest
from pathlib import Path

ENTRYPOINT = Path(__file__).resolve().parents[1] / 'entrypoint.sh'


class ExitStatusTests(unittest.TestCase):
    def test_build_pipeline_preserves_cli_failure_and_error_messages(self):
        original = ENTRYPOINT.read_text()
        options = original.splitlines()[1]
        build = original[original.index('# Build project\n'):]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = root / 'ccs-server-cli.sh'
            cli.chmod(0o755) if cli.exists() else None
            for status, message, expected in [(0, 'normal', 0), (17, 'crash without familiar wording', 1), (0, '1 out of 1 projects have errors', 1), (143, 'terminated', 1)]:
                cli.write_text(f'#!/bin/bash\necho "{message}"\nexit {status}\n')
                cli.chmod(0o755)
                script = '\n'.join([options, f'CCS_ECLIPSE_DIR="{root}"', 'CCS_WORKSPACE=/tmp', 'PROJECT_NAME=fixture', 'BUILD_CONFIG=Debug', build])
                result = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertIn(message, result.stdout)

    def test_installer_nonzero_is_not_masked_by_tee(self):
        options = ENTRYPOINT.read_text().splitlines()[1]
        result = subprocess.run(['bash', '-c', options + '\n(bash -c "echo installer-failed; exit 42") | tee /dev/null\necho SHOULD_NOT_RUN'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 42)
        self.assertNotIn('SHOULD_NOT_RUN', result.stdout)

    def test_discovery_does_not_use_early_exiting_head(self):
        self.assertNotIn('| head -1', ENTRYPOINT.read_text())


if __name__ == '__main__':
    unittest.main()
