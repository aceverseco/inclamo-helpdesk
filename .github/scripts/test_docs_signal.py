"""Tests of docs-signal on a stand-in GitHub and Slack served on loopback.

The script is run through main() and once as a program, with the environment a workflow gives it
(GITHUB_API_URL, GITHUB_EVENT_PATH, ...) pointing at the stand-in below. Nothing reaches the
network. The release tests build a throwaway git repository for `git merge-base --is-ancestor`.

Run: python3 -m unittest discover -s .github/scripts -p "test_docs_signal.py" -v
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import docs_signal

REPO = "acme/widgets"
SCRIPT = Path(__file__).resolve().parent / "docs_signal.py"

FILLED = """## Summary
Staff can open the helpdesk from the store app.

## Docs
- What the user sees: Store staff open the helpdesk from the Shopify app without a separate login.
- Where: Shopify admin → Apps → Inclamo → "Open helpdesk"
- Availability: on deploy  <!-- on deploy | behind setting: <name> | not exposed -->
- Screenshots: yes — the app home and the inbox after sign-in
- API: none

## Test plan
- [x] specs
"""


class World:
    """The state of the stand-in GitHub and Slack."""

    def __init__(self) -> None:
        self.pulls: dict[int, dict] = {}
        self.files: dict[int, list[dict]] = {}
        self.issues: dict[int, dict] = {}
        self.comments: list[tuple[int, str]] = []
        self.slack: list[dict] = []
        self.slack_answer: dict = {"ok": True, "ts": "1.0"}
        self.search_fails = False
        self.next_number = 1000
        self.calls: list[tuple[str, str]] = []

    def pull(self, number: int, labels=(), body=FILLED, merged=True, title="Let staff in", files=()):
        self.pulls[number] = {
            "number": number,
            "title": title,
            "body": body,
            "merged": merged,
            "html_url": f"https://github.com/{REPO}/pull/{number}",
            "merge_commit_sha": "ab" * 20 if merged else None,
            "labels": [{"name": n} for n in labels],
        }
        self.files[number] = [{"filename": f} for f in files]
        return self.pulls[number]

    def issue(self, title="x", body="", labels=(), state="open"):
        self.next_number += 1
        n = self.next_number
        self.issues[n] = {
            "number": n,
            "title": title,
            "body": body,
            "state": state,
            "html_url": f"https://github.com/{REPO}/issues/{n}",
            "labels": [{"name": l} for l in labels],
        }
        return self.issues[n]


class Handler(BaseHTTPRequestHandler):
    world: World

    def log_message(self, format, *args):  # quiet
        pass

    def _answer(self, status, payload, link=None):
        raw = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        if link:
            self.send_header("Link", link)
        self.end_headers()
        self.wfile.write(raw)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"null")

    def do_GET(self):
        w = self.world
        url = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        w.calls.append(("GET", url.path))
        parts = url.path.strip("/").split("/")
        if url.path == "/search/issues":
            if w.search_fails:
                return self._answer(422, {"message": "search is down"})
            needle = q["q"].split('"')[1]
            items = [i for i in w.issues.values() if needle in (i["body"] or "")]
            return self._answer(200, {"total_count": len(items), "items": items})
        if parts[:3] == ["repos", "acme", "widgets"]:
            rest = parts[3:]
            if rest[:1] == ["pulls"] and len(rest) == 2:
                pr = w.pulls.get(int(rest[1]))
                return self._answer(200, pr) if pr else self._answer(404, {"message": "Not Found"})
            if rest[:1] == ["pulls"] and rest[2:] == ["files"]:
                files = w.files.get(int(rest[1]), [])
                page = int(q.get("page", "1"))
                # two pages of files: the client must follow the Link header
                half = (len(files) + 1) // 2
                if page == 1 and len(files) > 1:
                    nxt = f'<http://{self.headers["Host"]}{url.path}?per_page=100&page=2>; rel="next"'
                    return self._answer(200, files[:half], link=nxt)
                return self._answer(200, files[half:] if page == 2 else files)
            if rest == ["issues"]:
                items = list(w.issues.values())
                if q.get("state") in ("open", "closed"):
                    items = [i for i in items if i["state"] == q["state"]]
                if q.get("labels"):
                    items = [i for i in items if q["labels"] in [l["name"] for l in i["labels"]]]
                # an open pull request is an issue too in this listing
                items.append(
                    {
                        "number": 1,
                        "pull_request": {},
                        "body": "<!-- docs-signal:pr=50 -->",
                        "labels": [{"name": "docs-pending"}],
                        "state": "open",
                    }
                )
                return self._answer(200, items)
        self._answer(404, {"message": "Not Found"})

    def do_POST(self):
        w = self.world
        path = urllib.parse.urlparse(self.path).path
        w.calls.append(("POST", path))
        if path == "/slack/chat.postMessage":
            assert self.headers["Authorization"] == "Bearer xoxb-test"
            assert self.headers["Content-Type"].startswith("application/json")
            w.slack.append(self._body())
            return self._answer(200, w.slack_answer)
        data = self._body()
        parts = path.strip("/").split("/")[3:]
        if parts == ["issues"]:
            issue = w.issue(data["title"], data["body"], data["labels"])
            return self._answer(201, issue)
        if parts[:1] == ["issues"] and parts[2:] == ["labels"]:
            issue = w.issues[int(parts[1])]
            issue["labels"] += [{"name": n} for n in data["labels"]]
            return self._answer(200, issue["labels"])
        if parts[:1] == ["issues"] and parts[2:] == ["comments"]:
            w.comments.append((int(parts[1]), data["body"]))
            return self._answer(201, {"id": 1})
        self._answer(404, {"message": "Not Found"})

    def do_PATCH(self):
        w = self.world
        path = urllib.parse.urlparse(self.path).path
        w.calls.append(("PATCH", path))
        parts = path.strip("/").split("/")[3:]
        issue = w.issues[int(parts[1])]
        issue.update(self._body())
        self._answer(200, issue)


class Base(unittest.TestCase):
    def setUp(self):
        self.world = World()
        handler = type("H", (Handler,), {"world": self.world})
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        api = f"http://127.0.0.1:{self.server.server_port}"
        self.env = {
            "GITHUB_REPOSITORY": REPO,
            "GITHUB_API_URL": api,
            "GITHUB_TOKEN": "ghs-test",
            "SLACK_BOT_TOKEN": "xoxb-test",
            "SLACK_NOTIFY_CHANNEL": "D0TEST",
            "SLACK_API_URL": api + "/slack",
            "GITHUB_STEP_SUMMARY": os.path.join(self.tmp.name, "summary.md"),
        }

    def run_script(self, command, event_name, event, **extra):
        path = os.path.join(self.tmp.name, "event.json")
        Path(path).write_text(json.dumps(event))
        env = {**self.env, "GITHUB_EVENT_NAME": event_name, "GITHUB_EVENT_PATH": path, **extra}
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = docs_signal.main([command], env)
        return code, out.getvalue()


class CheckRules(unittest.TestCase):
    def test_no_label(self):
        problems = docs_signal.check_pull_request([], FILLED)
        self.assertEqual(len(problems), 1)
        for name in docs_signal.DOCS_LABELS:
            self.assertIn(name, problems[0])

    def test_conflict_is_named(self):
        problems = docs_signal.check_pull_request(["docs:none", "docs:update"], FILLED)
        self.assertEqual(problems, ["docs:none conflicts with docs:update: remove docs:none or the other docs labels."])

    def test_user_facing_with_section_passes(self):
        for labels in (["docs:new"], ["docs:update", "docs:api"], ["docs:api"], ["docs:new", "area:core"]):
            self.assertEqual(docs_signal.check_pull_request(labels, FILLED), [], labels)

    def test_internal_needs_no_section(self):
        self.assertEqual(docs_signal.check_pull_request(["docs:none"], "Refactoring."), [])
        self.assertEqual(docs_signal.check_pull_request(["docs:none"], None), [])

    def test_missing_section_gives_the_template(self):
        problems = docs_signal.check_pull_request(["docs:new"], "## Summary\nA feature")
        self.assertEqual(len(problems), 1)
        self.assertIn(docs_signal.SECTION_TEMPLATE, problems[0])

    def test_untouched_template_is_empty(self):
        body = "## Summary\nx\n\n" + docs_signal.SECTION_TEMPLATE + "\n\n## Test plan\n"
        problems = docs_signal.check_pull_request(["docs:update"], body)
        self.assertEqual(problems, ["'What the user sees' is empty: write one to three sentences for the merchant."])

    def test_missing_fields_and_bad_availability(self):
        body = "## Docs\n- What the user sees: A new button.\n- Availability: soon\n"
        problems = docs_signal.check_pull_request(["docs:new"], body)
        self.assertIn("The '## Docs' section has no line for: Where, Screenshots, API.", problems)
        self.assertTrue(any("'Availability: soon'" in p for p in problems))

    def test_availability_values(self):
        for value in ("on deploy", "not exposed", "behind setting: AI replies"):
            body = FILLED.replace("Availability: on deploy", f"Availability: {value}")
            self.assertEqual(docs_signal.check_pull_request(["docs:new"], body), [], value)
        body = FILLED.replace("Availability: on deploy", "Availability: behind setting:")
        self.assertTrue(docs_signal.check_pull_request(["docs:new"], body))

    def test_section_ends_at_next_heading_and_ignores_fences(self):
        body = "```\n## Docs\n- What the user sees: example\n```\n## Notes\nnone"
        self.assertIsNone(docs_signal.docs_section(body))
        section = docs_signal.docs_section(FILLED)
        assert section is not None
        self.assertTrue(section.startswith("## Docs"))
        self.assertNotIn("Test plan", section)
        self.assertIn("### sub", docs_signal.docs_section("## Docs\n### sub\n- API: none\n# End") or "")

    def test_contract_files(self):
        names = [
            "docs/behavior/app-store-access/spec.md",
            "context/openspec/changes/archive/x/tasks.md",
            "openspec/specs/a/spec.md",
            "inclamo-core/voice/docs/openapi.json",
            "custom/app/x.rb",
            "docs/install.md",
            "docs/behavior/app-store-access/spec.md",
        ]
        self.assertEqual(docs_signal.contract_files(names), names[:4])

    def test_title(self):
        self.assertEqual(docs_signal.issue_title(50, "Let  staff in"), "Docs: Let staff in (#50)")
        self.assertLessEqual(len(docs_signal.issue_title(50, "x" * 400)), 256)

    def test_slack_text(self):
        pr = {
            "number": 50,
            "html_url": "https://github.com/acme/widgets/pull/50",
            "labels": [{"name": "docs:api"}, {"name": "docs:new"}],
        }
        issue = {"html_url": "https://github.com/acme/widgets/issues/51", "title": "Docs: A <b> & c (#50)"}
        text = docs_signal.slack_text(REPO, issue, pr)
        self.assertEqual(
            text,
            "Задача на документацию в widgets: "
            "<https://github.com/acme/widgets/issues/51|Docs: A &lt;b&gt; &amp; c (#50)>\n"
            "Метки: docs:new · docs:api · PR: <https://github.com/acme/widgets/pull/50|#50>",
        )


class PullRequestTemplate(unittest.TestCase):
    """The template of this repository is what the check reads: untouched, it fails a user-facing
    pull request on the empty line only, and passes once that line is written."""

    def test_template_matches_the_check(self):
        template = (Path(__file__).resolve().parents[1] / "pull_request_template.md").read_text()
        self.assertEqual(docs_signal.check_pull_request(["docs:none"], template), [])
        self.assertEqual(
            docs_signal.check_pull_request(["docs:new"], template),
            ["'What the user sees' is empty: write one to three sentences for the merchant."],
        )
        filled = template.replace("- What the user sees:", "- What the user sees: A new button.", 1)
        self.assertEqual(docs_signal.check_pull_request(["docs:new"], filled), [])


class CheckCommand(Base):
    def test_reads_the_pull_request_as_it_stands(self):
        # the event carried no label; the label was put on before the re-run
        self.world.pull(7, labels=["docs:update"])
        code, out = self.run_script("check", "pull_request", {"pull_request": {"number": 7, "labels": [], "body": ""}})
        self.assertEqual(code, 0, out)

    def test_fails_with_an_annotation(self):
        self.world.pull(7, labels=[])
        code, out = self.run_script("check", "pull_request", {"pull_request": {"number": 7}})
        self.assertEqual(code, 1)
        self.assertIn("::error title=docs-label::No docs label", out)
        self.assertIn("docs-label failed", Path(self.env["GITHUB_STEP_SUMMARY"]).read_text())

    def test_falls_back_to_the_event(self):
        code, out = self.run_script(
            "check", "pull_request", {"pull_request": {"number": 404, "labels": [{"name": "docs:none"}], "body": ""}}
        )
        self.assertEqual(code, 0, out)
        self.assertIn("::warning", out)


class SignalCommand(Base):
    def merged_event(self, number):
        return {"action": "closed", "pull_request": {"number": number, "merged": True}}

    def test_merge_of_a_new_feature_opens_one_issue_and_notifies(self):
        self.world.pull(
            50,
            labels=["docs:new", "area:core"],
            files=["docs/behavior/app-admin-entry/spec.md", "custom/app/x.rb", "openspec/specs/a/spec.md"],
        )
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(50))
        self.assertEqual(code, 0, out)
        [issue] = self.world.issues.values()
        self.assertEqual(issue["title"], "Docs: Let staff in (#50)")
        self.assertEqual([l["name"] for l in issue["labels"]], ["docs-pending", "docs:new"])
        body = issue["body"]
        for part in (
            "<!-- docs-signal:pr=50 -->",
            "<!-- docs-signal:merge=" + "ab" * 20 + " -->",
            "https://github.com/acme/widgets/pull/50",
            "## Docs",
            "Store staff open the helpdesk",
            "- `docs/behavior/app-admin-entry/spec.md`",
            "- `openspec/specs/a/spec.md`",
            docs_signal.NOTIFIED_MARKER,
        ):
            self.assertIn(part, body)
        self.assertNotIn("custom/app/x.rb", body)
        self.assertNotIn("Test plan", body)
        self.assertNotIn("<!-- on deploy", body)
        [message] = self.world.slack
        self.assertEqual(message["channel"], "D0TEST")
        self.assertIn(issue["html_url"], message["text"])

    def test_rerun_opens_no_second_issue_and_sends_nothing(self):
        self.world.pull(50, labels=["docs:update"])
        self.run_script("signal", "pull_request_target", self.merged_event(50))
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(50))
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.world.issues), 1)
        self.assertEqual(len(self.world.slack), 1)

    def test_closed_issue_is_found_by_search(self):
        self.world.pull(50, labels=["docs:update"])
        self.world.issue(
            "Docs: Let staff in (#50)",
            "<!-- docs-signal:pr=50 -->\n" + docs_signal.NOTIFIED_MARKER,
            ["docs:update", "released"],
            state="closed",
        )
        code, out = self.run_script("signal", "workflow_dispatch", {"inputs": {"pr": "50"}}, PR_NUMBER="50")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.world.issues), 1)
        self.assertEqual(self.world.slack, [])

    def test_marker_of_another_pr_is_not_a_match(self):
        self.world.pull(5, labels=["docs:new"])
        self.world.issue("Docs: other (#50)", "<!-- docs-signal:pr=50 -->", ["docs-pending"])
        self.run_script("signal", "pull_request_target", self.merged_event(5))
        self.assertEqual(len(self.world.issues), 2)

    def test_search_failure_still_dedupes_open_issues(self):
        self.world.search_fails = True
        self.world.pull(50, labels=["docs:new"])
        self.run_script("signal", "pull_request_target", self.merged_event(50))
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(50))
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.world.issues), 1)

    def test_internal_change_opens_nothing(self):
        self.world.pull(51, labels=["docs:none"])
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(51))
        self.assertEqual(code, 0, out)
        self.assertEqual(self.world.issues, {})
        self.assertEqual(self.world.slack, [])

    def test_closed_without_merge_opens_nothing(self):
        self.world.pull(52, labels=["docs:new"], merged=False)
        code, _ = self.run_script("signal", "pull_request_target", {"pull_request": {"number": 52, "merged": False}})
        self.assertEqual(code, 0)
        self.assertEqual(self.world.issues, {})

    def test_by_hand_for_a_label_put_on_after_the_merge(self):
        self.world.pull(53, labels=["docs:api"])
        code, out = self.run_script("signal", "workflow_dispatch", {"inputs": {"pr": "53"}}, PR_NUMBER="53")
        self.assertEqual(code, 0, out)
        [issue] = self.world.issues.values()
        self.assertEqual(issue["title"], "Docs: Let staff in (#53)")

    def test_by_hand_on_an_unmerged_pr_fails(self):
        self.world.pull(54, labels=["docs:new"], merged=False)
        code, out = self.run_script("signal", "workflow_dispatch", {"inputs": {"pr": "54"}}, PR_NUMBER="54")
        self.assertEqual(code, 1)
        self.assertIn("not merged", out)

    def test_by_hand_without_a_number_fails(self):
        code, _ = self.run_script("signal", "workflow_dispatch", {"inputs": {}}, PR_NUMBER="abc")
        self.assertEqual(code, 1)

    def test_slack_refusal_fails_and_the_rerun_sends_it(self):
        self.world.pull(50, labels=["docs:new"])
        self.world.slack_answer = {"ok": False, "error": "channel_not_found"}
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(50))
        self.assertEqual(code, 1)
        self.assertIn("channel_not_found", out)
        [issue] = self.world.issues.values()
        self.assertNotIn(docs_signal.NOTIFIED_MARKER, issue["body"])
        self.world.slack_answer = {"ok": True, "ts": "2.0"}
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(50))
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.world.issues), 1)
        self.assertIn(docs_signal.NOTIFIED_MARKER, issue["body"])

    def test_missing_slack_settings_fail_after_the_issue(self):
        self.world.pull(50, labels=["docs:new"])
        code, out = self.run_script("signal", "pull_request_target", self.merged_event(50), SLACK_BOT_TOKEN="")
        self.assertEqual(code, 1)
        self.assertEqual(len(self.world.issues), 1)
        self.assertIn("SLACK_BOT_TOKEN", out)
        self.assertNotIn("xoxb-test", out)


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class ReleaseCommand(Base):
    def setUp(self):
        super().setUp()
        self.repo = os.path.join(self.tmp.name, "repo")
        os.mkdir(self.repo)
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "t@example.com")
        git(self.repo, "config", "user.name", "t")
        self.shas = []
        for n in range(3):
            Path(self.repo, "f").write_text(str(n))
            git(self.repo, "add", "f")
            git(self.repo, "commit", "-q", "-m", f"c{n}")
            self.shas.append(git(self.repo, "rev-parse", "HEAD"))
        git(self.repo, "tag", "-a", "v0.2.0", self.shas[1], "-m", "Production")

    def docs_issue(self, pr, sha, labels=("docs-pending", "docs:new")):
        return self.world.issue(
            f"Docs: x (#{pr})", f"<!-- docs-signal:pr={pr} -->\n<!-- docs-signal:merge={sha} -->", labels
        )

    def release(self, tag="v0.2.0"):
        cwd = os.getcwd()
        os.chdir(self.repo)
        try:
            return self.run_script("release", "push", {}, GITHUB_REF_NAME=tag)
        finally:
            os.chdir(cwd)

    def test_tag_after_deployment_and_merged_but_not_deployed(self):
        deployed = self.docs_issue(50, self.shas[0])
        tagged = self.docs_issue(49, self.shas[1])
        later = self.docs_issue(51, self.shas[2])
        code, out = self.release()
        self.assertEqual(code, 0, out)
        for issue in (deployed, tagged):
            self.assertIn("released", [l["name"] for l in issue["labels"]])
            self.assertIn((issue["number"], "Released in v0.2.0"), self.world.comments)
        self.assertNotIn("released", [l["name"] for l in later["labels"]])
        self.assertEqual(len(self.world.comments), 2)

    def test_already_released_closed_and_unknown_are_left(self):
        done = self.docs_issue(48, self.shas[0], labels=("docs-pending", "released"))
        closed = self.docs_issue(47, self.shas[0])
        closed["state"] = "closed"
        unknown = self.docs_issue(46, "f" * 40)
        no_marker = self.world.issue("Docs: by hand", "no marker", ["docs-pending"])
        code, out = self.release()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.world.comments, [])
        self.assertEqual(len(done["labels"]), 2)
        for issue in (closed, unknown, no_marker):
            self.assertNotIn("released", [l["name"] for l in issue["labels"]])
        self.assertIn("does not know the merge commit", out)

    def test_calendar_tag_of_the_app(self):
        git(self.repo, "tag", "-a", "v2026.11.25.2", self.shas[2], "-m", "Production")
        issue = self.docs_issue(51, self.shas[2])
        code, out = self.release("v2026.11.25.2")
        self.assertEqual(code, 0)
        self.assertNotIn("::warning", out)
        self.assertIn("released", [l["name"] for l in issue["labels"]])


class AsAProgram(Base):
    def test_check_runs_from_the_command_line(self):
        self.world.pull(8, labels=["docs:none"])
        path = os.path.join(self.tmp.name, "event.json")
        Path(path).write_text(json.dumps({"pull_request": {"number": 8}}))
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "check"],
            check=False,
            capture_output=True,
            text=True,
            env={**os.environ, **self.env, "GITHUB_EVENT_PATH": path},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("passes (docs:none)", result.stdout)

    def test_unknown_command(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(docs_signal.main(["publish"], self.env), 2)


if __name__ == "__main__":
    unittest.main()
