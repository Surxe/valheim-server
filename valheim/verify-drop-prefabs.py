#!/usr/bin/env python3
"""Verify drop_that.drop_table.cfg prefab ids against a fresh DropThat dump.

Every override in drop_that.drop_table.cfg is keyed by a drop-table section
[Source.index] with a PrefabName=<item>. After a Valheim/mod update those ids can
drift. This checks each config entry against the DropThat "WriteDropTablesToFiles"
dump (prefabs/locations/dungeons) and reports MATCH / MISMATCH / MISSING.

By default it pulls the preserved dump straight off Valheim VM 100 via the guest
agent (needs sudo). Point --dump-dir at a directory of already-pulled
drop_that.drop_table.{prefabs,locations,dungeons}.txt files to skip that.

See the 'dropthat-prefab-dump' memory note for how to (re)generate the dump safely.

Usage:
    sudo ./verify-drop-prefabs.py                 # pull from VM 100, compare
    ./verify-drop-prefabs.py --dump-dir /some/dir # use local dump files
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

REPO_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CFG = os.path.join(REPO_DIR, "drop_that.drop_table.cfg")
VM_ID = "100"
VM_DUMP_DIR = "/srv/valheim/dropthat-prefab-dump"
DUMP_FILES = ["prefabs", "locations", "dungeons"]


def parse_blocks(path):
    """Parse an ini-ish file into {section-key: {field: value}}."""
    blocks, cur = {}, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            m = re.match(r"^\[([^\]]+)\]$", line)
            if m:
                cur = m.group(1)
                blocks[cur] = {}
            elif cur and "=" in line and not line.startswith("#"):
                k, _, v = line.partition("=")
                blocks[cur][k.strip()] = v.strip()
    return blocks


def pull_dump_from_vm(dest_dir):
    """Copy the preserved dump files off VM 100 via `qm guest exec`."""
    for name in DUMP_FILES:
        src = f"{VM_DUMP_DIR}/drop_that.drop_table.{name}.txt"
        try:
            raw = subprocess.check_output(
                ["qm", "guest", "exec", VM_ID, "--", "/bin/bash", "-lc", f"cat {src}"]
            )
        except FileNotFoundError:
            sys.exit("error: `qm` not found — run this on the Proxmox host.")
        except subprocess.CalledProcessError as e:
            sys.exit(f"error: guest exec failed for {name}: {e}")
        data = json.loads(raw)
        if data.get("exitcode", 0) != 0:
            sys.exit(f"error: reading {src} on VM {VM_ID}: {data.get('err-data','')}")
        with open(os.path.join(dest_dir, f"{name}.txt"), "w", encoding="utf-8") as fh:
            fh.write(data.get("out-data", ""))


def load_dump(dump_dir):
    """Merge the three dump files into one {section-key: fields} view."""
    merged, source = {}, {}
    for name in DUMP_FILES:
        path = os.path.join(dump_dir, f"{name}.txt")
        if not os.path.exists(path):
            sys.exit(f"error: dump file not found: {path}")
        for key, fields in parse_blocks(path).items():
            if key not in merged:
                merged[key], source[key] = fields, name
    return merged, source


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cfg", default=DEFAULT_CFG,
                    help="drop_table cfg to verify (default: repo copy)")
    ap.add_argument("--dump-dir",
                    help="dir of drop_that.drop_table.*.txt files "
                         "(default: pull from VM %s)" % VM_ID)
    args = ap.parse_args()

    cfg = {k: v for k, v in parse_blocks(args.cfg).items() if "PrefabName" in v}

    tmp = None
    dump_dir = args.dump_dir
    if not dump_dir:
        tmp = tempfile.mkdtemp(prefix="drop-dump-")
        pull_dump_from_vm(tmp)
        dump_dir = tmp
    dump, dump_src = load_dump(dump_dir)

    print(f"Config override entries: {len(cfg)}")
    print(f"Dump sections (merged):  {len(dump)}  [source: {dump_dir}]\n")

    ok, mism, missing = [], [], []
    for key, cv in cfg.items():
        citem = cv.get("PrefabName")
        if key not in dump:
            src = key.rsplit(".", 1)[0]
            idxs = sorted(k for k in dump if k == src or k.startswith(src + "."))
            missing.append((key, citem, src, idxs))
        elif dump[key].get("PrefabName") == citem:
            ok.append((key, citem, dump_src[key]))
        else:
            mism.append((key, citem, dump[key].get("PrefabName"), dump_src[key]))

    print(f"MATCH ({len(ok)}): same [Source.index] -> PrefabName in dump")
    for key, item, src in ok:
        print(f"  [{key}] -> {item}   ({src})")

    print(f"\nMISMATCH ({len(mism)}): entry in dump but item differs")
    for key, citem, ditem, src in mism:
        print(f"  [{key}]  config={citem}  DUMP={ditem}   ({src})")

    print(f"\nMISSING ({len(missing)}): config entry not in dump")
    for key, citem, src, idxs in missing:
        if idxs:
            print(f"  [{key}]  config={citem}  -> source '{src}' present with:")
            for ik in idxs:
                print(f"        [{ik}] -> {dump[ik].get('PrefabName','?')}")
        else:
            print(f"  [{key}]  config={citem}  -> source '{src}' NOT in dump at all")

    if tmp:
        for name in DUMP_FILES:
            os.remove(os.path.join(tmp, f"{name}.txt"))
        os.rmdir(tmp)

    return 1 if (mism or missing) else 0


if __name__ == "__main__":
    sys.exit(main())
