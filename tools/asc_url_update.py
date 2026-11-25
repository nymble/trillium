#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Set public URLs for Trillium Sense through the App Store Connect API.

Updates only privacy, support, and marketing URLs. Never submits a version
or build, never changes other fields, and never prints key material.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (PEM or base64), ASC_APP_ID.
"""
import base64, json, os, sys, urllib.error, urllib.request
import jwt

API = "https://api.appstoreconnect.apple.com"

PRIVACY = "https://trillium.music/privacy/"
SUPPORT = "https://trillium.music/support/"
MARKETING = "https://trillium.music/"

PLATFORMS = ("IOS", "MAC_OS")
LOCKED_STATES = frozenset({
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PENDING_CONTRACT",
    "PROCESSING_FOR_APP_STORE",
    "READY_FOR_SALE",
    "PREORDER_READY_FOR_SALE",
    "REMOVED_FROM_SALE",
    "DEVELOPER_REMOVED_FROM_SALE",
    "REPLACED_WITH_NEW_VERSION",
    "WAITING_FOR_EXPORT_COMPLIANCE",
})

# HTTP / API errors that mean the resource cannot be edited in its current state.
LOCKED_MARKERS = (
    "current state",
    "not allowed",
    "cannot be updated",
    "cannot be modified",
    "state is not",
    "in review",
    "waiting for review",
    "locked",
)


def key():
    raw = os.environ["ASC_KEY_P8"].strip()
    if "BEGIN" not in raw:
        raw = base64.b64decode(raw).decode()
    return raw


def token():
    now = int(__import__("time").time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100,
         "aud": "appstoreconnect-v1"},
        key(), algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


TOK = token()
RESULTS = []  # list of dicts for the end-of-run summary


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + TOK, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return r.status, (json.loads(data) if data else {})
    except urllib.error.HTTPError as e:
        txt = e.read().decode(errors="replace")
        try:
            parsed = json.loads(txt)
            errs = parsed.get("errors", [])
        except Exception:
            errs = [{"detail": txt[:300]}]
        # Never echo request headers or token material.
        return e.code, {"errors": [
            {"status": x.get("status"), "code": x.get("code"),
             "title": x.get("title"), "detail": x.get("detail")}
            for x in errs
        ]}


def paginate(path):
    items, included = [], []
    while path:
        s, body = call("GET", path)
        if s != 200:
            return s, body, items, included
        items.extend(body.get("data") or [])
        included.extend(body.get("included") or [])
        nxt = (body.get("links") or {}).get("next")
        if nxt and nxt.startswith(API):
            path = nxt[len(API):]
        elif nxt and nxt.startswith("/"):
            path = nxt
        else:
            path = None
    return 200, {}, items, included


def state_of(attrs):
    if not attrs:
        return None
    return attrs.get("appVersionState") or attrs.get("appStoreState") or attrs.get("state")


def is_locked_state(state):
    return state in LOCKED_STATES if state else False


def error_looks_locked(err_body):
    blob = json.dumps(err_body.get("errors", [])).lower()
    return any(m in blob for m in LOCKED_MARKERS)


def record(resource, target, fields, status, detail, values=None):
    row = {
        "resource": resource,
        "target": target,
        "fields": fields,
        "status": status,
        "detail": detail,
        "values": values or {},
    }
    RESULTS.append(row)
    val = ""
    if values:
        val = " " + " ".join(f"{k}={v!r}" for k, v in values.items())
    print(f"  [{status}] {resource} {target}: {detail}{val}", flush=True)


def get_resource(typ, rid):
    # typ is the JSON:API type, used as the collection path.
    s, body = call("GET", f"/v1/{typ}/{rid}")
    return s, body


def patch_and_confirm(typ, rid, attrs, target, field_names):
    body = {"data": {"type": typ, "id": rid, "attributes": attrs}}
    s, resp = call("PATCH", f"/v1/{typ}/{rid}", body)
    if s in (200, 201):
        after = (resp.get("data") or {}).get("attributes") or {}
        # Re-GET so the log is the persisted value, not only the PATCH echo.
        gs, got = get_resource(typ, rid)
        if gs == 200:
            after = (got.get("data") or {}).get("attributes") or after
        values = {k: after.get(k) for k in field_names}
        record(typ, target, field_names, "SET", f"PATCH {s}", values)
        return "SET"
    if error_looks_locked(resp) or s in (403, 409):
        record(typ, target, field_names, "SKIPPED",
               f"locked or not editable (HTTP {s}) {resp.get('errors')}", {})
        return "SKIPPED"
    record(typ, target, field_names, "FAILED",
           f"HTTP {s} {resp.get('errors')}", {})
    return "FAILED"


def update_app_info_localizations():
    print("== appInfoLocalizations (privacyPolicyUrl)")
    s, _, infos, _ = paginate(f"/v1/apps/{app}/appInfos?limit=50")
    if s != 200:
        record("appInfos", "list", ["privacyPolicyUrl"], "FAILED",
               f"GET appInfos HTTP {s}", {})
        return
    if not infos:
        record("appInfos", "list", ["privacyPolicyUrl"], "SKIPPED",
               "no appInfos returned", {})
        return
    for info in infos:
        st = state_of(info.get("attributes") or {})
        iid = info["id"]
        label = f"appInfo {iid} state={st}"
        ls, locs, localizations, _ = paginate(
            f"/v1/appInfos/{iid}/appInfoLocalizations?limit=50")
        if ls != 200:
            record("appInfoLocalizations", label, ["privacyPolicyUrl"], "FAILED",
                   f"GET localizations HTTP {ls} {locs.get('errors') if isinstance(locs, dict) else locs}", {})
            continue
        if not localizations:
            record("appInfoLocalizations", label, ["privacyPolicyUrl"], "SKIPPED",
                   "no localizations", {})
            continue
        if is_locked_state(st):
            for loc in localizations:
                a = loc.get("attributes") or {}
                record("appInfoLocalizations",
                       f"{label} locale={a.get('locale')} id={loc['id']}",
                       ["privacyPolicyUrl"], "SKIPPED",
                       f"appInfo state {st} is not editable",
                       {"privacyPolicyUrl": a.get("privacyPolicyUrl")})
            continue
        for loc in localizations:
            a = loc.get("attributes") or {}
            target = f"{label} locale={a.get('locale')} id={loc['id']}"
            print(f"  before {target} privacyPolicyUrl={a.get('privacyPolicyUrl')!r}", flush=True)
            patch_and_confirm("appInfoLocalizations", loc["id"],
                              {"privacyPolicyUrl": PRIVACY},
                              target, ["privacyPolicyUrl"])


def update_version_localizations():
    print("== appStoreVersionLocalizations (supportUrl, marketingUrl)")
    for plat in PLATFORMS:
        path = (f"/v1/apps/{app}/appStoreVersions"
                f"?filter[platform]={plat}&limit=50"
                "&fields[appStoreVersions]=platform,versionString,appStoreState,appVersionState")
        s, err, versions, _ = paginate(path)
        if s != 200:
            record("appStoreVersions", plat, ["supportUrl", "marketingUrl"], "FAILED",
                   f"GET versions HTTP {s} {err.get('errors') if isinstance(err, dict) else err}", {})
            continue
        if not versions:
            record("appStoreVersions", plat, ["supportUrl", "marketingUrl"], "SKIPPED",
                   "no versions for this platform", {})
            continue
        for ver in versions:
            a = ver.get("attributes") or {}
            st = state_of(a)
            label = (f"{a.get('platform') or plat} {a.get('versionString')} "
                     f"state={st} id={ver['id']}")
            ls, locs, localizations, _ = paginate(
                f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")
            if ls != 200:
                record("appStoreVersionLocalizations", label,
                       ["supportUrl", "marketingUrl"], "FAILED",
                       f"GET localizations HTTP {ls} {locs.get('errors') if isinstance(locs, dict) else locs}", {})
                continue
            if not localizations:
                record("appStoreVersionLocalizations", label,
                       ["supportUrl", "marketingUrl"], "SKIPPED",
                       "no localizations", {})
                continue
            if is_locked_state(st):
                for loc in localizations:
                    la = loc.get("attributes") or {}
                    record("appStoreVersionLocalizations",
                           f"{label} locale={la.get('locale')} id={loc['id']}",
                           ["supportUrl", "marketingUrl"], "SKIPPED",
                           f"version state {st} is not editable",
                           {"supportUrl": la.get("supportUrl"),
                            "marketingUrl": la.get("marketingUrl")})
                continue
            for loc in localizations:
                la = loc.get("attributes") or {}
                target = f"{label} locale={la.get('locale')} id={loc['id']}"
                print(f"  before {target} supportUrl={la.get('supportUrl')!r} "
                      f"marketingUrl={la.get('marketingUrl')!r}", flush=True)
                patch_and_confirm(
                    "appStoreVersionLocalizations", loc["id"],
                    {"supportUrl": SUPPORT, "marketingUrl": MARKETING},
                    target, ["supportUrl", "marketingUrl"],
                )


def update_beta_localizations():
    print("== betaAppLocalizations (privacyPolicyUrl, marketingUrl; feedbackEmail unchanged)")
    s, err, locs, _ = paginate(f"/v1/apps/{app}/betaAppLocalizations?limit=50")
    if s != 200:
        record("betaAppLocalizations", "list",
               ["privacyPolicyUrl", "marketingUrl"], "FAILED",
               f"GET HTTP {s} {err.get('errors') if isinstance(err, dict) else err}", {})
        return
    if not locs:
        record("betaAppLocalizations", "list",
               ["privacyPolicyUrl", "marketingUrl"], "SKIPPED",
               "no betaAppLocalizations", {})
        return
    for loc in locs:
        a = loc.get("attributes") or {}
        # Do not print feedbackEmail (Actions logs may be public).
        target = f"locale={a.get('locale')} id={loc['id']}"
        print(f"  before {target} privacyPolicyUrl={a.get('privacyPolicyUrl')!r} "
              f"marketingUrl={a.get('marketingUrl')!r}", flush=True)
        patch_and_confirm(
            "betaAppLocalizations", loc["id"],
            {"privacyPolicyUrl": PRIVACY, "marketingUrl": MARKETING},
            target, ["privacyPolicyUrl", "marketingUrl"],
        )


def main():
    print(f"ASC URL update for app {app}")
    print(f"  privacyPolicyUrl -> {PRIVACY}")
    print(f"  supportUrl       -> {SUPPORT}")
    print(f"  marketingUrl     -> {MARKETING}")
    update_app_info_localizations()
    update_version_localizations()
    update_beta_localizations()
    print("== Summary")
    counts = {"SET": 0, "SKIPPED": 0, "FAILED": 0}
    for row in RESULTS:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
        print(f"  {row['status']:7} {row['resource']} | {row['target']} | "
              f"{row['detail']} | {row['values']}", flush=True)
    print(f"== Totals set={counts['SET']} skipped={counts['SKIPPED']} failed={counts['FAILED']}")
    if counts["FAILED"]:
        sys.exit(1)


if __name__ == "__main__":
    missing = [n for n in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8", "ASC_APP_ID")
               if not os.environ.get(n)]
    if missing:
        # Names only, never values.
        print("missing env:", ", ".join(missing))
        sys.exit(1)
    app = os.environ["ASC_APP_ID"]
    main()
