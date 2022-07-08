#ifndef SYSLOG_PARSER_H
#define SYSLOG_PARSER_H

#include <vector>
#include <string>
#include <regex>
#include "json.hpp"
#include "events.h"

using namespace std;
using json = nlohmann::json;

/**
 * Syslog Parser is responsible for parsing log messages fed by rsyslog.d and returns
 * matched result to rsyslog_plugin to use with events publish API
 *
 */

class SyslogParser {
public:
    vector<regex> m_expressions;
    json m_regexList = json::array();
    bool parseMessage(string message, string& tag, event_params_t& paramDict);
};

#endif
