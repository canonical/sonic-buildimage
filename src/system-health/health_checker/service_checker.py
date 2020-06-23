import subprocess
from .health_checker import HealthChecker
from . import utils


class ServiceChecker(HealthChecker):
    CHECK_MONIT_SERVICE_CMD = 'systemctl is-active monit.service'
    CHECK_CMD = 'monit summary -B'
    MIN_CHECK_CMD_LINES = 3
    EXPECT_STATUS_DICT = {
        'System': 'Running',
        'Process': 'Running',
        'Filesystem': 'Accessible'
    }

    def __init__(self):
        HealthChecker.__init__(self)

    def reset(self):
        self._info = {}

    def get_category(self):
        return 'Services'

    def check(self, config):
        self.reset()
        output = utils.run_command(ServiceChecker.CHECK_MONIT_SERVICE_CMD).strip()
        if output != 'active':
            self.set_object_not_ok('Service', 'monit', 'monit service is not running')
            return

        output = utils.run_command(ServiceChecker.CHECK_CMD)
        lines = output.splitlines()
        if not lines or len(lines) < ServiceChecker.MIN_CHECK_CMD_LINES:
            self.set_object_not_ok('Service', 'monit', 'output of \"monit summary -B\" is invalid or incompatible')
            return

        status_begin = lines[1].find('Status')
        type_begin = lines[1].find('Type')
        if status_begin < 0 or type_begin < 0:
            self.set_object_not_ok('Service', 'monit', 'output of \"monit summary -B\" is invalid or incompatible')
            return

        for line in lines[2:]:
            name = line[0:status_begin].strip()
            if config.ignore_services and name in config.ignore_services:
                continue
            status = line[status_begin:type_begin].strip()
            service_type = line[type_begin:].strip()
            expect_status = ServiceChecker.EXPECT_STATUS_DICT[service_type]
            if expect_status != status:
                self.set_object_not_ok(service_type, name, '{} is not {}'.format(name, expect_status))
            else:
                self.set_object_ok(service_type, name)
        return
