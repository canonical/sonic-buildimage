import os
import pytest
import sys
if sys.version_info.major == 3:
    from unittest import mock
else:
    import mock

test_path = os.path.dirname(os.path.abspath(__file__))
modules_path = os.path.dirname(test_path)
sys.path.insert(0, modules_path)

from sonic_platform import utils


class TestUtils:
    def test_read_file(self):
        ret = utils.read_str_from_file('not exist', 'default return')
        assert ret == 'default return'

        with pytest.raises(IOError):
            ret = utils.read_str_from_file('not exist', 'default return', raise_exception=True)
            assert ret == 'default return'

        ret = utils.read_int_from_file('not exist', 100)
        assert ret == 100

        with pytest.raises(IOError):
            ret = utils.read_int_from_file('not exist', 200, raise_exception=True)
            assert ret == 200

        ret = utils.read_float_from_file('not exist', 3.14)
        assert ret == 3.14

        with pytest.raises(IOError):
            ret = utils.read_float_from_file('not exist', 2.25, raise_exception=True)
            assert ret == 2.25

    def test_write_file(self):
        file_path = '/tmp/test.txt'
        utils.write_file(file_path, '  hello  ')
        assert utils.read_str_from_file(file_path) == 'hello'

        utils.write_file(file_path, '123 ')
        assert utils.read_int_from_file(file_path) == 123

        utils.write_file(file_path, '3.14 ')
        assert utils.read_float_from_file(file_path) == 3.14

        with pytest.raises(IOError):
            utils.write_file('/not/exist/file', '123', raise_exception=True)

    def test_pre_initialize(self):
        mock_call = mock.MagicMock()

        class A:
            @utils.pre_initialize(mock_call)
            def func(self):
                pass

        A().func()
        assert mock_call.call_count == 1

    def test_pre_initialize_one(self):
        mock_call = mock.MagicMock()

        class A:
            @utils.pre_initialize_one(mock_call)
            def func(self, index):
                pass

        a = A()
        a.func(34)
        mock_call.assert_called_once_with(a, 34)

    def test_read_only_cache(self):
        value = 100

        def func():
            return value

        assert func() == 100
        value = 1000
        assert func() == 1000

        @utils.read_only_cache()
        def func():
            return value

        assert func() == 1000
        value = 10000
        assert func() == 1000

    @mock.patch('sonic_py_common.logger.Logger.log_debug')
    def test_default_return(self, mock_log):
        @utils.default_return(100, log_func=mock_log)
        def func():
            raise RuntimeError('')
        
        assert func() == 100
        assert mock_log.call_count == 1
