"""
ISA Remapping — Python Config Reader
Reads isa.env from the project root.
Usage: from lib.config import cfg
       map_path = cfg['ISA_MAP']
"""
import os

def load_env(env_path=None):
    if env_path is None:
        # Auto-detect project root (this file is in lib/)
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

# Load on import
cfg = load_env()

# ISA_MAP: prefer environment variable (set by bash export), then isa.env, then default
ISA_MAP = os.environ.get('ISA_MAP', cfg.get('ISA_MAP', '/etc/isa/map'))

if __name__ == '__main__':
    print("Config loaded from isa.env:")
    for k, v in cfg.items():
        print(f"  {k} = {v}")
    print(f"  ISA_MAP (resolved) = {ISA_MAP}")
