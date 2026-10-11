import re, json, os, subprocess

# The Planetfall source isn't openly licensed, so it isn't committed; it's cloned on first run.
SRC = os.environ.get('PLANETFALL_SRC', '/tmp/planetfall-src')
if not os.path.isdir(SRC):
    subprocess.run(['git', 'clone', '-q', '--depth', '1', 'https://github.com/historicalsource/planetfall', SRC], check=True)
src = ''.join(open(f'{SRC}/{f}.zil', errors='replace').read() for f in ['globals','compone','comptwo'])
rooms = {}
DIRS = 'NORTH SOUTH EAST WEST NE NW SE SW UP DOWN IN OUT LAND'.split()
for m in re.finditer(r'<ROOM ([A-Z0-9-]+)(.*?)>\s*\n(?=\s*\n|<|;)', src, re.S):
    name, body = m.group(1), m.group(2)
    desc = re.search(r'\(DESC "([^"]*)"\)', body)
    cm = re.search(r'\(C-MOVE\s*<TABLE(.*?)>\)', body, re.S)
    lengths = {}
    if cm:
        for d, v in re.findall(r';"(\w+)"\s+(\d+)', cm.group(1)):
            if int(v): lengths[d] = int(v)
    exits = []
    for e in re.finditer(r'\((' + '|'.join(DIRS) + r') ((?:[^()"]|"[^"]*")*)\)', body):
        d, rest = e.group(1), e.group(2).strip()
        exits.append({'dir': d, 'raw': ' '.join(rest.split())})
    flags = re.search(r'\(FLAGS ([^)]*)\)', body)
    rooms[name] = {'desc': desc.group(1) if desc else name, 'lengths': lengths, 'exits': exits,
                   'flags': flags.group(1).split() if flags else []}
json.dump(rooms, open('rooms-raw.json', 'w'), indent=1)
print(len(rooms), 'rooms')
