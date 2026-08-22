#!/usr/bin/env python3
"""Generate the AEAD throughput report from a UART (picocom) capture.

Usage:
    python3 generate_report.py <picocom_log.txt> <output_report.rpt>
        [--sys-clk-mhz 50 100] [--fmax NAME=MHZ]
        [--fmax-csv PATH] [--fmax-log PATH]

Per-core Fmax is resolved with this precedence (highest wins):
  1. --fmax NAME=MHZ              manual override
  2. scripts/vivado/fmax_ooc.csv  machine-readable results of fmax_ooc.tcl
  3. scripts/vivado/fmax_ooc.log  ">>>" result lines of an fmax_ooc.tcl run
  4. "#   est fmax ..." boot-header lines in the UART log (unverified estimates)
There is NO silent default frequency: a core without any Fmax source gets
"N/A (no Fmax)" in the HW Throughput column and a warning on stdout.
"""

import argparse
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VIVADO_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "scripts", "vivado"))

# fmax_ooc.tcl top-module names -> report core names
OOC_TO_REPORT = {
    "tinyjambu_core":         "TinyJAMBU",
    "xoodyakcore":            "Xoodyak",
    "cofb_core":              "GIFT-COFB",
    "chacha20_poly1305_core": "ChaCha20-Poly1305",
}

# Result lines printed by fmax_ooc.tcl, e.g.
#   >>> tinyjambu_core  Fmax ~ 211.0 MHz  (closes at T=4.738 ns)
# Anchored, with numeric groups only, so the copy of the tcl format string
# that Vivado echoes into the log cannot match.
OOC_LINE_RE = re.compile(
    r"^>>>\s+(\S+)\s+Fmax\s*~\s*[\d.]+\s*MHz\s+\(closes at T=([\d.]+)\s*ns\)")

# Boot-header estimate lines emitted by older firmware builds
BOOT_FMAX_KEYS = {
    "#   est fmax tj":      "TinyJAMBU",
    "#   est fmax xoodyak": "Xoodyak",
    "#   est fmax gift":    "GIFT-COFB",
    "#   est fmax chacha":  "ChaCha20-Poly1305",
}


def fmax_from_csv(path):
    """Read fmax_ooc.csv ('core,period_ns,fmax_mhz,part,date'). {} if unusable."""
    found = {}
    try:
        with open(path, errors="replace") as f:
            lines = [ln.strip() for ln in f if ln.strip()]
    except OSError:
        return found
    for row in lines[1:]:  # skip header
        cols = row.split(",")
        if len(cols) < 3 or cols[0] not in OOC_TO_REPORT:
            continue
        try:
            period = float(cols[1])
        except ValueError:
            continue
        if period <= 0:
            continue
        when = cols[4] if len(cols) > 4 else "undated"
        found[OOC_TO_REPORT[cols[0]]] = (
            1000.0 / period,
            "post-route OOC, closes at T=%.3f ns (%s, %s)"
            % (period, os.path.basename(path), when))
    return found


def fmax_from_ooc_log(path):
    """Scrape the '>>>' result lines of an fmax_ooc.tcl run log. {} if unusable."""
    found = {}
    try:
        f = open(path, errors="replace")
    except OSError:
        return found
    with f:
        for line in f:
            m = OOC_LINE_RE.match(line)
            if not m or m.group(1) not in OOC_TO_REPORT:
                continue
            period = float(m.group(2))
            if period > 0:  # last occurrence per core wins
                found[OOC_TO_REPORT[m.group(1)]] = (
                    1000.0 / period,
                    "post-route OOC, closes at T=%.3f ns (%s)"
                    % (period, os.path.basename(path)))
    return found


def parse_uart_log(path):
    """Return (results, boot_fmax).

    results: [(name, payload_bytes, ops, core_cycles, total_cycles)] in
    first-seen order with System-All forced last; duplicates keep the last
    values. boot_fmax: {core name: MHz} from boot-header estimate lines.
    """
    results_dict = {}
    boot_fmax = {}
    with open(path, "r", errors="replace") as f:
        for line in f:
            handled = False
            for key, name in BOOT_FMAX_KEYS.items():
                if key in line and "N/A" not in line:
                    try:
                        boot_fmax[name] = float(
                            line.split("=")[1].strip().split(" ")[0])
                    except (IndexError, ValueError):
                        pass
                    handled = True
                    break
            if handled or "PERF_DATA:" not in line:
                continue
            # Example: PERF_DATA:TinyJAMBU,56,4,1500,2000
            data_part = line[line.find("PERF_DATA:") + 10:].strip()
            parts = data_part.split(",")
            if len(parts) == 5:
                try:
                    results_dict[parts[0]] = (parts[0], int(parts[1]),
                                              int(parts[2]), int(parts[3]),
                                              int(parts[4]))
                except ValueError:
                    pass
    results = list(results_dict.values())
    results.sort(key=lambda x: x[0] == "System-All")
    return results, boot_fmax


def resolve_fmax(results, boot_fmax, args):
    """Return {core name: (fmax_mhz, provenance)} for every measured core."""
    overrides = dict(args.fmax or [])
    csv_vals = fmax_from_csv(args.fmax_csv)
    log_vals = fmax_from_ooc_log(args.fmax_log)

    resolved = {}
    for res in results:
        name = res[0]
        if name == "System-All":
            continue
        if name in overrides:
            resolved[name] = (overrides[name], "manual override (--fmax)")
        elif name in csv_vals:
            resolved[name] = csv_vals[name]
        elif name in log_vals:
            resolved[name] = log_vals[name]
        elif name in boot_fmax:
            resolved[name] = (boot_fmax[name],
                              "firmware boot-header estimate -- UNVERIFIED")
            print("[!] %s: no Vivado timing data found; using unverified "
                  "firmware-estimated Fmax %.3f MHz" % (name, boot_fmax[name]))
        else:
            print("[!] %s: no Fmax source found (--fmax, %s, %s); "
                  "HW Throughput will be N/A" % (name, args.fmax_csv, args.fmax_log))
    return resolved


def check_core_sums(results):
    """Warn if the per-core rows do not sum to the System-All row."""
    rows = {r[0]: r for r in results}
    if "System-All" not in rows or len(rows) < 3:
        return
    for idx, label in ((1, "payload_bytes"), (2, "ops"),
                       (3, "core_cycles"), (4, "total_cycles")):
        total = sum(r[idx] for n, r in rows.items() if n != "System-All")
        if total != rows["System-All"][idx]:
            print("[!] consistency: sum of per-core %s (%d) != System-All (%d)"
                  % (label, total, rows["System-All"][idx]))


def generate_report(args):
    if not os.path.isfile(args.log_file):
        print("Error: Could not find log file '%s'" % args.log_file)
        sys.exit(1)

    results, boot_fmax = parse_uart_log(args.log_file)
    if not results:
        print("Error: No 'PERF_DATA:' lines found in the log file.")
        sys.exit(1)

    fmax = resolve_fmax(results, boot_fmax, args)
    check_core_sums(results)

    for res in results:
        name = res[0]
        if name in fmax:
            print("[*] %s: Fmax = %.3f MHz  [%s]"
                  % (name, fmax[name][0], fmax[name][1]))

    sys_clks = args.sys_clk_mhz
    sys_headers = ["System @%g MHz" % clk for clk in sys_clks]
    sys_widths = [max(15, len(h)) for h in sys_headers]

    header_cells = ["%-17s" % "Core / Scope", "%-8s" % "Payload",
                    "%-5s" % "Ops", "%-10s" % "Core Cyc", "%-10s" % "Total Cyc",
                    "%-10s" % "Fmax (MHz)", "%-15s" % "HW Throughput"]
    header_cells += ["%-*s" % (w, h) for w, h in zip(sys_widths, sys_headers)]
    header_line = " | ".join(header_cells)

    with open(args.output_rpt, "w") as out:
        out.write("========================================================\n")
        out.write("              HARDWARE THROUGHPUT REPORT                \n")
        out.write("========================================================\n\n")
        out.write(header_line + "\n")
        out.write("-" * len(header_line) + "\n")

        for res in results:
            name, p_bytes, ops, core_cyc, total_cyc = res

            fmax_cell = "N/A"
            hw_cell = "N/A"
            if name != "System-All":
                if name not in fmax:
                    hw_cell = "N/A (no Fmax)"
                elif core_cyc > 0:
                    fmax_cell = "%.3f" % fmax[name][0]
                    hw_cell = "%.3f Mbps" % (p_bytes * 8 * fmax[name][0] / core_cyc)

            cells = ["%-17s" % name, "%-6d B" % p_bytes, "%-5d" % ops,
                     "%-10d" % core_cyc, "%-10d" % total_cyc,
                     "%-10s" % fmax_cell, "%-15s" % hw_cell]
            for clk, w in zip(sys_clks, sys_widths):
                sys_cell = "N/A"
                if total_cyc > 0:
                    sys_cell = "%.3f Mbps" % (p_bytes * 8 * clk / total_cyc)
                cells.append("%-*s" % (w, sys_cell))
            out.write(" | ".join(cells) + "\n")

        out.write("\nFmax sources:\n")
        for res in results:
            name = res[0]
            if name in fmax:
                out.write("  %-17s : %8.3f MHz  [%s]\n"
                          % (name, fmax[name][0], fmax[name][1]))
            elif name != "System-All":
                out.write("  %-17s : N/A (no Fmax source found)\n" % name)

        out.write("\n========================================================\n")
        out.write(
            "Notes:\n"
            "- HW Throughput = payload_bits * Fmax / core_cycles. Fmax is the\n"
            "  core's STANDALONE post-route out-of-context Fmax (scripts/vivado/\n"
            "  fmax_ooc.tcl: binary-searched clock period, register-to-register\n"
            "  paths, part xc7a100tcsg324-1). It is an upper bound, not the\n"
            "  in-system rate.\n"
            "- System @F MHz = payload_bits * F / total_cycles, where total_cycles\n"
            "  (rdcycle) includes CPU register writes/reads and status polling.\n"
            "  The board oscillator is 100 MHz; older builds divided it to 50 MHz\n"
            "  (ChaCha timing). Check which clock the measured build actually ran\n"
            "  at (system.v clock section / synth_system.xdc) and read the\n"
            "  matching column.\n"
            "- Cycle counts are hardware measurements in the single clk_sys domain\n"
            "  and do not change with clock frequency.\n"
            "- Fmax from the binary search is a safe lower bound (the recorded\n"
            "  fmax_ooc.log run used 8 iterations = ~0.113 ns period resolution;\n"
            "  fmax_ooc.tcl now uses 10 = ~0.028 ns). fmax_ooc.log was recorded\n"
            "  from an earlier checkout (pico_fivecore); re-run fmax_ooc.tcl to\n"
            "  emit fmax_ooc.csv, which this script picks up automatically.\n")

    print("Success! Report generated at: %s" % args.output_rpt)


def parse_fmax_override(spec):
    name, sep, val = spec.partition("=")
    try:
        mhz = float(val)
    except ValueError:
        mhz = -1.0
    if not sep or not name or mhz <= 0:
        raise argparse.ArgumentTypeError(
            "expected NAME=MHZ with MHZ > 0, got '%s'" % spec)
    return (name, mhz)


def main():
    ap = argparse.ArgumentParser(
        description="Generate the AEAD throughput report from a UART capture.")
    ap.add_argument("log_file",
                    help="picocom/UART capture containing PERF_DATA lines")
    ap.add_argument("output_rpt", help="report file to write")
    ap.add_argument("--sys-clk-mhz", nargs="+", type=float,
                    default=[50.0, 100.0], metavar="MHZ",
                    help="system clock(s) for the System Throughput column(s); "
                         "default: 50 (implemented clk_sys) and 100 (nominal "
                         "board clock)")
    ap.add_argument("--fmax", action="append", type=parse_fmax_override,
                    metavar="NAME=MHZ",
                    help="manual Fmax override for one core, repeatable "
                         "(e.g. --fmax TinyJAMBU=211.06)")
    ap.add_argument("--fmax-csv", default=os.path.join(VIVADO_DIR, "fmax_ooc.csv"),
                    help="machine-readable fmax_ooc.tcl results "
                         "(default: %(default)s)")
    ap.add_argument("--fmax-log", default=os.path.join(VIVADO_DIR, "fmax_ooc.log"),
                    help="fmax_ooc.tcl run log, used if the CSV is absent "
                         "(default: %(default)s)")
    generate_report(ap.parse_args())


if __name__ == "__main__":
    main()
