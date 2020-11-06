#!/usr/bin/env python

""" This module implements new feature registration/de-registration in SONiC system. """

from typing import Dict, Type

from sonic_package_manager.manifest import Manifest
from sonic_package_manager.service_creator.sonic_db import SonicDB

FEATURE = 'FEATURE'


class FeatureRegistry:
    """ FeatureRegistry class provides an interface to
    register/de-register new feature persistently. """

    def __init__(self, sonic_db: Type[SonicDB]):
        self._sonic_db = sonic_db

    def register(self, name: str, manifest: Manifest):
        for table in self._get_tables():
            cfg_entries = self.get_default_feature_entries()
            non_cfg_entries = self.get_non_configurable_feature_entries(manifest)

            exists, running_cfg = table.get(name)

            cfg = cfg_entries.copy()
            # Override configurable entries with CONFIG DB data.
            cfg = {**cfg, **dict(running_cfg)}
            # Override CONFIG DB data with non configurable entries.
            cfg = {**cfg, **non_cfg_entries}

            table.set(name, list(cfg.items()))

    def deregister(self, name: str):
        for table in self._get_tables():
            table._del(name)

    def is_feature_enabled(self, name: str) -> bool:
        """ Returns whether the feature is current enabled
        or not. Accesses running CONFIG DB. If no running CONFIG_DB
        table is found in tables returns False. """

        running_db_table = self._sonic_db.running_table(FEATURE)
        if running_db_table is None:
            return False

        exists, cfg = running_db_table.get(name)
        if not exists:
            return False
        cfg = dict(cfg)
        if cfg.get('state') == 'enabled':
            return True

        return False

    def get_multi_instance_features(self):
        res = []
        init_db_table = self._sonic_db.initial_table(FEATURE)
        for feature in init_db_table.keys():
            exists, cfg = init_db_table.get(feature)
            assert exists
            cfg = dict(cfg)
            asic_flag = str(cfg.get('has_per_asic_scope', 'False'))
            if asic_flag.lower() == 'true':
                res.append(feature)
        return res

    @staticmethod
    def get_default_feature_entries() -> Dict[str, str]:
        """ Get configurable feature table entries:
        e.g. 'state', 'auto_restart', etc. """

        return {
            'state': 'disabled',
            'auto_restart': 'enabled',
            'high_mem_alert': 'disabled',
        }

    @staticmethod
    def get_non_configurable_feature_entries(manifest) -> Dict[str, str]:
        """ Get non-configurable feature table entries: e.g. 'has_timer' """

        return {
            'has_per_asic_scope': str(manifest['service']['asic-service']),
            'has_global_scope': str(manifest['service']['host-service']),
            'has_timer': 'False',  # TODO: include timer if package requires
        }

    def _get_tables(self):
        tables = []
        running = self._sonic_db.running_table(FEATURE)
        if running is not None:  # it's Ok if there is no database
            tables.append(running)
        persistent = self._sonic_db.persistent_table(FEATURE)
        if persistent is not None:  # this is also Ok
            tables.append(persistent)
        tables.append(self._sonic_db.initial_table(FEATURE))  # init_cfg.json is must

        return tables
