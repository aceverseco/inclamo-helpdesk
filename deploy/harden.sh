#!/usr/bin/env bash
# The baseline of a machine that runs an instance (Debian or Ubuntu):
#   - ssh with keys only, no root login;
#   - a firewall that lets in ports 22, 80 and 443 and nothing else;
#   - security updates installed automatically;
#   - every container's log bounded in size and number of files.
# Safe to run again: each step leaves a machine that already has it as it is.
#
#   sudo deploy/harden.sh
#
# Run it before deploy/install.sh, from a session of a user that signs in
# with an ssh key and may use sudo: after it, root and passwords cannot sign
# in. It refuses when no such user exists. Docker's published ports bypass
# this firewall, which is why the stack publishes 80 and 443 only.
#
# What it cannot show from inside (a password login refused, the ports seen
# from the internet) is in the checklist of the install guide.
set -euo pipefail
case $- in *x*) set +x ;; esac

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

[ $# -eq 0 ] || die 'usage: deploy/harden.sh'
[ "$(id -u)" = 0 ] || die 'run this as root (sudo)'
command -v apt-get > /dev/null 2>&1 || die 'this script knows Debian and Ubuntu only (apt-get was not found)'
command -v sshd > /dev/null 2>&1 || die 'sshd was not found on this machine'

# --- somebody can still sign in afterwards -----------------------------------

key_user=''
while IFS=: read -r user _ uid _ _ home _; do
  [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ] || continue
  [ -s "$home/.ssh/authorized_keys" ] || continue
  id -nG "$user" | tr ' ' '\n' | grep -q -x -E 'sudo|wheel|admin' || continue
  key_user=$user
  break
done < /etc/passwd
[ -n "$key_user" ] || die 'no user other than root has both an ssh key (~/.ssh/authorized_keys) and sudo: closing root and password logins would lock this machine. Make such a user first. Nothing was changed.'

# --- packages ----------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive
packages=''
for package in ufw unattended-upgrades; do
  dpkg -s "$package" > /dev/null 2>&1 || packages="$packages $package"
done
if [ -n "$packages" ]; then
  say "installing$packages"
  apt-get update > /dev/null
  # shellcheck disable=SC2086
  apt-get install -y --no-install-recommends $packages > /dev/null
fi

# --- ssh: keys only, no root -------------------------------------------------

# sshd keeps the first value it reads, and the files of sshd_config.d are read
# in the order of their names: 00- comes before what an image or cloud-init
# put there.
ssh_file=/etc/ssh/sshd_config.d/00-inclamo-helpdesk.conf
ssh_wanted='# Written by deploy/harden.sh of the Inclamo Helpdesk.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no'
mkdir -p /etc/ssh/sshd_config.d
if [ "$(cat "$ssh_file" 2> /dev/null || true)" != "$ssh_wanted" ]; then
  printf '%s\n' "$ssh_wanted" > "$ssh_file"
  chmod 644 "$ssh_file"
fi
sshd -t || { rm -f "$ssh_file"; die 'sshd refuses the new configuration; it was taken back and nothing else was changed'; }
effective=$(sshd -T 2> /dev/null | grep -i -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication) ' | sort | tr '\n' ' ')
case $effective in
  'kbdinteractiveauthentication no passwordauthentication no permitrootlogin no ') ;;
  *)
    rm -f "$ssh_file"
    die "sshd does not take its settings from /etc/ssh/sshd_config.d (it reports: $effective). Set PasswordAuthentication no and PermitRootLogin no in /etc/ssh/sshd_config by hand. The file was taken back."
    ;;
esac
systemctl reload ssh 2> /dev/null || systemctl reload sshd 2> /dev/null || die 'sshd could not be reloaded'
say "ssh: keys only, no root login (checked: $key_user has a key and sudo)"

# --- firewall: 22, 80, 443 ---------------------------------------------------

ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
for port in 22 80 443; do
  ufw allow "$port/tcp" > /dev/null
done
# A rule this script does not know stays visible to the operator, not removed.
others=$(ufw show added 2> /dev/null | grep '^ufw ' | grep -v -x -E 'ufw allow (22|80|443)/tcp' || true)
ufw --force enable > /dev/null
say 'firewall: incoming 22, 80 and 443 only'
[ -z "$others" ] || printf 'firewall: other rules exist and were left in place, review them:\n%s\n' "$others" >&2

# --- security updates --------------------------------------------------------

auto_file=/etc/apt/apt.conf.d/20auto-upgrades
auto_wanted='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
if [ "$(cat "$auto_file" 2> /dev/null || true)" != "$auto_wanted" ]; then
  printf '%s\n' "$auto_wanted" > "$auto_file"
fi
systemctl enable --now unattended-upgrades > /dev/null 2>&1 || true
say 'security updates: installed automatically'

# --- container logs ----------------------------------------------------------

# Every container made from now on logs to json-file with these limits. The
# stack's compose file sets the same limits itself, so they hold even where
# this file could not be written.
daemon_file=/etc/docker/daemon.json
mkdir -p /etc/docker
if [ ! -s "$daemon_file" ]; then
  printf '%s\n' '{' '  "log-driver": "json-file",' '  "log-opts": { "max-size": "10m", "max-file": "5" }' '}' > "$daemon_file"
  changed=1
elif command -v python3 > /dev/null 2>&1; then
  changed=$(python3 - "$daemon_file" <<'PYTHON'
import json, sys
path = sys.argv[1]
with open(path) as handle:
    config = json.load(handle)
wanted = dict(config)
wanted["log-driver"] = "json-file"
wanted["log-opts"] = {**config.get("log-opts", {}), "max-size": "10m", "max-file": "5"}
if wanted == config:
    print(0)
else:
    with open(path, "w") as handle:
        json.dump(wanted, handle, indent=2)
        handle.write("\n")
    print(1)
PYTHON
  ) || die "$daemon_file is not valid JSON; set log-driver json-file with max-size and max-file in it by hand"
else
  die "$daemon_file exists and python3 is not here to merge it: set \"log-driver\": \"json-file\" and \"log-opts\": {\"max-size\": \"10m\", \"max-file\": \"5\"} in it by hand"
fi
if [ "$changed" = 1 ] && command -v docker > /dev/null 2>&1; then
  if [ -n "$(docker ps --quiet 2> /dev/null)" ]; then
    printf '%s\n' "container logs: $daemon_file is written, but containers are running and Docker was not restarted. Restart it yourself (systemctl restart docker) when a short stop is acceptable." >&2
  else
    systemctl restart docker
  fi
fi
say 'container logs: json-file, 10 MB a file, 5 files'
