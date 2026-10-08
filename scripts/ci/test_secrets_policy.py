"""Tests for the gate that keeps token-bearing values out of log output."""

import unittest

import secrets_policy


class SecretsPolicyTest(unittest.TestCase):
    def findings(self, source):
        return secrets_policy.findings("Reader.swift", source)

    def test_catches_an_access_token_interpolated_into_a_logger_call(self):
        source = 'logger.debug("token \\(credentials.accessToken)")\n'
        self.assertEqual(len(self.findings(source)), 1)

    def test_catches_each_logging_api_and_identifier(self):
        cases = [
            'print("\\(auth.access_token)")',
            'NSLog("%@", refreshToken)',
            'os_log("%{public}@", request.value(forHTTPHeaderField: "Authorization"))',
            'Self.logger.error("failed \\(headers["Authorization"] ?? "")")',
        ]
        for case in cases:
            with self.subTest(case=case):
                self.assertEqual(len(self.findings(case + "\n")), 1)

    def test_catches_bare_tokens_headers_account_ids_and_bodies(self):
        cases = [
            'logger.debug("\\(token)")',
            'print("Bearer \\(value)")',
            'logger.info("sent \\(request.headers)")',
            'logger.info("account \\(accountId)")',
            "print(String(decoding: response.body, as: UTF8.self))",
        ]
        for case in cases:
            with self.subTest(case=case):
                self.assertEqual(len(self.findings(case + "\n")), 1)

    def test_allows_identifiers_that_merely_contain_token(self):
        source = (
            'logger.info("parsed \\(tokenCount) lines from \\(bodyLength) bytes")\n'
        )
        self.assertEqual(self.findings(source), [])

    def test_catches_a_call_that_spans_several_lines(self):
        source = 'logger.info(\n    "using \\(token.accessToken)"\n)\n'
        self.assertIn("Reader.swift:1", self.findings(source)[0])

    def test_allows_tokens_outside_logging_calls(self):
        source = (
            'request.setValue("Bearer \\(credentials.accessToken)", '
            'forHTTPHeaderField: "Authorization")\n'
            'logger.info("refresh finished for \\(profile.id, privacy: .private)")\n'
        )
        self.assertEqual(self.findings(source), [])


if __name__ == "__main__":
    unittest.main()
