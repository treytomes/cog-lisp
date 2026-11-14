"""Drive a console program the way a person at a terminal would.

The program runs in a real console (Windows ConPTY, through pywinpty; the
VS Code terminal uses the same), so it sees a terminal, not a pipe: the
console library turns on its interactive prompts, arrow keys reach it, and
Ctrl+Z / Ctrl+C mean what they do at a keyboard. pyte renders the output into
a screen that can be checked.

Needs:  python -m pip install --user pywinpty pyte

As a program, it runs a step script:

    python tools/console_driver.py [options] SCRIPT -- COMMAND [ARG ...]

    options: --cols N (100)  --rows N (40)  --timeout SECONDS (20, each step)
             --start-timeout SECONDS (90, the first expect)  --cwd DIR
             --transcript FILE (write everything the program printed, escapes stripped)
             -v (echo each step and print the screen when the script ends)

A step is a line; # starts a comment.

    send TEXT          type TEXT, then Enter
    type TEXT          type TEXT, no Enter
    key NAME [N]       press a key N times: enter tab esc backspace up down
                       left right home end ctrl-c ctrl-d ctrl-z, or ctrl-<letter>;
                       eof is the end of input: Ctrl+Z, Enter on Windows, Ctrl+D
                       elsewhere (Ctrl+Z suspends a program on Linux)
    expect TEXT        wait until TEXT appears in what the program printed since
                       the last send/type/key (escapes stripped; a match may
                       span a redraw, so prefer short phrases)
    expect-re REGEX    the same, for a Python regular expression
    expect-screen TEXT wait until TEXT is on the rendered screen
    expect-screen-re REGEX  the same, a Python regular expression, ^ and $ at
                       each line's start and end
    refute TEXT        fail if TEXT is in what was printed since the last input
    wait SECONDS       let the program run
    settle             wait until the program prints nothing for 0.5 s
    screen             print the rendered screen
    print              print what was printed since the last input
    exit [CODE]        wait for the program to end; check its exit code (0)

It exits 0 when every step passed, else 1, printing the failing step, what was
printed since the last input, and the screen.

As a library:

    from console_driver import Console   # tools/ on sys.path
    with Console(["cog-lisp.bat", "weather/main.lisp"], cwd=...) as c:
        c.expect("weather>", timeout=90)
        c.send("help")
        c.expect("Commands")
        print(c.screen_text())
"""

import argparse
import os
import queue
import re
import subprocess
import sys
import threading
import time

WINDOWS = sys.platform == "win32"
try:
    import pyte
    if WINDOWS:
        from winpty import PtyProcess
    else:  # untested so far: ptyprocess has the API pywinpty copies
        from ptyprocess import PtyProcessUnicode as PtyProcess
except ImportError as e:  # pragma: no cover
    sys.exit(f"console-driver: {e.name} is missing: python -m pip install --user "
             + ("pywinpty" if WINDOWS else "ptyprocess") + " pyte")

KEYS = {
    "enter": "\r", "tab": "\t", "esc": "\x1b", "backspace": "\x7f",
    "up": "\x1b[A", "down": "\x1b[B", "right": "\x1b[C", "left": "\x1b[D",
    "home": "\x1b[H", "end": "\x1b[F",
}

# CSI and OSC sequences, and the lone escapes ConPTY sends
_ESCAPES = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]")


def strip_escapes(s):
    return _ESCAPES.sub("", s).replace("\r", "")


class StepFailed(Exception):
    pass


class Console:
    def __init__(self, argv, cwd=None, cols=100, rows=40, env=None):
        if WINDOWS:  # pywinpty takes one command line
            cmd = subprocess.list2cmdline(argv) if isinstance(argv, (list, tuple)) else argv
        else:
            cmd = list(argv)
        # pywinpty does not start it in the current folder unless told
        self.proc = PtyProcess.spawn(cmd, cwd=cwd or os.getcwd(), env=env, dimensions=(rows, cols))
        self.screen = pyte.Screen(cols, rows)
        self._stream = pyte.Stream(self.screen)
        self._queue = queue.Queue()
        self.output = ""      # everything printed, escapes stripped
        self.mark = 0         # where the output since the last input starts
        self.ended = False
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        while True:
            try:
                data = self.proc.read(4096)
            except EOFError:
                self._queue.put(None)
                return
            self._queue.put(data)

    def pump(self, timeout):
        """Takes what the program printed in the next `timeout` seconds; answers whether it printed any."""
        try:
            data = self._queue.get(timeout=timeout)
        except queue.Empty:
            return False
        if data is None:
            self.ended = True
            return False
        self._stream.feed(data)
        self.output += strip_escapes(data)
        return True

    def since_input(self):
        return self.output[self.mark:]

    def screen_text(self):
        lines = [line.rstrip() for line in self.screen.display]
        while lines and not lines[-1]:
            lines.pop()
        return "\n".join(lines)

    # input
    def type(self, text):
        self._drain()
        self.mark = len(self.output)
        self.proc.write(text)

    def send(self, line):
        self.type(line + "\r")

    def key(self, name, times=1):
        name = name.lower()
        if name == "eof":  # the end of input: Ctrl+Z, Enter on Windows; Ctrl+D elsewhere
            seq = "\x1a\r" if WINDOWS else "\x04"
        elif name in KEYS:
            seq = KEYS[name]
        elif re.fullmatch(r"ctrl-[a-z]", name):
            seq = chr(ord(name[-1]) - ord("a") + 1)
        else:
            raise StepFailed(f"unknown key {name!r}")
        self.type(seq * times)

    def _drain(self):
        while self.pump(0):
            pass

    # waiting
    def _until(self, test, timeout, what):
        end = time.time() + timeout
        while True:
            if test():
                return
            if self.ended:
                raise StepFailed(f"{what}: the program ended")
            left = end - time.time()
            if left <= 0:
                raise StepFailed(f"{what}: not within {timeout:g} s")
            self.pump(min(left, 0.1))

    def expect(self, text, timeout=20):
        self._until(lambda: text in self.since_input(), timeout, f"expect {text!r}")

    def expect_re(self, pattern, timeout=20):
        rx = re.compile(pattern)
        self._until(lambda: rx.search(self.since_input()), timeout, f"expect-re {pattern!r}")

    def expect_screen_re(self, pattern, timeout=20):
        rx = re.compile(pattern, re.MULTILINE)
        self._until(lambda: rx.search(self.screen_text()), timeout, f"expect-screen-re {pattern!r}")

    def expect_screen(self, text, timeout=20):
        self._until(lambda: text in self.screen_text(), timeout, f"expect-screen {text!r}")

    def refute(self, text):
        self._drain()
        if text in self.since_input():
            raise StepFailed(f"refute {text!r}: it was printed")

    def wait(self, seconds):
        end = time.time() + seconds
        while time.time() < end and not self.ended:
            self.pump(min(end - time.time(), 0.1))

    def settle(self, quiet=0.5, timeout=20):
        end = time.time() + timeout
        while time.time() < end and not self.ended:
            if not self.pump(quiet):
                return
        if not self.ended:
            raise StepFailed(f"settle: still printing after {timeout:g} s")

    def wait_exit(self, timeout=20):
        end = time.time() + timeout
        while not self.ended and time.time() < end:
            self.pump(0.1)
        while self.proc.isalive() and time.time() < end:
            time.sleep(0.05)
        if self.proc.isalive():
            raise StepFailed(f"exit: still running after {timeout:g} s")
        return self.proc.exitstatus

    def close(self):
        if self.proc.isalive():
            self.proc.terminate(force=True)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def run_script(console, steps, timeout, start_timeout, verbose):
    first_expect = True
    for number, line in steps:
        word, _, arg = line.partition(" ")
        if verbose:
            print(f"  {number}: {line}", flush=True)
        try:
            if word == "send":
                console.send(arg)
            elif word == "type":
                console.type(arg)
            elif word == "key":
                parts = arg.split()
                console.key(parts[0], int(parts[1]) if len(parts) > 1 else 1)
            elif word in ("expect", "expect-re", "expect-screen", "expect-screen-re"):
                t = start_timeout if first_expect else timeout
                first_expect = False
                {"expect": console.expect, "expect-re": console.expect_re,
                 "expect-screen": console.expect_screen,
                 "expect-screen-re": console.expect_screen_re}[word](arg, t)
            elif word == "refute":
                console.refute(arg)
            elif word == "wait":
                console.wait(float(arg))
            elif word == "settle":
                console.settle(timeout=timeout)
            elif word == "screen":
                console.settle(timeout=timeout)
                print(console.screen_text(), flush=True)
            elif word == "print":
                console.settle(timeout=timeout)
                print(console.since_input().rstrip(), flush=True)
            elif word == "exit":
                want = int(arg) if arg.strip() else 0
                got = console.wait_exit(timeout)
                if got != want:
                    raise StepFailed(f"exit: the program exited {got}, not {want}")
            else:
                raise StepFailed(f"unknown step {word!r}")
        except StepFailed as e:
            print(f"FAILED at line {number}: {line}\n  {e}", flush=True)
            print("--- printed since the last input:\n" + console.since_input().rstrip())
            print("--- screen:\n" + console.screen_text())
            return False
    return True


def read_steps(path):
    with open(path, encoding="utf-8") as f:
        steps = []
        for number, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            if line.strip() and not line.lstrip().startswith("#"):
                steps.append((number, line.strip()))
        return steps


def main(argv):
    if "--" not in argv:
        sys.exit("usage: console_driver.py [options] SCRIPT -- COMMAND [ARG ...]")
    split = argv.index("--")
    ap = argparse.ArgumentParser(prog="console_driver.py")
    ap.add_argument("script")
    ap.add_argument("--cols", type=int, default=100)
    ap.add_argument("--rows", type=int, default=40)
    ap.add_argument("--timeout", type=float, default=20)
    ap.add_argument("--start-timeout", type=float, default=90)
    ap.add_argument("--cwd")
    ap.add_argument("--transcript")
    ap.add_argument("-v", "--verbose", action="store_true")
    opts = ap.parse_args(argv[:split])
    command = argv[split + 1:]
    if not command:
        sys.exit("console_driver.py: no command after --")
    steps = read_steps(opts.script)
    with Console(command, cwd=opts.cwd, cols=opts.cols, rows=opts.rows) as console:
        ok = run_script(console, steps, opts.timeout, opts.start_timeout, opts.verbose)
        if opts.transcript:
            with open(opts.transcript, "w", encoding="utf-8") as f:
                f.write(console.output)
        if opts.verbose and ok:
            print("--- screen:\n" + console.screen_text())
    print(f"console-driver: {len(steps)} steps, {'passed' if ok else 'failed'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
