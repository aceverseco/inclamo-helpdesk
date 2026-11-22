#!/usr/bin/env python3
"""docs-signal: the queue the documentation is written from.

Three commands, one per workflow job (CONTRIBUTING.md, "Docs labels and release tags"):

  check    a pull request into main carries one docs label, docs:none alone, and a filled
           "## Docs" section when the change is user-facing (workflow docs-label);
  signal   a merged user-facing pull request gets exactly one open issue "Docs: <title> (#N)"
           labelled docs-pending, and the founder gets a Slack message about it
           (workflow docs-signal, on merge or by hand with the number of the pull request);
  release  a pushed deployment tag labels "released" every open docs-pending issue whose merge
           commit the tag contains (workflow docs-signal, on a tag v*).

The script talks to GitHub's REST API with the workflow's GITHUB_TOKEN and to Slack's
chat.postMessage with SLACK_BOT_TOKEN; it needs nothing but the Python standard library and git.
Every run reads the pull request as it stands now, not the event that started it, so a re-run
after a label change sees the new labels.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable
from typing import Any

DOCS_LABELS = ("docs:new", "docs:update", "docs:api", "docs:none")
USER_FACING = ("docs:new", "docs:update", "docs:api")
PENDING = "docs-pending"
RELEASED = "released"
FIELDS = ("What the user sees", "Where", "Availability", "Screenshots", "API")
AVAILABILITY = re.compile(r"^(on deploy|not exposed|behind setting:\s*\S.*)$")

# Files whose change the docs agent reads first: behaviour contracts, archived OpenSpec changes
# and specs, API descriptions. Listed in the body of the docs issue.
CONTRACTS = (
    re.compile(r"(^|/)docs/behavior/"),
    re.compile(r"(^|/)openspec/changes/archive/"),
    re.compile(r"(^|/)openspec/specs/"),
    re.compile(r"(^|/)(openapi|swagger)[^/]*\.(json|ya?ml)$"),
)

SECTION_TEMPLATE = """## Docs
- What the user sees:      <!-- one to three sentences of fact, for the merchant -->
- Where:                   <!-- the screen or the menu path -->
- Availability: on deploy  <!-- on deploy | behind setting: <name> | not exposed -->
- Screenshots: no          <!-- or: yes - which screens -->
- API: none                <!-- or: the endpoint or webhook and what changed in it -->"""

PR_MARKER = "<!-- docs-signal:pr={number} -->"
MERGE_MARKER = re.compile(r"<!-- docs-signal:merge=([0-9a-f]{7,40}) -->")
NOTIFIED_MARKER = "<!-- docs-signal:notified -->"
TAG_SCHEME = re.compile(r"^v\d+\.\d+\.\d+(\.\d+)?$")

MAX_SECTION = 20000
MAX_CONTRACTS = 200


# --- The pull request's description --------------------------------------------------------


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def docs_section(body: str | None) -> str | None:
    """The "## Docs" section of a description, heading included, up to the next heading of level
    one or two; headings inside code fences do not count. None when there is no such section."""
    lines = (body or "").replace("\r\n", "\n").split("\n")
    out: list[str] | None = None
    fence = False
    for line in lines:
        if line.lstrip().startswith(("```", "~~~")):
            fence = not fence
        heading = not fence and re.match(r"^#{1,2}\s", line)
        if out is None:
            if heading and re.match(r"^##\s+Docs\s*$", line.strip(), re.IGNORECASE):
                out = [line.rstrip()]
            continue
        if heading:
            break
        out.append(line.rstrip())
    if out is None:
        return None
    return "\n".join(out).strip()


def section_fields(section: str) -> dict[str, str]:
    """Field name (lower case) -> value of the "- Name: value" lines, comments removed."""
    fields: dict[str, str] = {}
    for line in strip_comments(section).split("\n"):
        m = re.match(r"^\s*[-*]\s*([^:]+?)\s*:\s*(.*)$", line)
        if m:
            fields.setdefault(m.group(1).strip().lower(), m.group(2).strip())
    return fields


def placeholder(value: str) -> bool:
    return not value or bool(re.fullmatch(r"<[^>]*>", value))


def check_pull_request(labels: Iterable[str], body: str | None) -> list[str]:
    """What keeps a pull request from passing docs-label; empty when it passes."""
    docs = [name for name in DOCS_LABELS if name in set(labels)]
    problems: list[str] = []
    if not docs:
        problems.append(
            "No docs label. Put one on the pull request: docs:new, docs:update, docs:api (alone or "
            "with docs:new / docs:update), or docs:none alone."
        )
        return problems
    if "docs:none" in docs and len(docs) > 1:
        others = ", ".join(name for name in docs if name != "docs:none")
        problems.append(f"docs:none conflicts with {others}: remove docs:none or the other docs labels.")
    if not any(name in USER_FACING for name in docs):
        return problems
    section = docs_section(body)
    if section is None:
        problems.append(
            "A pull request labelled "
            + ", ".join(n for n in docs if n != "docs:none")
            + " needs a '## Docs' section in its description:\n\n"
            + SECTION_TEMPLATE
        )
        return problems
    fields = section_fields(section)
    missing = [name for name in FIELDS if name.lower() not in fields]
    if missing:
        problems.append("The '## Docs' section has no line for: " + ", ".join(missing) + ".")
    if placeholder(fields.get("what the user sees", "")):
        problems.append("'What the user sees' is empty: write one to three sentences for the merchant.")
    availability = fields.get("availability")
    if availability is not None and not AVAILABILITY.match(availability):
        problems.append(
            f"'Availability: {availability}' is not one of: on deploy, behind setting: <name>, not exposed."
        )
    return problems


# --- The docs issue -------------------------------------------------------------------------


def contract_files(filenames: Iterable[str]) -> list[str]:
    seen: list[str] = []
    for name in filenames:
        if name and name not in seen and any(p.search(name) for p in CONTRACTS):
            seen.append(name)
    return seen


def issue_title(number: int, title: str) -> str:
    suffix = f" (#{number})"
    room = 256 - len("Docs: ") - len(suffix)
    title = " ".join(title.split())
    if len(title) > room:
        title = title[: room - 1].rstrip() + "…"
    return f"Docs: {title}{suffix}"


def issue_body(pr: dict[str, Any], merge_sha: str, section: str | None, contracts: list[str]) -> str:
    labels = [n for n in USER_FACING if n in label_names(pr)]
    section_text = strip_comments(section or "").strip() or "## Docs\n(no section in the pull request)"
    if len(section_text) > MAX_SECTION:
        section_text = section_text[:MAX_SECTION] + "\n…(cut, see the pull request)"
    lines = [
        PR_MARKER.format(number=pr["number"]),
        f"<!-- docs-signal:merge={merge_sha} -->",
        f"Pull request: {pr['html_url']}",
        f"Merge commit: `{merge_sha}`",
        "Labels: " + ", ".join(f"`{n}`" for n in labels),
        "",
        section_text,
        "",
        "## Contract files",
    ]
    if contracts:
        lines += [f"- `{name}`" for name in contracts[:MAX_CONTRACTS]]
        if len(contracts) > MAX_CONTRACTS:
            lines.append(f"- …and {len(contracts) - MAX_CONTRACTS} more, see the pull request")
    else:
        lines.append("None changed.")
    lines += [
        "",
        (
            f"`{RELEASED}` comes with the deployment tag that contains the merge commit; until then "
            "the documentation of this change is a draft."
        ),
    ]
    return "\n".join(lines)


def label_names(item: dict[str, Any]) -> list[str]:
    return [(label["name"] if isinstance(label, dict) else label) for label in item.get("labels") or []]


def slack_escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def slack_text(repo: str, issue: dict[str, Any], pr: dict[str, Any]) -> str:
    labels = " · ".join(n for n in USER_FACING if n in label_names(pr))
    return (
        f"Задача на документацию в {repo.split('/')[-1]}: "
        f"<{issue['html_url']}|{slack_escape(issue['title'])}>\n"
        f"Метки: {labels} · PR: <{pr['html_url']}|#{pr['number']}>"
    )


def post_slack(
    token: str,
    channel: str,
    text: str,
    api_url: str = "https://slack.com/api",
    urlopen: Callable[..., Any] = urllib.request.urlopen,
) -> dict[str, Any]:
    """chat.postMessage; returns Slack's answer. Raises unless the answer says ok."""
    request = urllib.request.Request(
        api_url.rstrip("/") + "/chat.postMessage",
        data=json.dumps({"channel": channel, "text": text, "unfurl_links": False}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urlopen(request, timeout=20) as response:
        answer = json.loads(response.read().decode() or "{}")
    if not answer.get("ok"):
        raise RuntimeError(f"Slack chat.postMessage answered {answer.get('error') or answer}")
    return answer


# --- GitHub ---------------------------------------------------------------------------------


class GitHub:
    def __init__(self, token: str, repo: str, api_url: str = "https://api.github.com") -> None:
        self.token, self.repo, self.api_url = token, repo, api_url.rstrip("/")

    def request(self, method: str, path: str, data: Any = None, params: dict[str, Any] | None = None) -> Any:
        return self._call(method, self._url(path, params), data)[0]

    def paginate(self, path: str, params: dict[str, Any] | None = None) -> list[Any]:
        url: str | None = self._url(path, {"per_page": 100, **(params or {})})
        items: list[Any] = []
        while url:
            page, headers = self._call("GET", url, None)
            items += page.get("items", []) if isinstance(page, dict) else page
            m = re.search(r'<([^>]+)>;\s*rel="next"', headers.get("Link") or "")
            url = m.group(1) if m else None
        return items

    def _url(self, path: str, params: dict[str, Any] | None) -> str:
        path = path.replace("{repo}", self.repo)
        url = path if path.startswith("http") else f"{self.api_url}/{path.lstrip('/')}"
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        return url

    def _call(self, method: str, url: str, data: Any) -> tuple[Any, Any]:
        request = urllib.request.Request(
            url,
            data=None if data is None else json.dumps(data).encode(),
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": "application/json",
                "User-Agent": "docs-signal",
            },
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read().decode()
                return (json.loads(raw) if raw else None), response.headers
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            raise RuntimeError(f"GitHub {method} {url}: {error.code} {detail}") from None


def find_issue(gh: Any, number: int) -> dict[str, Any] | None:
    """The docs issue of a pull request, open or closed, by its marker. Open issues carry
    docs-pending (a fresh one is not in the search index yet); closed ones are found by search."""
    marker = PR_MARKER.format(number=number)
    candidates = gh.paginate("repos/{repo}/issues", {"state": "all", "labels": PENDING})
    try:
        query = f'repo:{gh.repo} is:issue in:body "docs-signal:pr={number}"'
        candidates += gh.paginate("search/issues", {"q": query})
    except RuntimeError as error:  # the search is a second net; the label listing is the first
        warn(f"issue search failed, relying on the {PENDING} listing: {error}")
    for issue in candidates:
        if "pull_request" not in issue and marker in (issue.get("body") or ""):
            return issue
    return None


# --- Commands -------------------------------------------------------------------------------


def annotate(kind: str, message: str, title: str = "docs-signal") -> None:
    encoded = message.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{kind} title={title}::{encoded}")


def warn(message: str) -> None:
    annotate("warning", message)


SUMMARY_PATH: str | None = None  # GITHUB_STEP_SUMMARY of the run, set by main()


def summary(text: str) -> None:
    path = SUMMARY_PATH
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text.rstrip() + "\n")


def command_check(gh: Any, event: dict[str, Any]) -> int:
    pr = event["pull_request"]
    try:  # the pull request as it stands: a re-run must see labels put on after the event
        pr = gh.request("GET", f"repos/{{repo}}/pulls/{pr['number']}")
    except RuntimeError as error:
        warn(f"reading the pull request failed, checking the event's copy: {error}")
    labels = label_names(pr)
    problems = check_pull_request(labels, pr.get("body"))
    if not problems:
        docs = ", ".join(n for n in DOCS_LABELS if n in labels)
        print(f"docs-label: #{pr['number']} passes ({docs})")
        summary(f"docs-label: passes ({docs})")
        return 0
    for problem in problems:
        annotate("error", problem, title="docs-label")
    summary(
        "## docs-label failed\n\n"
        + "\n\n".join(f"- {p}" for p in problems)
        + '\n\nThe labels and the section: CONTRIBUTING.md, "Docs labels and release tags".'
    )
    return 1


def command_signal(gh: Any, event_name: str, event: dict[str, Any], env: dict[str, str]) -> int:
    if event_name == "workflow_dispatch":
        raw = env.get("PR_NUMBER") or str((event.get("inputs") or {}).get("pr") or "")
        if not raw.strip().lstrip("#").isdigit():
            annotate("error", f"workflow_dispatch needs the number of a pull request, got {raw!r}")
            return 1
        number = int(raw.strip().lstrip("#"))
    else:
        number = int(event["pull_request"]["number"])
    pr = gh.request("GET", f"repos/{{repo}}/pulls/{number}")
    if not pr.get("merged"):
        message = f"#{number} is not merged: no docs task"
        if event_name == "workflow_dispatch":
            annotate("error", message)
            return 1
        print(message)
        return 0
    labels = label_names(pr)
    visible = [n for n in USER_FACING if n in labels]
    if not visible:
        print(
            f"#{number} is not user-facing ({', '.join(n for n in labels if n.startswith('docs')) or 'no docs label'}): no docs task"
        )
        summary(f"#{number}: no docs task (not labelled docs:new, docs:update or docs:api)")
        return 0
    merge_sha = pr.get("merge_commit_sha") or ""
    issue = find_issue(gh, number)
    if issue is None:
        files = gh.paginate(f"repos/{{repo}}/pulls/{number}/files")
        names = [f.get("filename") for f in files] + [f.get("previous_filename") for f in files]
        body = issue_body(pr, merge_sha, docs_section(pr.get("body")), contract_files(n for n in names if n))
        issue = gh.request(
            "POST",
            "repos/{repo}/issues",
            {
                "title": issue_title(number, pr["title"]),
                "body": body,
                "labels": [PENDING, *visible],
            },
        )
        print(f"opened {issue['html_url']}")
        summary(f"#{number}: opened [{issue['title']}]({issue['html_url']})")
    else:
        print(f"#{number} already has its docs issue {issue['html_url']}: none opened")
        summary(f"#{number}: the docs issue exists, [{issue['title']}]({issue['html_url']})")
        missing = [n for n in visible if n not in label_names(issue)]
        if missing and issue.get("state") == "open":
            gh.request("POST", f"repos/{{repo}}/issues/{issue['number']}/labels", {"labels": missing})
    if NOTIFIED_MARKER in (issue.get("body") or ""):
        return 0
    token, channel = env.get("SLACK_BOT_TOKEN", ""), env.get("SLACK_NOTIFY_CHANNEL", "")
    if not token or not channel:
        annotate(
            "error",
            "SLACK_BOT_TOKEN (secret) or SLACK_NOTIFY_CHANNEL (variable) is not set: the founder "
            "was not told about the docs issue. Set them and re-run this job.",
        )
        return 1
    try:
        answer = post_slack(
            token, channel, slack_text(gh.repo, issue, pr), env.get("SLACK_API_URL", "https://slack.com/api")
        )
    except (RuntimeError, OSError, ValueError) as error:
        annotate("error", f"the Slack message was not sent: {error}. Re-run this job; the issue is not opened twice.")
        return 1
    print(f"Slack: sent, ts {answer.get('ts')}")
    gh.request(
        "PATCH",
        f"repos/{{repo}}/issues/{issue['number']}",
        {"body": (issue.get("body") or "").rstrip() + "\n" + NOTIFIED_MARKER},
    )
    return 0


def is_ancestor(sha: str, tag: str, cwd: str | None = None) -> bool | None:
    """True or False by `git merge-base --is-ancestor`; None when git does not know the commit."""
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", sha, f"refs/tags/{tag}^{{commit}}"],
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode in (0, 1):
        return result.returncode == 0
    return None


def command_release(gh: Any, tag: str, ancestor: Callable[[str, str], bool | None] = is_ancestor) -> int:
    if not TAG_SCHEME.match(tag):
        warn(
            f"the tag {tag} is not of the release scheme (v<overlay version> in the helpdesk, "
            "vYYYY.MM.DD[.N] in the app); its issues are marked anyway"
        )
    issues = [
        i for i in gh.paginate("repos/{repo}/issues", {"state": "open", "labels": PENDING}) if "pull_request" not in i
    ]
    released, waiting = [], []
    for issue in issues:
        m = MERGE_MARKER.search(issue.get("body") or "")
        if not m:
            warn(f"#{issue['number']} has no merge commit marker: left as it is")
            continue
        if RELEASED in label_names(issue):
            continue
        inside = ancestor(m.group(1), tag)
        if inside is None:
            warn(f"#{issue['number']}: git does not know the merge commit {m.group(1)}: left as it is")
            continue
        if not inside:
            waiting.append(issue)
            continue
        gh.request("POST", f"repos/{{repo}}/issues/{issue['number']}/labels", {"labels": [RELEASED]})
        gh.request("POST", f"repos/{{repo}}/issues/{issue['number']}/comments", {"body": f"Released in {tag}"})
        released.append(issue)
    lines = [f"## {tag}", "", f"Released: {len(released)}; still waiting for a deployment: {len(waiting)}"]
    lines += [f"- released: [{i['title']}]({i['html_url']})" for i in released]
    lines += [f"- waiting: [{i['title']}]({i['html_url']})" for i in waiting]
    print("\n".join(lines))
    summary("\n".join(lines))
    return 0


def main(argv: list[str], env: dict[str, str] | None = None) -> int:
    global SUMMARY_PATH
    env = dict(os.environ if env is None else env)
    SUMMARY_PATH = env.get("GITHUB_STEP_SUMMARY")
    if len(argv) != 1 or argv[0] not in ("check", "signal", "release"):
        print("usage: docs_signal.py check|signal|release", file=sys.stderr)
        return 2
    token = env.get("GITHUB_TOKEN") or env.get("GH_TOKEN") or ""
    gh = GitHub(token, env["GITHUB_REPOSITORY"], env.get("GITHUB_API_URL", "https://api.github.com"))
    event: dict[str, Any] = {}
    if env.get("GITHUB_EVENT_PATH"):
        with open(env["GITHUB_EVENT_PATH"], encoding="utf-8") as handle:
            event = json.load(handle)
    if argv[0] == "check":
        return command_check(gh, event)
    if argv[0] == "signal":
        return command_signal(gh, env.get("GITHUB_EVENT_NAME", ""), event, env)
    return command_release(gh, env["GITHUB_REF_NAME"])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
