#!/usr/bin/env python3
"""Fails for code a newer Swift builds that Swift 5.7 refuses (docs/building.md).

Swift 5.7 can't type-check the app's views on CI: no runner has the macOS 12 or 13 SDK it
needs. So the two kinds of code it refused on a Mac on macOS 12 are looked for by their shape:
- a weak `self` read by a `Task` inside the closure that took it ("reference to captured var
  'self' in concurrently-executing code"): hold it in a `WeakBox`, a constant;
- a `defer` inside a `Task` ("main actor-isolated property ... can not be mutated from the main
  actor"): set what it sets after the awaited call instead;
- a view's model read inside a `Task` in one of the view's own functions, not its `body`, with no
  `await` on the line ("main actor-isolated property ... can not be referenced from a
  non-isolated context"). On macOS 12's SDK only a view's `body` is on the main actor, so such a
  `Task` isn't, and each read of an `@ObservedObject`, `@StateObject` or `@EnvironmentObject`, or
  of a `...Model` the function takes, needs `await`: read it with `await` first, then use it.
Usage: scripts/swift57patterns.py FILE..."""
import re, sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from viewbuilders import strip  # comments and strings out, newlines kept


def block(src, start):
    """The text of the brace block opening at or after `start`, braces included."""
    i = src.find('{', start)
    if i < 0:
        return ''
    depth = 0
    for j in range(i, len(src)):
        if src[j] == '{':
            depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    return src[i:]


VIEW = re.compile(r'\bstruct\s+\w+\s*(<[^>{]*>)?\s*:[^{]*\bView\b[^{]*\{')
MODEL_PROP = re.compile(r'@(?:ObservedObject|StateObject|EnvironmentObject)\s+(?:private\s+)?(?:var|let)\s+(\w+)')
FUNC = re.compile(r'\bfunc\s+\w+\s*(<[^>(]*>)?\s*\(([^)]*)\)[^{]*\{')
TASK = re.compile(r'\bTask\b\s*(\([^)]*\))?\s*\{')


def task_reads(src):
    """A view's model read with no `await`, inside a Task in one of the view's own functions."""
    found = []
    for v in VIEW.finditer(src):
        view = block(src, v.end() - 1)
        models = set(MODEL_PROP.findall(view))
        for f in FUNC.finditer(view):
            params = set(re.findall(r'(\w+)\s*:\s*\w*Model\b', f.group(2)))
            names = models | params
            if not names:
                continue
            body = block(view, f.end() - 1)
            for t in TASK.finditer(body):
                task = block(body, t.start())
                at = v.end() - 1 + view.find(body) + t.start()
                for k, line in enumerate(task.split('\n')):
                    if 'await' in line:
                        continue
                    for name in names:
                        if re.search(r'(?<![\w.])' + name + r'\b\s*(\?|!)?\s*\.', line):
                            row = src.count('\n', 0, at) + 1 + k
                            found.append((row, f"{name} read with no await inside a Task in a view's function: read it with await first"))
                            break
    return found


def problems(src):
    found = task_reads(src)
    for m in re.finditer(r'\[\s*weak\s+self\s*\]', src):
        # The closure that took the weak `self`: from its `{` (just before the capture list) on.
        opening = src.rfind('{', 0, m.start())
        closure = block(src, opening)
        for t in re.finditer(r'\bTask\b\s*(\([^)]*\))?\s*\{', closure):
            if re.search(r'\bself\b', block(closure, t.start())):
                found.append((src.count('\n', 0, m.start()) + 1, "a weak self read by a Task: hold it in a WeakBox, a constant"))
                break
    for t in re.finditer(r'\bTask\b\s*(\([^)]*\))?\s*\{', src):
        if re.search(r'\bdefer\s*\{', block(src, t.start())):
            found.append((src.count('\n', 0, t.start()) + 1, "a defer inside a Task: set it after the awaited call"))
    return found


def main(paths):
    bad = 0
    for path in paths:
        src = strip(open(path, encoding='utf-8').read())
        for line, why in problems(src):
            print(f"{path}:{line}: {why} (Swift 5.7 refuses it)")
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
