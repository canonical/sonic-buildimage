/* Load-time stand-in for the libpython3.11 that vendor Marvell SAI builds link; any call aborts. */
#include <stdio.h>
#include <stdlib.h>

static void die(const char *name)
{
    fprintf(stderr, "mrvl-sai-pystub: %s() called; this SAI needs a real libpython3.11\n", name);
    abort();
}

void PyConfig_Clear(void) { die("PyConfig_Clear"); }
void PyConfig_InitPythonConfig(void) { die("PyConfig_InitPythonConfig"); }
void PyConfig_SetArgv(void) { die("PyConfig_SetArgv"); }
void PyConfig_SetBytesArgv(void) { die("PyConfig_SetBytesArgv"); }
void PyConfig_SetString(void) { die("PyConfig_SetString"); }
void PyEval_SaveThread(void) { die("PyEval_SaveThread"); }
void PyGILState_Ensure(void) { die("PyGILState_Ensure"); }
void PyGILState_Release(void) { die("PyGILState_Release"); }
void PyModule_Create2(void) { die("PyModule_Create2"); }
void PyRun_SimpleFileExFlags(void) { die("PyRun_SimpleFileExFlags"); }
void PyStatus_Exception(void) { die("PyStatus_Exception"); }
void PyStatus_IsExit(void) { die("PyStatus_IsExit"); }
void Py_DecodeLocale(void) { die("Py_DecodeLocale"); }
void Py_Finalize(void) { die("Py_Finalize"); }
void Py_Initialize(void) { die("Py_Initialize"); }
void Py_InitializeFromConfig(void) { die("Py_InitializeFromConfig"); }
void Py_IsInitialized(void) { die("Py_IsInitialized"); }
void Py_RunMain(void) { die("Py_RunMain"); }
