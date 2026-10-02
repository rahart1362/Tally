#!/usr/bin/env python3
"""PAY-01 (pricing-licensing.md §6; PRD §11.1, §11.9): Tally's StoreKit products derive from the bundle ID.

Reads apps/TallyiOS/Config/Identity.xcconfig (the bundle ID is `$(TALLY_BUNDLE_ID_PREFIX).tally`),
the product-ID suffixes in packages/TallyCore/Sources/TallyDomain/Subscription/SubscriptionConfig.swift
and apps/TallyiOS/Config/Products.storekit, and checks that:

  - every product ID starts with the bundle ID, and the two IDs are `<bundle-id><studentAnnualSuffix>`
    and `<bundle-id><parentAnnualSuffix>`, as the app derives them (`SubscriptionProducts`);
  - there are exactly two subscription groups, "Tally" and "Tally Parent", one product each, and no
    other product of any kind;
  - "Tally": US$9.99 every year, a one-month free trial, one custom offer code, one win-back offer;
  - "Tally Parent": US$4.99 every year;
  - Family Sharing is off for both (PRD §11.1, owner decision 2026-09-27);
  - apps/TallyiOS/project.yml bundles the file into TallyAppTests and names it as the scheme's
    StoreKit configuration.

    python3 scripts/ci/check_storekit_products.py [ROOT]
    python3 scripts/ci/check_storekit_products.py --self-test

Exit 0 when every check passes, 1 when one fails (each printed), 2 when an input is missing or
unreadable (never a silent pass).
"""
from __future__ import annotations

import copy
import json
import pathlib
import re
import sys

IDENTITY = "apps/TallyiOS/Config/Identity.xcconfig"
STOREKIT = "apps/TallyiOS/Config/Products.storekit"
CONFIG_SWIFT = "packages/TallyCore/Sources/TallyDomain/Subscription/SubscriptionConfig.swift"
PROJECT = "apps/TallyiOS/project.yml"

STUDENT_GROUP = "Tally"
PARENT_GROUP = "Tally Parent"


class InputError(Exception):
    pass


def bundle_id(xcconfig: str) -> str:
    """`$(TALLY_BUNDLE_ID_PREFIX).tally`, from the xcconfig's two settings (comments stripped)."""
    settings = {}
    for line in xcconfig.splitlines():
        line = line.split("//", 1)[0].strip()
        match = re.match(r"^([A-Z_]+)\s*=\s*(.*)$", line)
        if match:
            settings[match.group(1)] = match.group(2).strip()
    prefix = settings.get("TALLY_BUNDLE_ID_PREFIX")
    product = settings.get("PRODUCT_BUNDLE_IDENTIFIER")
    if not prefix or not product:
        raise InputError("Identity.xcconfig: TALLY_BUNDLE_ID_PREFIX or PRODUCT_BUNDLE_IDENTIFIER missing")
    return product.replace("$(TALLY_BUNDLE_ID_PREFIX)", prefix)


def suffixes(swift: str) -> tuple[str, str]:
    """`studentAnnualSuffix` and `parentAnnualSuffix` from SubscriptionConfig.swift."""
    found = {}
    for name in ("studentAnnualSuffix", "parentAnnualSuffix"):
        match = re.search(name + r'\s*=\s*"([^"]+)"', swift)
        if not match:
            raise InputError(f"SubscriptionConfig.swift: {name} not found")
        found[name] = match.group(1)
    return found["studentAnnualSuffix"], found["parentAnnualSuffix"]


def check(xcconfig: str, storekit: dict, config_swift: str, project_yml: str) -> list[str]:
    """Every failed check, as a sentence; empty when all pass."""
    errors: list[str] = []
    bundle = bundle_id(xcconfig)
    student_suffix, parent_suffix = suffixes(config_swift)
    student_id, parent_id = bundle + student_suffix, bundle + parent_suffix

    if storekit.get("products") or storekit.get("nonRenewingSubscriptions"):
        errors.append("only the two subscriptions may exist: products or nonRenewingSubscriptions is not empty")
    groups = storekit.get("subscriptionGroups") or []
    names = sorted(group.get("name", "") for group in groups)
    if names != sorted([STUDENT_GROUP, PARENT_GROUP]):
        errors.append(f"subscription groups are {names}, expected exactly {[STUDENT_GROUP, PARENT_GROUP]}")
    all_subscriptions = [sub for group in groups for sub in group.get("subscriptions") or []]
    for sub in all_subscriptions:
        product_id = sub.get("productID", "")
        if not product_id.startswith(bundle + "."):
            errors.append(f"{product_id!r} does not start with the bundle ID {bundle!r} (Identity.xcconfig)")
        if sub.get("familyShareable") is not False:
            errors.append(f"{product_id}: Family Sharing must be off (familyShareable false)")
        if sub.get("type") != "RecurringSubscription":
            errors.append(f"{product_id}: not an auto-renewable subscription")
        if sub.get("recurringSubscriptionPeriod") != "P1Y":
            errors.append(f"{product_id}: the period must be one year (P1Y)")

    def only_subscription(name: str):
        group = next((g for g in groups if g.get("name") == name), None)
        subs = (group or {}).get("subscriptions") or []
        if len(subs) != 1:
            errors.append(f"group {name!r} must hold exactly one product, holds {len(subs)}")
            return None
        if subs[0].get("subscriptionGroupID") != group.get("id"):
            errors.append(f"{subs[0].get('productID')}: subscriptionGroupID does not match its group's id")
        return subs[0]

    student = only_subscription(STUDENT_GROUP)
    if student is not None:
        if student.get("productID") != student_id:
            errors.append(f"Tally's product is {student.get('productID')!r}, expected {student_id!r}")
        if student.get("displayPrice") != "9.99":
            errors.append("Tally Annual must be 9.99 a year")
        intro = student.get("introductoryOffer") or {}
        if not (intro.get("paymentMode") == "free" and intro.get("subscriptionPeriod") == "P1M"
                and intro.get("numberOfPeriods", 1) == 1):
            errors.append("Tally Annual needs a one-month free trial (introductory offer: free, P1M)")
        if len(student.get("codeOffers") or []) != 1:
            errors.append("Tally Annual needs exactly one custom offer code")
        if len(student.get("winbackOffers") or []) != 1:
            errors.append("Tally Annual needs exactly one win-back offer")
    parent = only_subscription(PARENT_GROUP)
    if parent is not None:
        if parent.get("productID") != parent_id:
            errors.append(f"Tally Parent's product is {parent.get('productID')!r}, expected {parent_id!r}")
        if parent.get("displayPrice") != "4.99":
            errors.append("Tally Parent must be 4.99 a year")

    # The test target bundles the file and the scheme names it (StoreKit Testing, PAY-03).
    if not re.search(r"-\s*path:\s*Config/Products\.storekit\s*\n\s*buildPhase:\s*resources", project_yml):
        errors.append("project.yml: TallyAppTests must bundle Config/Products.storekit (buildPhase: resources)")
    if not re.search(r"storeKitConfiguration:\s*Config/Products\.storekit", project_yml):
        errors.append("project.yml: the Tally scheme's run action must name Config/Products.storekit")
    return errors


def read_inputs(root: pathlib.Path) -> tuple[str, dict, str, str]:
    try:
        xcconfig = (root / IDENTITY).read_text()
        storekit = json.loads((root / STOREKIT).read_text())
        config_swift = (root / CONFIG_SWIFT).read_text()
        project_yml = (root / PROJECT).read_text()
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(str(error)) from error
    return xcconfig, storekit, config_swift, project_yml


def main(root: pathlib.Path) -> int:
    try:
        xcconfig, storekit, config_swift, project_yml = read_inputs(root)
        errors = check(xcconfig, storekit, config_swift, project_yml)
        bundle = bundle_id(xcconfig)
    except InputError as error:
        print(f"STOREKIT | ERROR | {error}")
        return 2
    for error in errors:
        print(f"STOREKIT | FAIL | {error}")
    if errors:
        return 1
    ids = [sub["productID"] for group in storekit["subscriptionGroups"] for sub in group["subscriptions"]]
    print(f"STOREKIT | PASS | bundle {bundle}: {', '.join(ids)}")
    return 0


def self_test() -> int:
    """Every check catches what it guards, on inputs derived from the real files."""
    root = pathlib.Path(__file__).resolve().parents[2]
    xcconfig, storekit, config_swift, project_yml = read_inputs(root)
    assert check(xcconfig, storekit, config_swift, project_yml) == [], "the repository's own inputs must pass"

    def broken(mutate) -> list[str]:
        sk = copy.deepcopy(storekit)
        xc, cs, py = mutate(sk, xcconfig, config_swift, project_yml)
        return check(xc, sk, cs, py)

    def student(sk):
        return next(g for g in sk["subscriptionGroups"] if g["name"] == STUDENT_GROUP)["subscriptions"][0]

    def parent(sk):
        return next(g for g in sk["subscriptionGroups"] if g["name"] == PARENT_GROUP)["subscriptions"][0]

    def setting(sk, xc, cs, py, edit):
        edit(sk)
        return xc, cs, py

    cases = {
        "a prefix that is not the bundle ID": lambda sk, xc, cs, py: (
            xc.replace("TALLY_BUNDLE_ID_PREFIX = dev.tally-app", "TALLY_BUNDLE_ID_PREFIX = com.example"), cs, py),
        "Family Sharing on": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: student(s).update(familyShareable=True)),
        "the wrong price": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: student(s).update(displayPrice="4.99")),
        "no free trial": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: student(s).update(introductoryOffer=None)),
        "no offer code": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: student(s).update(codeOffers=[])),
        "no win-back offer": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: student(s).update(winbackOffers=[])),
        "a monthly period": lambda sk, xc, cs, py: setting(
            sk, xc, cs, py, lambda s: parent(s).update(recurringSubscriptionPeriod="P1M")),
        "the parent's price": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: parent(s).update(displayPrice="9.99")),
        "a suffix the app does not derive": lambda sk, xc, cs, py: (
            xc, cs.replace('parentAnnualSuffix = ".parent.annual"', 'parentAnnualSuffix = ".family.annual"'), py),
        "a third product": lambda sk, xc, cs, py: setting(
            sk, xc, cs, py, lambda s: s["products"].append({"productID": "dev.tally-app.tally.tip"})),
        "one group missing": lambda sk, xc, cs, py: setting(sk, xc, cs, py, lambda s: s["subscriptionGroups"].pop()),
        "the test target does not bundle it": lambda sk, xc, cs, py: (
            xc, cs, py.replace("path: Config/Products.storekit", "path: Config/Other.storekit")),
        "the scheme does not name it": lambda sk, xc, cs, py: (
            xc, cs, py.replace("storeKitConfiguration: Config/Products.storekit", "storeKitConfiguration: X.storekit")),
    }
    failures = 0
    for name, mutate in cases.items():
        errors = broken(mutate)
        status = "caught" if errors else "MISSED"
        failures += 0 if errors else 1
        print(f"STOREKIT self-test | {status} | {name}" + (f": {errors[0]}" if errors else ""))
    try:
        bundle_id("PRODUCT_BUNDLE_IDENTIFIER = x\n")
        print("STOREKIT self-test | MISSED | a missing prefix")
        failures += 1
    except InputError:
        print("STOREKIT self-test | caught | a missing prefix")
    print(f"STOREKIT self-test | {'PASS' if failures == 0 else 'FAIL'} | {len(cases) + 1 - failures} of {len(cases) + 1}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
