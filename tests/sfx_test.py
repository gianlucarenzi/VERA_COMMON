# sfx_test.py - a small effects bank for tests/prof_sfx.c (tools/psgsfx.py)
from psgsfx import frame, sweep, env

def zap(n=10):
    f = sweep(2000, 200, n)
    v = env([(0, 60), (n - 1, 0)], n)
    return [frame(f[i], v[i], 'pulse', 32) for i in range(n)]

EFFECTS = [('zap', zap()), ('noise', [frame(5000, 40, 'noise')] * 20),
           ('saw', [frame(220, 50, 'saw')] * 30), ('long', zap(60))]
