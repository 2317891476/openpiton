import re, sys
# Replace every $display/$write statement (single OR multi-line) with a null ';'.
# [^;]* matches across newlines (char class, not '.'), so multi-line $display work.
# Keeps fail()/$finish (error detection) intact; only removes logging.
n = 0
for path in sys.argv[1:]:
    with open(path) as f: text = f.read()
    new, c1 = re.subn(r'\$display\b[^;]*;', ';', text)
    new, c2 = re.subn(r'\$write\b[^;]*;', ';', new)
    with open(path, 'w') as f: f.write(new)
    print(f"{path}: $display->{c1} $write->{c2}")
    n += c1 + c2
print(f"TOTAL silenced: {n}")
