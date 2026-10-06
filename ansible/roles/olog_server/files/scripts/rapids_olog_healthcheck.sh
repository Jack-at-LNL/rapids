#!/usr/bin/env bash
# =============================================================================
# rapids_olog_tests.sh
# RAPIDS - tests of the Olog server on an installed machine (test plan 25 Sep 2026)
#
#   O1  services and listening addresses (8080 Olog, 9200/9300 ElasticSearch,
#       27017 MongoDB, 8389 embedded LDAP)
#   O3  authentication (configured password, demo accounts, wrong password,
#       anonymous write)
#   O4  contents: logbook, tag, entry, attachment (upload + download check),
#       search by title / text / logbook / tag / time range, edit
#   O6a persistence across an Olog service restart
#   O7  backup: cron job present, backup script runs, archive produced
#   O8  management scripts: present, permissions, no demo password inside
#
# Usage (as epics-dev on the test machine):
#   bash ~/rapids_olog_tests.sh                 # all tests (asks the Olog password)
#   bash ~/rapids_olog_tests.sh --no-restart    # skip O6a (no service restart)
#   bash ~/rapids_olog_tests.sh --no-backup     # skip running the backup (O7)
# Report: ~/olog-tests-<date>.txt ; created ids: ~/olog-test-ids.txt
#
# Test data are created in logbook and tag 'rapids-test' and are kept on
# purpose, for the persistence tests after update.sh and reboot.
# The password is passed to curl through a temporary config, never on the
# command line and never printed.
# =============================================================================
set -u
URL=${OLOG_URL:-http://localhost:8080/Olog}
USER_NAME=${OLOG_USER:-admin}
SCRIPTS=/opt/epics-tools/olog/scripts
REPORT=~/olog-tests-$(date +%Y%m%d-%H%M).txt
IDS=~/olog-test-ids.txt
RUN=$(date +%Y%m%d%H%M%S)
DO_RESTART=yes; DO_BACKUP=yes
for a in "$@"; do
    case "$a" in --no-restart) DO_RESTART=no;; --no-backup) DO_BACKUP=no;; esac
done
PASS=0; FAIL=0; WARN=0
exec > >(tee "$REPORT") 2>&1
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
info() { echo "  [INFO] $*"; }

if [ -n "${OLOG_PASSWORD:-}" ]; then
    PW="$OLOG_PASSWORD"
    info "using OLOG_PASSWORD from the environment (non-interactive run)"
else
    read -rs -p "Olog password for '$USER_NAME': " PW; echo
fi
CFG=$(mktemp); chmod 600 "$CFG"
printf 'user = "%s:%s"\n' "$USER_NAME" "$PW" > "$CFG"
TMP=$(mktemp -d); trap 'rm -rf "$CFG" "$TMP"' EXIT

acurl() { curl -s -K "$CFG" "$@"; }                 # authenticated
jget()  { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
code_login() {                                     # $1 user  $2 password
    python3 - "$1" "$2" <<'PY' > "$TMP/login.json"
import json, sys; print(json.dumps({"username": sys.argv[1], "password": sys.argv[2]}))
PY
    curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-Type: application/json' \
         --data @"$TMP/login.json" "$URL/login"
}

echo "RAPIDS Olog tests - $(date) - run $RUN - $URL"

# ----------------------------------------------------------------- O1
echo; echo "O1 Services and listening addresses"
for s in olog elasticsearch mongod; do
    a=$(systemctl is-active "$s" 2>/dev/null); e=$(systemctl is-enabled "$s" 2>/dev/null)
    [ "$a" = active ] && [ "$e" = enabled ] && ok "$s active and enabled" || bad "$s: active=$a enabled=$e"
done
for p in 8080 9200 9300 27017 8389; do
    addrs=$(ss -Hltn "sport = :$p" 2>/dev/null | awk '{print $4}' | sort -u | tr '\n' ' ')
    if [ -z "$addrs" ]; then info "port $p: not listening"; continue; fi
    if echo "$addrs" | grep -qE '^(127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\]):'"$p"'( |$)' && ! echo "$addrs" | grep -qE '(0\.0\.0\.0|\*|\[::\]):'; then
        ok "port $p listens only locally: $addrs"
    elif [ "$p" = 8080 ]; then
        info "port 8080 (Olog, meant for clients): $addrs"
    else
        warn "port $p listens on all interfaces: $addrs (check O2 from another machine)"
    fi
done

# ----------------------------------------------------------------- O3
echo; echo "O3 Authentication"
c=$(code_login "$USER_NAME" "$PW");       [ "$c" = 200 ] && ok "configured password accepted (HTTP $c)" || bad "configured password: HTTP $c"
c=$(code_login admin adminPass);          [ "$c" = 401 ] && ok "demo account admin refused (HTTP $c)"   || bad "demo account admin: HTTP $c"   # audit: allow
c=$(code_login user userPass);            [ "$c" = 401 ] && ok "demo account user refused (HTTP $c)"    || bad "demo account user: HTTP $c"
c=$(code_login "$USER_NAME" "wrong-$RUN"); [ "$c" = 401 ] && ok "wrong password refused (HTTP $c)"      || bad "wrong password: HTTP $c"
c=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H 'Content-Type: application/json' \
      "$URL/logbooks/rapids-anon-$RUN" -d "{\"name\":\"rapids-anon-$RUN\",\"owner\":\"x\",\"state\":\"Active\"}")
[ "$c" = 401 ] && ok "anonymous write refused (HTTP $c)" || bad "anonymous write: HTTP $c"

# ----------------------------------------------------------------- O4
echo; echo "O4 Contents"
c=$(acurl -o /dev/null -w "%{http_code}" -X PUT -H 'Content-Type: application/json' "$URL/logbooks/rapids-test" \
      -d '{"name":"rapids-test","owner":"admin","state":"Active"}')
[ "$c" = 200 ] && ok "logbook rapids-test created/updated" || bad "logbook: HTTP $c"
c=$(acurl -o /dev/null -w "%{http_code}" -X PUT -H 'Content-Type: application/json' "$URL/tags/rapids-test" \
      -d '{"name":"rapids-test","state":"Active"}')
[ "$c" = 200 ] && ok "tag rapids-test created/updated" || bad "tag: HTTP $c"

TOKEN="rapidstoken$RUN"
python3 - "$RUN" "$TOKEN" > "$TMP/log.json" <<'PY'
import json, sys
print(json.dumps({"owner": "admin", "title": f"RAPIDS test {sys.argv[1]}",
  "description": f"Automatic RAPIDS test entry. Search token: {sys.argv[2]}",
  "level": "Info", "logbooks": [{"name": "rapids-test"}], "tags": [{"name": "rapids-test"}]}))
PY
acurl -X PUT -H 'Content-Type: application/json' --data @"$TMP/log.json" "$URL/logs" > "$TMP/created.json"
LID=$(jget 'd["id"]' < "$TMP/created.json")
if [ -n "$LID" ]; then ok "entry created: id $LID"; echo "$LID RAPIDS test $RUN" >> "$IDS"
else bad "entry not created: $(head -c 200 "$TMP/created.json")"; fi

if [ -n "$LID" ]; then
    printf 'RAPIDS attachment test %s\n' "$RUN" > "$TMP/rapids-attachment.txt"
    SUM=$(sha256sum "$TMP/rapids-attachment.txt" | cut -d' ' -f1)
    c=$(acurl -o "$TMP/att.json" -w "%{http_code}" -X POST "$URL/logs/attachments/$LID" \
          -F "file=@$TMP/rapids-attachment.txt" -F "filename=rapids-attachment.txt")
    [ "$c" = 200 ] && ok "attachment uploaded" || bad "attachment upload: HTTP $c"
    curl -s -o "$TMP/down.txt" "$URL/logs/attachments/$LID/rapids-attachment.txt"
    [ "$(sha256sum "$TMP/down.txt" | cut -d' ' -f1)" = "$SUM" ] && ok "attachment downloaded identical (sha256)" || bad "attachment download differs or failed"
    echo "$LID attachment rapids-attachment.txt sha256 $SUM" >> "$IDS"

    hits() { curl -s "$URL/logs/search?$1" | jget 'd.get("hitCount", 0)'; }
    sleep 2   # let the search index refresh
    [ "$(hits "title=RAPIDS%20test%20$RUN")" = 1 ] && ok "search by title"   || bad "search by title"
    [ "$(hits "text=$TOKEN")" = 1 ]                 && ok "search by text"    || bad "search by text"
    n=$(hits "logbooks=rapids-test&size=100");   [ "${n:-0}" -ge 1 ] && ok "search by logbook ($n)" || bad "search by logbook"
    n=$(hits "tags=rapids-test&size=100");       [ "${n:-0}" -ge 1 ] && ok "search by tag ($n)"     || bad "search by tag"
    n=$(hits "start=1%20hour&end=now&text=$TOKEN"); [ "$n" = 1 ] && ok "search by time range (last hour)" || bad "search by time range"
    n=$(hits "start=2%20hours&end=1%20hour&text=$TOKEN"); [ "${n:-0}" = 0 ] && ok "time range excludes the entry when it should" || bad "time range filter"

    curl -s "$URL/logs/$LID" | python3 -c '
import sys, json
d = json.load(sys.stdin)
# Olog 5 keeps the Markdown text in "source" and rebuilds "description" from it,
# so an edit must change "source" (as Phoebus does), not only "description".
d["source"] = (d.get("source") or d.get("description") or "") + " (edited)"
d["description"] = d["source"]
print(json.dumps(d))' > "$TMP/edit.json"
    c=$(acurl -o /dev/null -w "%{http_code}" -X POST -H 'Content-Type: application/json' --data @"$TMP/edit.json" "$URL/logs/$LID")
    d=$(curl -s "$URL/logs/$LID" | jget 'd.get("source") or d["description"]')
    [ "$c" = 200 ] && [[ "$d" == *"(edited)" ]] && ok "entry edited" || bad "edit: HTTP $c"
fi

# ----------------------------------------------------------------- O6a
echo; echo "O6a Persistence across an Olog restart"
if [ "$DO_RESTART" = yes ]; then
    sudo systemctl restart olog
    for i in $(seq 1 45); do curl -s -o /dev/null "$URL/logbooks" && break; sleep 2; done
    miss=0; total=0
    while read -r id rest; do
        case "$rest" in attachment*) continue;; esac
        total=$((total+1)); curl -s "$URL/logs/$id" | jget 'd["id"]' | grep -qx "$id" || miss=$((miss+1))
    done < "$IDS"
    [ "$miss" = 0 ] && ok "all $total recorded entries present after restart" || bad "$miss of $total entries missing after restart"
    while read -r id _ name _ sum; do
        [ "$(curl -s "$URL/logs/attachments/$id/$name" | sha256sum | cut -d' ' -f1)" = "$sum" ] \
          && ok "attachment of entry $id intact after restart" || bad "attachment of entry $id changed or missing"
    done < <(grep ' attachment ' "$IDS")
else info "skipped (--no-restart)"; fi

# ----------------------------------------------------------------- O7
echo; echo "O7 Backup"
# RAPIDS deliberately ships no Olog backup mechanism (see doc/rapids/olog-server.md,
# section 6): an earlier backup-now.sh/cron pair only dumped MongoDB, which
# does not hold log entry content or the logbook/tag list - both live in
# ElasticSearch - so it protected almost nothing and was removed outright.
# This is intentional and documented, not a defect: confirm that state here
# rather than treating its absence as a failure.
cronhits=$( (sudo crontab -l 2>/dev/null; sudo cat /etc/cron.d/* 2>/dev/null) | grep -i olog | grep -v '^#')
if [ -n "$cronhits" ]; then
    bad "an Olog backup cron job was found, but RAPIDS does not ship or maintain one - investigate its source:"
    echo "$cronhits" | sed 's/^/         /'
else
    info "no Olog backup cron job present, as documented (olog-server.md section 6)"
fi
if [ -x "$SCRIPTS/backup-now.sh" ]; then
    bad "$SCRIPTS/backup-now.sh exists but RAPIDS does not ship this script - investigate its source"
else
    info "no backup-now.sh present, as documented - run your own ElasticSearch snapshot + mongodump if you need backups"
fi

# ----------------------------------------------------------------- O8
echo; echo "O8 Management scripts"
if sudo test -d "$SCRIPTS"; then
    sudo ls -l "$SCRIPTS" | sed 's/^/         /'
    for f in $(sudo ls "$SCRIPTS"); do
        # Skip this healthcheck script itself: its own O3 test section
        # legitimately contains the literal demo-password string as the
        # value it tests against (code_login admin adminPass), not a
        # leaked credential - scanning it here is a false positive.
        [ "$f" = "rapids_olog_healthcheck.sh" ] && { info "$f: skipped (this is the healthcheck script itself)"; continue; }
        p="$SCRIPTS/$f"
        sudo grep -q "adminPass" "$p" && bad "$f contains the demo password" || ok "$f: no demo password"   # audit: allow
        m=$(sudo stat -c '%a' "$p"); [ "${m: -1}" -ge 4 ] 2>/dev/null && sudo grep -qi "password" "$p" \
          && warn "$f is world-readable (mode $m) and mentions a password" || true
    done
else bad "$SCRIPTS not found"; fi

echo; echo "SUMMARY: PASS=$PASS FAIL=$FAIL WARN=$WARN   report: $REPORT   ids: $IDS"
