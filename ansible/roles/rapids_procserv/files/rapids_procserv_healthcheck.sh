#!/usr/bin/env bash
# =============================================================================
# rapids_procserv_healthcheck.sh
# RAPIDS - tests of the procServ/manage-procs installation on this machine
#
#   P1  procServ and manage-procs installed, correct version, correctly
#       resolvable (the PATH/PYTHONPATH issues this install is known to hit)
#   P2  the systemd generator is correctly symlinked and producing units
#   P3  end-to-end: a transient sine-wave self-check instance is added,
#       confirmed reachable over the network via caget, then stopped and
#       disabled - proves the whole chain genuinely works, not just that
#       the binaries exist
#   P4  read-only report on any operator-declared instances already present
#       under /etc/procServ.d/*.conf (this script never starts, stops, or
#       modifies them - see doc/rapids/procserv-manual.md)
#
# Usage (as the epics-dev / operator user; installed by RAPIDS at
# /opt/epics-tools/procserv/scripts/rapids_procserv_healthcheck.sh, but
# safe to run from any location, e.g. after copying it to your home dir):
#   bash rapids_procserv_healthcheck.sh
#   PROCSERV_SELFCHECK_PORT=4099 bash rapids_procserv_healthcheck.sh   # avoid a port already in use
#
# Recognized environment variables (all optional):
#   RAPIDS_PROJECT_NAME      self-check PV prefix (default: rapids)
#   RAPIDS_INSTANCE_NAME     self-check PV prefix (default: vm)
#   PROCSERV_PREFIX          procServ/manage-procs install prefix (default: /usr/local)
#   PROCSERV_SELFCHECK_PORT  telnet port for the self-check instance (default: 4051)
#   PROCSERV_SELFCHECK_CA_PORT  dedicated Channel Access server port for the
#                            self-check IOC, kept clear of the EPICS default
#                            (5064) and of anything else already running on
#                            this host (default: 5078; beacon port is this+1)
#   PROCSERV_SELFCHECK_DIR   self-check working directory (default: /opt/epics-tools/procserv/selfcheck)
# Report: ~/rapids-selfchecks/procserv-tests-<date>.txt
# =============================================================================
set -u
PREFIX=${PROCSERV_PREFIX:-/usr/local}
PORT=${PROCSERV_SELFCHECK_PORT:-4051}
PROJECT=${RAPIDS_PROJECT_NAME:-rapids}
INSTANCE=${RAPIDS_INSTANCE_NAME:-vm}
SELFCHECK_DIR="${RAPIDS_SELFCHECK_DIR:-$HOME/rapids-selfchecks}"
mkdir -p "$SELFCHECK_DIR" 2>/dev/null
REPORT="$SELFCHECK_DIR/procserv-tests-$(date +%Y%m%d-%H%M).txt"
PASS=0; FAIL=0; WARN=0
exec > >(tee "$REPORT") 2>&1
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
info() { echo "  [INFO] $*"; }

export PATH="$PREFIX/bin:$PATH"
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
export PYTHONPATH="$PREFIX/lib/python${PYVER}/site-packages"

echo "RAPIDS procServ tests - $(date) - prefix $PREFIX"

# ----------------------------------------------------------------- P1
echo; echo "P1 procServ / manage-procs installation"
if command -v procServ >/dev/null 2>&1; then
    v=$(procServ --version 2>&1)
    ok "procServ found: $v"
else bad "procServ not found on PATH (checked $PREFIX/bin)"; fi

if command -v manage-procs >/dev/null 2>&1; then
    ok "manage-procs found at $(command -v manage-procs)"
else bad "manage-procs not found on PATH (checked $PREFIX/bin)"; fi

launcher=$(python3 -c "from procServUtils.generator import which; print(which('procServ-launcher'))" 2>/dev/null)
if [ -n "$launcher" ] && [ "$launcher" != "None" ]; then
    ok "procServ-launcher resolvable via PATH: $launcher"
else bad "procServ-launcher NOT resolvable (manage-procs-generated systemd units would show ExecStart=None)"; fi

rpm -q procServ >/dev/null 2>&1 && warn "a package-manager procServ is also installed (check 'which procServ' for PATH ambiguity)"

# ----------------------------------------------------------------- P2
echo; echo "P2 systemd generator"
gen=/usr/lib/systemd/system-generators/systemd-procserv-generator-system
if [ -L "$gen" ] || [ -e "$gen" ]; then
    ok "generator present at $gen"
    [ -L "$gen" ] && info "-> $(readlink -f "$gen")"
else bad "generator missing at $gen - instances will not survive 'systemctl enable'"; fi

sudo mkdir -p /etc/procServ.d 2>/dev/null
[ -d /etc/procServ.d ] && ok "/etc/procServ.d exists" || bad "/etc/procServ.d missing"

# ----------------------------------------------------------------- P3
echo; echo "P3 End-to-end self-check (sine wave, transient)"
NAME=selfcheck
PVPREFIX="${PROJECT}:${INSTANCE}:procserv-selfcheck"
# RAPIDS's own diagnostic artifact - deliberately NOT placed under
# rapids_procserv_iocs_dir (/opt/epics/iocs by default), which is
# reserved for the operator's own production IOCs.
WORKDIR="${PROCSERV_SELFCHECK_DIR:-/opt/epics-tools/procserv/selfcheck}"
if ! sudo mkdir -p "$WORKDIR" || ! sudo chown "$(whoami):$(id -gn)" "$WORKDIR"; then
    bad "could not create/own $WORKDIR - skipping P3"
    WORKDIR=""
fi
if [ -n "$WORKDIR" ]; then
cat > "$WORKDIR/selfcheck.db" << DBEOF
record(calc, "${PVPREFIX}:angle") {
    field(SCAN, "1 second")
    field(CALC, "A+0.3")
    field(INPA, "${PVPREFIX}:angle")
}
record(calc, "${PVPREFIX}:sine") {
    field(SCAN, "1 second")
    field(CALC, "SIN(A)")
    field(INPA, "${PVPREFIX}:angle")
}
DBEOF
fi

SOFTIOC=$(bash -l -c 'command -v softIocPVX' 2>/dev/null)
CAGET=$(bash -l -c 'command -v caget' 2>/dev/null)
if [ -z "$WORKDIR" ]; then
    : # already reported above
elif [ -z "$SOFTIOC" ]; then
    bad "softIocPVX not found (run in a login shell: bash -l); skipping P3"
elif [ -z "$CAGET" ]; then
    bad "caget not found, even via a login shell (checked EPICS Base's bin dir on PATH); skipping P3"
else
    # Give this throwaway self-check IOC its own dedicated Channel Access
    # port pair, well clear of the EPICS default (5064/5065) and of any
    # other IOC that may already be running on this host (e.g. a leftover
    # Archiver test IOC) - so this self-check never depends on being the
    # only CA server around.
    CAPORT="${PROCSERV_SELFCHECK_CA_PORT:-5078}"
    BEACONPORT="$((CAPORT + 1))"

    {
        echo '#!/usr/bin/env bash'
        echo "export EPICS_CAS_SERVER_PORT=$CAPORT"
        echo "export EPICS_CAS_BEACON_PORT=$BEACONPORT"
        echo "exec \"$SOFTIOC\" -S -d selfcheck.db"
    } > "$WORKDIR/run-selfcheck.sh"
    chmod +x "$WORKDIR/run-selfcheck.sh"

    sudo env PATH="$PATH" PYTHONPATH="$PYTHONPATH" manage-procs --system remove "$NAME" -f >/dev/null 2>&1
    addout=$(sudo env PATH="$PATH" PYTHONPATH="$PYTHONPATH" manage-procs --system add -C "$WORKDIR" -P "$PORT" \
         -U "$(whoami)" -G "$(id -gn)" -A "$NAME" \
         "$WORKDIR/run-selfcheck.sh" 2>&1)
    if [ $? -eq 0 ]; then
        ok "manage-procs add succeeded (instance $NAME, port $PORT)"
    else
        bad "manage-procs add failed:"
        echo "$addout" | sed 's/^/         /'
    fi

    unit="/etc/procServ.d/procserv-${NAME}.service"
    if [ -f "$unit" ] && ! grep -q "ExecStart=None" "$unit" 2>/dev/null; then
        ok "generated unit resolved a real ExecStart"
    else
        bad "generated unit missing or ExecStart=None (procServ-launcher not resolved at add-time)"
    fi

    ready=no
    for i in $(seq 1 8); do
        [ "$(systemctl is-active "procserv-${NAME}" 2>/dev/null)" = "active" ] && { ready=yes; break; }
        sleep 2
    done
    [ "$ready" = yes ] && ok "service active" || bad "service did not reach active state"

    val=""
    caerr=""
    for i in $(seq 1 8); do
        val=$(EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_ADDR_LIST="127.0.0.1" EPICS_CA_SERVER_PORT="$CAPORT" \
              "$CAGET" -t -w 3 "${PVPREFIX}:sine" 2>&1)
        rc=$?
        [ $rc -eq 0 ] && [ -n "$val" ] && break
        caerr="$val"; val=""
        sleep 3
    done
    if [ -n "$val" ]; then
        ok "self-check PV reachable: ${PVPREFIX}:sine = $val (dedicated CA port $CAPORT)"
    else
        bad "self-check PV not reachable via caget (dedicated CA port $CAPORT)"
        [ -n "$caerr" ] && echo "         $caerr"
    fi

    sudo systemctl stop "procserv-${NAME}" 2>/dev/null
    sudo systemctl disable "procserv-${NAME}" 2>/dev/null
    info "self-check instance stopped and disabled (unit kept as reference)"
fi

# ----------------------------------------------------------------- P4
echo; echo "P4 Operator-declared instances (read-only report)"
confs=$(sudo find /etc/procServ.d -maxdepth 1 -name '*.conf' 2>/dev/null)
if [ -z "$confs" ]; then
    info "no operator-declared instances found under /etc/procServ.d"
else
    for c in $confs; do
        inst=$(basename "$c" .conf)
        st=$(systemctl is-active "procserv-${inst}" 2>/dev/null)
        en=$(systemctl is-enabled "procserv-${inst}" 2>/dev/null)
        if [ "$inst" = "$NAME" ]; then
            info "$inst: active=$st enabled=$en  ($c)  <- this is P3's own self-check instance, listed here for reference, not a separate production IOC"
        else
            info "$inst: active=$st enabled=$en  ($c)"
        fi
    done
fi

echo; echo "SUMMARY: PASS=$PASS FAIL=$FAIL WARN=$WARN   report: $REPORT"
