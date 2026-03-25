import configparser
import tempfile
import yaml

def main() -> int:
    config = configparser.ConfigParser()
    with open('supervisord.conf', 'r', encoding='utf-8') as f:
        config.read_file(f)

    services = {}
    for section in config.sections():
        if section.startswith('program:isc-dhcpv4') or section.startswith('program:dhcpmon-'):
            svc_name = section[8:]
            svc = {'command': config.get(section, 'command'), 'override': 'replace', 'startup': 'enabled'}
            services[svc_name] = svc

    with tempfile.NamedTemporaryFile(prefix='pebble-layer-', suffix='.yaml', delete=False, mode='w', encoding='utf-8') as f:
        output = {'services': services}
        yaml.safe_dump(output, f, width=float("inf"))
        temp_path = f.name

    print(temp_path)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
