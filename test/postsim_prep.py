"""Prepare files for Icarus post-layout (SDF) simulation.

Icarus Verilog has two limitations with the SKY130 timing models / OpenSTA SDF:

1. Timing checks ($setuphold) are not supported, so the *_delayed signals that
   the sequential cell models use are never driven -> flops do nothing.
   Fix: patched copy of the cell library where each `wire X_delayed;` becomes
   `wire X_delayed = X;`.

2. The flattened netlist uses escaped instance names such as
   \\core.line_a.stage[0].dly[0].dt_keep_dly , which the SDF writes as
   core\\.line_a\\.stage\\[0\\]... Icarus splits on every '.', escaped or not.
   Fix: switch the SDF hierarchy DIVIDER to '/' and un-escape the names.

3. Icarus's SDF parser also rejects instance names containing '.' or '[]'
   (all the hand-instantiated dt_keep cells). Fix: rename those instances to
   plain identifiers (dtk_0, dtk_1, ...) in BOTH the netlist and the SDF.
   Only instance names change, not the circuit.

usage: python3 postsim_prep.py <cell_lib.v> <in.sdf> <netlist.v> <out_dir>
"""
import os
import re
import sys

lib_in, sdf_in, nl_in, out_dir = sys.argv[1:5]
os.makedirs(out_dir, exist_ok=True)

# rename escaped instances in the netlist
rename = {}
def ren(m):
    old = m.group(2)
    new = rename.setdefault(old, f'dtk_{len(rename)}')
    return f'{m.group(1)}{new} '
nl = open(nl_in).read()
nl = re.sub(r'^(\s*sky130_fd_sc_hd__\w+\s+)\\(\S+)\s', ren, nl, flags=re.M)
open(os.path.join(out_dir, 'netlist_postsim.v'), 'w').write(nl)
print(f'netlist: {len(rename)} escaped instances renamed')

# 1. cell library
lib = open(lib_in).read()
lib, n = re.subn(r'wire\s+(\w+)_delayed\s*;', r'wire \1_delayed = \1;', lib)
open(os.path.join(out_dir, 'sky130_fd_sc_hd_postsim.v'), 'w').write(lib)
print(f'cell library: {n} *_delayed wires tied to their inputs')

# 2. SDF
def convert(ident):
    # split on unescaped '.', then drop the escapes
    parts = re.split(r'(?<!\\)\.', ident)
    return '/'.join(p.replace('\\', '') for p in parts)

sdf = open(sdf_in).read()
sdf = sdf.replace('(DIVIDER .)', '(DIVIDER /)')
def inst(m):
    name = convert(m.group(1))
    return f'(INSTANCE {rename.get(name, name)})'
sdf = re.sub(r'\(INSTANCE ([^)]+)\)', inst, sdf)
# 3. Icarus cannot parse the top-level CELL that holds the INTERCONNECT (wire)
#    delays. They are small (0.02-0.07 ns per net, see STA), so drop that block
#    and keep every cell's own IOPATH delays.
cells = re.split(r'\n(?= \(CELL\n)', sdf)
head, body = cells[0], cells[1:]
kept = [c for c in body if 'INTERCONNECT' not in c]
dropped = len(body) - len(kept)
sdf = head + '\n' + '\n'.join(kept)
if not sdf.rstrip().endswith(')'):
    sdf += '\n)'
open(os.path.join(out_dir, 'design_postsim.sdf'), 'w').write(sdf)
print(f'sdf: divider set to "/", instance names un-escaped, {dropped} interconnect block(s) dropped, '
      f'{len(kept)} cell blocks kept')
