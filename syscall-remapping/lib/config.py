"""
ISA Remapping Phase 3 — Python Config Reader
Reads isa.env from the project root.
Usage: from lib.config import cfg
       map_path = cfg['ISA_SYSCALL_KEYRING']
"""
import os

def load_env(env_path=None):
    if env_path is None:
        lib_dir = os.path.dirname(os.path.abspath(__file__))
        env_path = os.path.join(lib_dir, '..', 'isa.env')
    cfg = {}
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    key, val = line.split('=', 1)
                    cfg[key.strip()] = val.strip()
    except FileNotFoundError:
        pass
    return cfg

cfg = load_env()
ISA_SYSCALL_KEYRING = os.environ.get('ISA_SYSCALL_KEYRING', cfg.get('ISA_SYSCALL_KEYRING', '/etc/isa/syscall_keyring'))

if __name__ == '__main__':
    for k, v in cfg.items():
        print(f"  {k} = {v}")
