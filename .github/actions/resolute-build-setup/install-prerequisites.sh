#!/usr/bin/env bash
set -eux

# Idempotently prepare build prerequisites on the self-hosted Ubuntu Resolute
# runner. Runs at the start of every job. Trigger path: 
#      .github/workflows/resolute-build.yml 
#   -> .github/actions/resolute-build-setup/action.yml
#   -> install-prerequisites.sh
#
# Every install in the docker branches below is wrapped in set +e/ set -e so a
# repo failure can fall through to the next source instead of aborting.

# dockerd needs the overlay module for its default overlay2 driver
sudo modprobe overlay

# Install docker-ce from the official docker.com apt repo (fresh daemon plus
# buildx plugin).
install_docker_ce() {
  sudo apt-get update -qq
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
}

# Prefer the docker.com repo; if the runner cannot reach download.docker.com,
# remove the repo/key again and fall back to the Ubuntu archive packages
# (docker.io + docker-buildx).
if ! command -v docker >/dev/null 2>&1; then
  set +e
  install_docker_ce
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "docker-ce official repo failed, falling back to Ubuntu archive docker.io"
    sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
    sudo apt-get update -qq
    sudo apt-get install -y docker.io docker-buildx
  fi
# If docker already present, but the buildx plugin is missing...
# buildx is not used by the SONiC build itself (the build commands use plain
# `docker build`); this branch only keeps the plugin healthy as a convenience
# and is therefore best-effort: it warns but never aborts. Try the Ubuntu
# archive package first (simple, no repo setup), then the docker.com repo.
elif ! docker buildx version >/dev/null 2>&1; then
  echo 'docker present but buildx plugin missing; installing'
  set +e
  sudo apt-get update -qq
  sudo apt-get install -y docker-buildx
  rc=$?
  set -e
  if [ $rc -ne 0 ] || ! docker buildx version >/dev/null 2>&1; then
    echo 'Ubuntu docker-buildx unavailable; trying docker.com repo'
    set +e
    install_docker_ce
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
      echo 'WARN: docker-buildx-plugin install failed'
      sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
      sudo apt-get update -qq || true
    fi
  fi
fi

# Toolchain for the build (make/git), helper scripts (jq) and the jinja2 CLI
sudo apt-get install -y make git jq python3-pip
pip3 install --user --quiet jinjanator || pip3 install --user --quiet --break-system-packages jinjanator
echo "$HOME/.local/bin" >> "$GITHUB_PATH"

# Give the CI user access to dockerd
sudo gpasswd -a "$(id -un)" docker || true
sudo systemctl restart docker
sudo chmod a+rw /var/run/docker.sock

# Environment watermarks: fail loudly here (with a readable summary in the job
# log) instead of deep into the build.
docker version --format 'client={{.Client.Version}} server={{.Server.Version}}'
docker buildx version || echo 'WARN: buildx plugin missing'
j2 --version 2>/dev/null || jinjanate --version 2>/dev/null || echo 'WARN: j2/jinjanate missing'
docker ps >/dev/null && echo 'docker socket OK'
