from .health_checker import HealthChecker
from .utils import run_command


class ExternalChecker(HealthChecker):
    def __init__(self, cmd):
        HealthChecker.__init__(self)
        self._cmd = cmd
        self._category = None

    def reset(self):
        self._category = None
        self._error_info = None

    def get_category(self):
        return self._category

    def check(self, config):
        self.reset()
        output = run_command(self._cmd)
        if not output:
            return

        lines = output.splitlines()
        if not lines:
            return

        self._category = lines[0]
        if len(lines) > 1:
            self._error_info = {}
            for line in lines[1:]:
                line = line.strip()
                if not line:
                    continue
                pos = line.find(':')
                if pos == -1:
                    continue
                obj_name = line[:pos]
                error_msg = line[pos:]
                self._error_info[obj_name] = error_msg
        return

    def __str__(self):
        return 'ExternalChecker - {}'.format(self._cmd)
