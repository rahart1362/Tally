#!/usr/bin/env python3
"""EB-07 (dossier.md §12; compliance dossier, Guideline 5.1.1(i) accuracy): the privacy policy
names only the network flows the composition root actually wires, and every flow it wires is
named in the policy.

Parsing the policy's prose directly is fragile (it is English sentences counsel will keep
editing), so the policy carries a small machine-readable manifest in an HTML comment
(`POLICY-FLOWS`, in `site/privacy/index.html`) that states, for each known flow, whether the
prose above currently describes it as active. This script never touches the prose; it only reads
that comment and compares it against what the app itself wires:

  - `canvas-api` (the school's own Canvas host: sign-in token exchange, revoke, observer
    endpoints) is wired when `AppEnvironment.live()` passes a real `makeTokenExchange` (built
    from `SignInServices.canvasTokenExchange`) rather than leaving it at `SignInServices`'s own
    default, which only ever returns `UnavailableTokenExchange`.
  - `school-search` (Instructure's school directory, `canvas.instructure.com`) is wired only if
    `live()` explicitly assigns `institutionSearch:`; `SignInServices`'s own default
    (`UnavailableInstitutionSearch()`) always throws `.transportNotConfigured` and never reaches
    a host (dossier F5).
  - `school-list-download` (a signed school list from tally-app.dev) is wired only if `live()`
    passes a non-empty `registry:`; the default, `ClientRegistry([])`, is a literal empty list:
    no fetch, no host.
  - `summary-sharing` (a weekly/monthly summary a student shares) is wired only if any shipping
    source defines a type or function whose name says so; none exists today (dossier F5, BL-14 —
    this is a feature gap, not a composition-root wiring gap, but the effect on the policy is the
    same: nothing to disclose).

A flow the policy calls active that the app does not wire is an overclaim; a flow the app wires
that the policy does not call active is an undisclosed flow. Both fail the build, UNLESS the
mismatch is on the dated `ALLOWLIST` below, which names the dossier gap it tracks. The allowlist
only ever excuses a mismatch in the overclaim direction (the safer of the two), and only for the
exact flow named — a NEW mismatch, or the opposite direction, still fails. Shrink the allowlist
(remove the entry) once the policy's own `POLICY-FLOWS` comment stops claiming the flow is
active; the script then says so (a notice, not a failure) if the entry is still present but no
longer needed.

    python3 scripts/ci/check_policy_matches_app.py [ROOT]
    python3 scripts/ci/check_policy_matches_app.py --self-test

Exit 0 every flow accounted for; 1 an unallowed mismatch exists; 2 an input could not be read or
understood (never a silent pass).
"""
from __future__ import annotations

import pathlib
import re
import sys

POLICY = "site/privacy/index.html"
SIGN_IN_SERVICES = "packages/TallyAppleKit/Sources/TallyFeatures/Account/SignInServices.swift"
APP_ENVIRONMENT = "apps/TallyiOS/Tally/AppEnvironment.swift"
# Shipping sources scanned for a wired summary-sharing feature (never test targets: a fixture or
# test double implementing the protocol would not make the feature live on `main`).
SHIPPING_SOURCE_DIRS = (
    "packages/TallyAppleKit/Sources",
    "apps/TallyiOS/Tally",
    "packages/TallyCore/Sources",
)

FLOWS = ("canvas-api", "school-search", "school-list-download", "summary-sharing")

# dossier.md §12 (2026-10-12). Each entry excuses exactly one flow's OVERCLAIM (the policy calls
# it active; the app does not wire it) until counsel's rewrite stops claiming it. Never excuses
# the opposite direction (an undisclosed flow the app actually wires).
ALLOWLIST = {
    # P1: "Finding your school" (site/privacy/index.html, the paragraph after "Your Canvas
    # information") describes both the Instructure search and the tally-app.dev list download as
    # if live. Neither is wired on `main` (dossier F5: search exists in code but is never
    # instantiated; the enablement list is empty).
    "school-search": "dossier.md §12 P1, 2026-10-12",
    "school-list-download": "dossier.md §12 P1, 2026-10-12",
    # P2: "Parents and linked accounts" describes a weekly/monthly summary a student can share.
    # No such feature exists in the app at all (no code; engineering-backlog.md BL-14).
    "summary-sharing": "dossier.md §12 P2, 2026-10-12",
}

POLICY_FLOWS_BLOCK = re.compile(r"<!--\s*POLICY-FLOWS.*?-->", re.S)
POLICY_FLOW_LINE = re.compile(r"^\s*([a-z-]+)\s*:\s*(active|inactive)\s*$", re.M)


class InputError(Exception):
    """An input could not be read or understood: exit 2, never a silent pass."""


# --------------------------------------------------------------------------------------------
# What the policy claims
# --------------------------------------------------------------------------------------------

def policy_claims(policy_html: str) -> dict[str, bool]:
    """flow -> True (claimed active) / False (claimed inactive), from the POLICY-FLOWS comment."""
    block = POLICY_FLOWS_BLOCK.search(policy_html)
    if not block:
        raise InputError(f"{POLICY}: no POLICY-FLOWS manifest comment found")
    claims = {match.group(1): match.group(2) == "active" for match in POLICY_FLOW_LINE.finditer(block.group(0))}
    unknown = sorted(set(claims) - set(FLOWS))
    if unknown:
        raise InputError(f"{POLICY}: POLICY-FLOWS names unknown flow(s) {unknown}; update FLOWS in this script too")
    missing = sorted(set(FLOWS) - set(claims))
    if missing:
        raise InputError(f"{POLICY}: POLICY-FLOWS is missing flow(s) {missing}")
    return claims


# --------------------------------------------------------------------------------------------
# What the app actually wires
# --------------------------------------------------------------------------------------------

def _live_function(app_environment: str) -> str:
    match = re.search(r"static func live\(\).*", app_environment, re.S)
    if not match:
        raise InputError(f"{APP_ENVIRONMENT}: no 'static func live()' found")
    return match.group(0)

def _sign_in_services_call(live_body: str) -> str:
    """The text of the one `SignInServices(...)` call in `live()`, parens balanced."""
    start = live_body.find("SignInServices(")
    if start == -1:
        raise InputError(f"{APP_ENVIRONMENT}: live() does not construct a SignInServices")
    depth = 0
    for index in range(start, len(live_body)):
        if live_body[index] == "(":
            depth += 1
        elif live_body[index] == ")":
            depth -= 1
            if depth == 0:
                return live_body[start:index + 1]
    raise InputError(f"{APP_ENVIRONMENT}: unbalanced parentheses in the SignInServices( call")

def _default_is_unavailable(sign_in_services: str, parameter: str) -> bool:
    """True when `SignInServices`'s own default for `parameter` is a dead end (never reaches a
    host): `institutionSearch ?? UnavailableInstitutionSearch()`, or a default argument that is a
    literal empty collection, e.g. `registry: ClientRegistry = ClientRegistry([])`."""
    coalesce = re.search(rf"{parameter}\s*\?\?\s*(\w+)\(\)", sign_in_services)
    if coalesce:
        return coalesce.group(1).startswith("Unavailable")
    default_arg = re.search(rf"{parameter}\s*:\s*\w+\s*=\s*(\w+)\(\s*\[\s*\]\s*\)", sign_in_services)
    if default_arg:
        return True  # an empty-literal default collection: no fetch, no host.
    raise InputError(f"{SIGN_IN_SERVICES}: could not find {parameter}'s default to classify it")

def app_wired_flows(sign_in_services: str, app_environment: str, shipping_text: str) -> set[str]:
    wired: set[str] = set()

    live_body = _live_function(app_environment)
    call = _sign_in_services_call(live_body)

    # canvas-api: a real token exchange, not the struct's own default (which only ever returns
    # UnavailableTokenExchange).
    if re.search(r"makeTokenExchange\s*:\s*SignInServices\.canvasTokenExchange", call):
        wired.add("canvas-api")

    # school-search: explicitly assigned in live() (in the constructor call, or by a later
    # `….institutionSearch = …` anywhere in live(); MVP-4 gate 2 caught the latter slipping
    # through), and not itself an Unavailable stand-in.
    assigned_search = re.search(r"\.institutionSearch\s*=\s*(\w+)\(", live_body)
    search_arg = re.search(r"institutionSearch\s*:\s*(\w+)\(", call)
    if assigned_search and not assigned_search.group(1).startswith("Unavailable"):
        wired.add("school-search")
    elif search_arg:
        if not search_arg.group(1).startswith("Unavailable"):
            wired.add("school-search")
    elif not _default_is_unavailable(sign_in_services, "institutionSearch"):
        wired.add("school-search")  # live() took the struct's default, and that default is live.

    # school-list-download: a non-empty registry, however it is built (in the call, or assigned
    # later in live()).
    assigned_registry = re.search(r"\.registry\s*=\s*([^\n;]+)", live_body)
    registry_arg = re.search(r"registry\s*:\s*([^,)]+)", call)
    if assigned_registry and not re.fullmatch(r"\s*\w+\s*\(\s*\[\s*\]\s*\)\s*", assigned_registry.group(1)):
        wired.add("school-list-download")
    elif registry_arg:
        if not re.fullmatch(r"\s*\w+\s*\(\s*\[\s*\]\s*\)\s*", registry_arg.group(1)):
            wired.add("school-list-download")
    elif not _default_is_unavailable(sign_in_services, "registry"):
        wired.add("school-list-download")

    # summary-sharing: no composition-root seam at all today; detect the feature itself, by name,
    # anywhere in shipping code (never test targets — see SHIPPING_SOURCE_DIRS).
    if re.search(r"\bSummaryShar(?:e|ing)\b|\b(?:Weekly|Monthly)Summary\b", shipping_text, re.I):
        wired.add("summary-sharing")

    return wired


def _read_shipping_text(root: pathlib.Path) -> str:
    chunks = []
    for rel in SHIPPING_SOURCE_DIRS:
        directory = root / rel
        if not directory.is_dir():
            raise InputError(f"{rel}: not a directory")
        for path in sorted(directory.rglob("*.swift")):
            if "Tests" in path.parts:
                continue
            chunks.append(path.read_text())
    return "\n".join(chunks)


# --------------------------------------------------------------------------------------------
# Compare
# --------------------------------------------------------------------------------------------

def check(policy_html: str, sign_in_services: str, app_environment: str, shipping_text: str,
          allowlist: dict[str, str] | None = ALLOWLIST) -> tuple[list[str], list[str]]:
    """(errors, notices). `allowlist=None` or `{}` checks with no excuses at all (used by the
    self-test to prove the allowlist is doing real work)."""
    allowlist = allowlist or {}
    claims = policy_claims(policy_html)
    wired = app_wired_flows(sign_in_services, app_environment, shipping_text)

    errors: list[str] = []
    notices: list[str] = []
    for flow in FLOWS:
        claimed_active = claims[flow]
        is_wired = flow in wired
        if claimed_active and not is_wired:
            if flow in allowlist:
                continue
            errors.append(f"{flow}: the policy's POLICY-FLOWS calls it active, but the app does not wire it "
                          f"(overclaim; add a dated allowlist entry only if this is a known, tracked dossier gap)")
        elif is_wired and not claimed_active:
            errors.append(f"{flow}: the app wires it, but the policy's POLICY-FLOWS does not call it active "
                          f"(undisclosed flow; the allowlist never excuses this direction)")
        elif flow in allowlist:
            notices.append(f"{flow}: no longer mismatched ({allowlist[flow]}) — the allowlist entry can be removed")
    return errors, notices


def read_inputs(root: pathlib.Path) -> tuple[str, str, str, str]:
    try:
        policy_html = (root / POLICY).read_text()
        sign_in_services = (root / SIGN_IN_SERVICES).read_text()
        app_environment = (root / APP_ENVIRONMENT).read_text()
        shipping_text = _read_shipping_text(root)
    except OSError as error:
        raise InputError(str(error)) from error
    return policy_html, sign_in_services, app_environment, shipping_text


def main(root: pathlib.Path) -> int:
    try:
        policy_html, sign_in_services, app_environment, shipping_text = read_inputs(root)
        errors, notices = check(policy_html, sign_in_services, app_environment, shipping_text)
    except InputError as error:
        print(f"POLICY | ERROR | {error}")
        return 2
    for notice in notices:
        print(f"POLICY | NOTICE | {notice}")
    for error in errors:
        print(f"POLICY | FAIL | {error}")
    if errors:
        return 1
    print("POLICY | PASS | every flow the app wires is named active; every active claim is wired, or allow-listed")
    return 0


# --------------------------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------------------------

def self_test() -> int:
    """Every check catches what it guards, on inputs derived from the real files."""
    root = pathlib.Path(__file__).resolve().parents[2]
    policy_html, sign_in_services, app_environment, shipping_text = read_inputs(root)

    errors, _ = check(policy_html, sign_in_services, app_environment, shipping_text)
    assert errors == [], f"the repository's own inputs must pass with the real allowlist, got {errors}"

    # With no allowlist at all, today's three known dossier mismatches must still be caught —
    # proof the allowlist (not a bug in the comparison) is what keeps the real check green.
    bare_errors, _ = check(policy_html, sign_in_services, app_environment, shipping_text, allowlist={})
    expected_bare = {"school-search", "school-list-download", "summary-sharing"}
    found_bare = {error.split(":", 1)[0] for error in bare_errors}
    assert found_bare == expected_bare, f"expected {expected_bare} without an allowlist, got {found_bare}"

    failures = 0

    def case(name: str, mutated_errors: list[str], should_fail: bool):
        nonlocal failures
        caught = bool(mutated_errors)
        ok = caught == should_fail
        failures += 0 if ok else 1
        print(f"POLICY self-test | {'caught' if ok else 'MISSED'} | {name}"
              + (f": {mutated_errors[0]}" if mutated_errors else ""))

    # --- Overclaims the app does not wire, undoing each allowlist entry one at a time --------
    for flow in ("school-search", "school-list-download", "summary-sharing"):
        errs, _ = check(policy_html, sign_in_services, app_environment, shipping_text,
                        allowlist={k: v for k, v in ALLOWLIST.items() if k != flow})
        case(f"{flow} overclaim, un-allow-listed", errs, should_fail=True)

    # --- A flow the app wires that the policy does not call active (undisclosed) -------------
    search_live_claims = policy_html.replace("school-search: active", "school-search: inactive")
    wired_search_app_env = app_environment.replace(
        "var signIn = SignInServices(webAuthPresenter: WebAuthPresenter(),",
        "var signIn = SignInServices(webAuthPresenter: WebAuthPresenter(), "
        "institutionSearch: CanvasAccountSearch(transport: transport),")
    errs, _ = check(search_live_claims, sign_in_services, wired_search_app_env, shipping_text)
    case("school-search wired and left inactive (undisclosed)", errs, should_fail=True)
    # The same flow wired by an assignment after construction (MVP-4 gate 2, P1), left inactive.
    assigned_search_app_env = app_environment.replace(
        "var signIn = SignInServices(webAuthPresenter: WebAuthPresenter(),",
        "var signIn = SignInServices(webAuthPresenter: WebAuthPresenter(),", 1)
    marker = "var signIn = SignInServices("
    i = assigned_search_app_env.find(marker)
    j = assigned_search_app_env.find("\n", assigned_search_app_env.find(")", i))
    assigned_search_app_env = (assigned_search_app_env[:j] +
                               "\n        signIn.institutionSearch = CanvasAccountSearch(transport: transport)" +
                               assigned_search_app_env[j:])
    errs, _ = check(search_live_claims, sign_in_services, assigned_search_app_env, shipping_text)
    case("school-search assigned after construction and left inactive (undisclosed)", errs, should_fail=True)
    # Sanity: the same code change, with the claim correctly flipped to active too, must pass.
    both_active = policy_html  # already "active" for school-search
    errs, _ = check(both_active, sign_in_services, wired_search_app_env, shipping_text)
    case("school-search wired AND claimed active (consistent)", errs, should_fail=False)

    # --- canvas-api stops being wired while still claimed active (new, unlisted overclaim) ---
    unwired_canvas_app_env = app_environment.replace(
        "makeTokenExchange: SignInServices.canvasTokenExchange(transport: transport))",
        "makeTokenExchange: nil)")
    errs, _ = check(policy_html, sign_in_services, unwired_canvas_app_env, shipping_text)
    case("canvas-api stops being wired but policy still claims it active", errs, should_fail=True)

    # --- A resolved mismatch produces a notice, not a failure, and is removable ---------------
    summary_sharing_resolved = policy_html.replace("summary-sharing: active", "summary-sharing: inactive")
    errs, notices = check(summary_sharing_resolved, sign_in_services, app_environment, shipping_text)
    ok = not errs and any("summary-sharing" in n for n in notices)
    failures += 0 if ok else 1
    print(f"POLICY self-test | {'caught' if ok else 'MISSED'} | summary-sharing claim corrected to inactive"
          f" (no error" + (", notice fires)" if ok else ")"))

    # --- A missing POLICY-FLOWS block, and an unknown flow name, are InputErrors (exit 2) -----
    try:
        policy_claims(policy_html.replace("POLICY-FLOWS", "NOT-THE-MARKER"))
        print("POLICY self-test | MISSED | a policy with no POLICY-FLOWS comment")
        failures += 1
    except InputError:
        print("POLICY self-test | caught | a policy with no POLICY-FLOWS comment")
    try:
        policy_claims(policy_html.replace("canvas-api: active", "canvas-api-v2: active"))
        print("POLICY self-test | MISSED | an unknown flow name in POLICY-FLOWS")
        failures += 1
    except InputError:
        print("POLICY self-test | caught | an unknown flow name in POLICY-FLOWS")

    total = 3 + 2 + 1 + 1 + 2
    print(f"POLICY self-test | {'PASS' if failures == 0 else 'FAIL'} | {total - failures} of {total}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
