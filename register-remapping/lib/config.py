"""
Register Remapping — Python config reader
Reads isa.env from the same directory as this file.
"""
import os

_BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ENV  = os.path.join(_BASE, "isa.env")

def _load():
    cfg = {}
    with open(_ENV) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip()
    return cfg

_cfg = _load()
REGISTER_KEYRING = _cfg.get("REGISTER_KEYRING", "/etc/isa/register_keyring")
