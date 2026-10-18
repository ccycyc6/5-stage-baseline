#!/usr/bin/env python3
import sys, re

def strip_displays(text):
    out = []
    i = 0
    while i < len(text):
        j = text.find('$display(', i)
        if j < 0:
            out.append(text[i:])
            break
        out.append(text[i:j])
        k = j + len('$display(')
        depth = 1
        in_str = False
        esc = False
        while k < len(text) and depth > 0:
            c = text[k]
            if in_str:
                if esc:
                    esc = False
                elif c == '\\':
                    esc = True
                elif c == '"':
                    in_str = False
            else:
                if c == '"':
                    in_str = True
                elif c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
            k += 1
        # include the trailing semicolon and whitespace
        while k < len(text) and text[k] in ' \t':
            k += 1
        if k < len(text) and text[k] == ';':
            k += 1
        i = k
    return ''.join(out)

for path in sys.argv[1:]:
    with open(path, 'r') as f:
        t = f.read()
    t2 = strip_displays(t)
    with open(path, 'w') as f:
        f.write(t2)
    print(path, 'removed', t.count('$display('), 'displays')
