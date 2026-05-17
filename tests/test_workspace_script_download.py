import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import specify_cli as cli


class FakeResponse:
    def __init__(self, status_code: int, content: bytes = b''):
        self.status_code = status_code
        self.content = content


class DownloadWorkspaceScriptsTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.scripts_dir = Path(self.tmpdir.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_prefers_shakudo_fork_before_upstream(self):
        requested_urls = []

        def fake_get(url, timeout, follow_redirects, headers):
            requested_urls.append(url)
            return FakeResponse(200, url.encode())

        with patch.object(cli.client, 'get', side_effect=fake_get):
            copied, errors = cli.download_workspace_scripts(self.scripts_dir, script_type='sh')

        self.assertEqual(copied, 5)
        self.assertEqual(errors, [])
        self.assertTrue(requested_urls)
        self.assertTrue(all('/Shakudo-io/spec-kit/main/' in url for url in requested_urls))
        self.assertTrue((self.scripts_dir / 'bash/check-prerequisites.sh').exists())

    def test_falls_back_to_upstream_when_fork_download_fails(self):
        requested_urls = []

        def fake_get(url, timeout, follow_redirects, headers):
            requested_urls.append(url)
            if '/Shakudo-io/spec-kit/main/' in url:
                return FakeResponse(404, b'')
            return FakeResponse(200, b'upstream-helper')

        with patch.object(cli.client, 'get', side_effect=fake_get):
            copied, errors = cli.download_workspace_scripts(self.scripts_dir, script_type='sh')

        self.assertEqual(copied, 5)
        self.assertEqual(errors, [])
        self.assertTrue(any('/Shakudo-io/spec-kit/main/' in url for url in requested_urls))
        self.assertTrue(any('/github/spec-kit/main/' in url for url in requested_urls))
        self.assertEqual((self.scripts_dir / 'bash/check-prerequisites.sh').read_bytes(), b'upstream-helper')


if __name__ == '__main__':
    unittest.main()
