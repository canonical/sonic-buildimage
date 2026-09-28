set -eux
sudo modprobe overlay
sudo modprobe ip_tables
echo ip_tables | sudo tee /etc/modules-load.d/ip_tables.conf >/dev/null
sudo apt-get update -qq
sudo apt-get install -y ca-certificates curl gnupg make git jq python3-pip python3-venv
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu resolute stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
pip3 install --user --quiet --break-system-packages jinjanator
sudo gpasswd -a ubuntu docker
sudo systemctl enable --now docker
sudo chmod a+rw /var/run/docker.sock
# AppArmor gs override (bash build writes bash.pdf via gs)
if [ -f /etc/apparmor.d/gs ]; then
  printf 'owner file rw /sonic/**,\nowner file rw /var/*/**,\n' | sudo tee /etc/apparmor.d/local/gs >/dev/null
  sudo apparmor_parser -r /etc/apparmor.d/gs
fi
sudo mkdir -p /var/cache/sonic/artifacts/vcache && sudo chmod -R 777 /var/cache/sonic/artifacts
docker version --format 'client={{.Client.Version}} server={{.Server.Version}}'
~/.local/bin/j2 --version || ~/.local/bin/jinjanate --version
lsmod | grep -E '^(ip_tables|overlay)'
echo SETUP_DONE
