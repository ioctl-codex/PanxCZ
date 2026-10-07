#!/usr/bin/env python3
"""Extract the embedded kernel config (IKCFG_ST ... IKCFG_ED) and optionally diff it.

The kernel config is compiled into the Image as a gzip blob. Two callers want it:

  * "what config did this build actually produce?" - read it back from the Image
    instead of trusting out/.../.config, because a silently-disabled Kconfig
    symbol is exactly the failure mode this project keeps hitting.
  * "is this build the same as the kernel the device actually boots?" - diff
    against a known-good reference config.

Usage:
    extract-kernel-config.py <image-or-boot.img>              # print to stdout
    extract-kernel-config.py <img> -o out.txt                 # write to a file
    extract-kernel-config.py <img> --diff reference.txt       # sorted diff
    extract-kernel-config.py <img> --diff ref.txt --quiet     # summary only

<image-or-boot.img> may be a raw kernel Image, an Image.gz, or a full Android
boot image; boot images are unwrapped automatically.
"""

import argparse
import gzip
import struct
import sys


def unwrap(data: bytes) -> bytes:
    """Return the raw kernel Image, unwrapping a boot image or gzip if needed."""
    if data[:8] == b"ANDROID!":
        kernel_size = struct.unpack_from("<I", data, 8)[0]
        # v3/v4 boot images place the kernel at the first 4096-byte page.
        return unwrap(data[4096:4096 + kernel_size])
    if data[:2] == b"\x1f\x8b":
        return gzip.decompress(data)
    return data


def extract(data: bytes) -> str:
    start = data.find(b"IKCFG_ST")
    end = data.find(b"IKCFG_ED")
    if start < 0 or end < 0 or end <= start:
        raise SystemExit(
            "no IKCFG_ST/IKCFG_ED blob found - not a kernel Image with an "
            "embedded config (CONFIG_IKCONFIG must be enabled)"
        )
    return gzip.decompress(data[start + 8:end]).decode("utf-8", "replace")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("-o", "--output", help="write the config here")
    ap.add_argument("--diff", metavar="REFERENCE",
                    help="diff the extracted config against this reference config")
    ap.add_argument("--quiet", action="store_true",
                    help="with --diff, print only the summary line")
    args = ap.parse_args()

    with open(args.image, "rb") as fh:
        image = unwrap(fh.read())
    config = extract(image)

    if args.output:
        with open(args.output, "w") as fh:
            fh.write(config)
        print(f"wrote {args.output} ({len(config)} bytes)")

    if not args.diff:
        if not args.output:
            sys.stdout.write(config)
        return 0

    with open(args.diff) as fh:
        reference = fh.read()

    ref_set = set(reference.splitlines())
    got_set = set(config.splitlines())
    missing = sorted(ref_set - got_set)   # in the reference, not in ours
    added = sorted(got_set - ref_set)     # in ours, not in the reference

    if not args.quiet:
        for line in missing:
            print(f"- {line}")
        for line in added:
            print(f"+ {line}")
    print(f"config diff vs {args.diff}: {len(missing)} removed, {len(added)} added")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
