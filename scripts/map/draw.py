"""Draws the full Planetfall map from the game's own room definitions (rooms-raw.json, parsed
from the ZIL source) plus a hand-made layout. Exits are drawn from the side of each room that
the game's direction names, so asymmetric exits show up as bent links."""
import json, math, html, sys

RAW = json.load(open('rooms-raw.json'))

# ---------------------------------------------------------------- layout (grid cells; y grows down)
POS = {
    # S.P.S. Feinstein
    'DECK-EIGHT': (1.8, 14.6), 'BRIG': (3.1, 14.6), 'GANGWAY': (1.8, 15.8),
    'DECK-NINE': (1.8, 17.0), 'ESCAPE-POD': (0.5, 17.0), 'REACTOR-LOBBY': (3.1, 17.0),
    # Coast and castle
    'UNDERWATER': (-1.3, 17.0), 'CRAG': (-1.3, 15.8), 'BALCONY': (-1.3, 14.6),
    'WINDING-STAIR': (-1.3, 13.4), 'COURTYARD': (-1.3, 12.2), 'WEST-WING': (-2.6, 12.2),
    'PLAIN-HALL': (-1.3, 7.2),
    # Kalamontee: residential
    'BOOTH-1': (-1.3, 3.6), 'CONFERENCE-ROOM': (-1.3, 4.8), 'REC-AREA': (-1.3, 6.0),
    'REC-CORRIDOR': (0, 6.0), 'DORM-B': (0, 4.8), 'SANFAC-B': (0, 3.6), 'DORM-A': (0, 7.2),
    'SANFAC-A': (0, 8.4), 'MESS-CORRIDOR': (1.3, 6.0), 'STORAGE-WEST': (1.3, 4.8),
    'MESS-HALL': (1.3, 7.2), 'KITCHEN': (1.3, 8.4), 'DORM-CORRIDOR': (2.6, 6.0),
    'DORM-D': (2.6, 4.8), 'SANFAC-D': (2.6, 3.6), 'DORM-C': (2.6, 7.2), 'SANFAC-C': (2.6, 8.4),
    # Kalamontee: admin
    'CORRIDOR-JUNCTION': (6.5, 6.0), 'ADMIN-CORRIDOR-S': (6.5, 4.8), 'SANFAC-E': (7.8, 4.8),
    'ADMIN-CORRIDOR': (6.5, 3.6), 'SYSTEMS-MONITORS': (5.2, 3.6), 'ADMIN-CORRIDOR-N': (6.5, 1.8),
    'PLAN-ROOM': (7.8, 1.8), 'SMALL-OFFICE': (5.2, 1.8), 'LARGE-OFFICE': (3.9, 1.8),
    'TRANSPORTATION-SUPPLY': (6.5, 0.6),
    # Kalamontee: mechanical
    'MECH-CORRIDOR-N': (6.5, 7.2), 'STORAGE-EAST': (7.8, 7.2), 'PHYSICAL-PLANT': (5.2, 7.8),
    'MECH-CORRIDOR': (6.5, 8.4), 'REACTOR-CONTROL': (7.8, 8.4), 'REACTOR-ELEVATOR': (9.1, 8.4),
    'REACTOR-ACCESS-STAIRS': (7.8, 9.6), 'MECH-CORRIDOR-S': (6.5, 9.6), 'TOOL-ROOM': (5.2, 10.8),
    'MACHINE-SHOP': (6.5, 10.8), 'ROBOT-SHOP': (7.8, 10.8),
    # Elevators
    'ELEVATOR-LOBBY': (9.1, 6.0), 'BOOTH-2': (10.4, 6.0),
    'UPPER-ELEVATOR': (9.1, 4.8), 'LOWER-ELEVATOR': (9.1, 7.2),
    # Tower (top of the blue elevator)
    'UPPER-ELEVATOR@top': (13.2, 1.8), 'TOWER-CORE': (13.2, 3.0), 'COMM-ROOM': (15.5, 1.8),
    'OBSERVATION-DECK': (11.9, 4.2), 'HELIPAD': (14.2, 1.8), 'HELICOPTER': (14.2, 0.6),
    # Bottom of the red elevator, and the shuttle line
    'LOWER-ELEVATOR@bottom': (4.95, 14.8), 'WAITING-AREA': (4.95, 13.6),
    'KALAMONTEE-PLATFORM': (6.25, 13.6),
    'SHUTTLE-CAR-BETTY': (8.85, 12.4), 'BETTY-CONTROL-WEST': (7.55, 12.4), 'BETTY-CONTROL-EAST': (10.15, 12.4),
    'SHUTTLE-CAR-ALFIE': (8.85, 14.8), 'ALFIE-CONTROL-WEST': (7.55, 14.8), 'ALFIE-CONTROL-EAST': (10.15, 14.8),
    'LAWANDA-PLATFORM': (11.45, 13.6),
    # Lawanda
    'ESCALATOR': (13.39, 11.1), 'FORK': (15.35, 8.6),
    'SYSTEMS-CORRIDOR-WEST': (16.65, 7.4), 'INFIRMARY': (15.35, 6.2), 'REPAIR-ROOM': (16.65, 6.2),
    'SYSTEMS-CORRIDOR': (17.95, 7.4), 'PLANETARY-DEFENSE': (17.95, 6.2),
    'SYSTEMS-CORRIDOR-EAST': (19.25, 7.4), 'PLANETARY-COURSE-CONTROL': (19.25, 6.2),
    'PHYSICAL-PLANT-TWO': (20.55, 7.4), 'LIBRARY-LOBBY': (19.25, 8.6), 'LIBRARY': (17.95, 8.6),
    'BOOTH-3': (20.55, 8.6),
    'PROJECT-CORRIDOR-WEST': (16.65, 9.8), 'SANFAC-F': (15.35, 9.8), 'PROJECT-CORRIDOR': (17.95, 9.8),
    'PROJECT-CORRIDOR-EAST': (19.25, 9.8), 'PROJCON-OFFICE': (17.95, 11.0),
    'CRYO-ELEVATOR': (17.95, 12.2), 'CRYO-ANTEROOM': (17.95, 13.5),
    'COMPUTER-ROOM': (19.25, 11.0), 'MINI-BOOTH': (19.25, 12.2),
    'MAIN-LAB': (21.85, 9.8), 'LAB-STORAGE': (21.85, 11.0),
    'RADIATION-LOCK-WEST': (23.15, 8.6), 'RADIATION-LOCK-EAST': (24.45, 8.6), 'RADIATION-LAB': (25.75, 8.6),
    'BIO-LOCK-WEST': (23.15, 11.0), 'BIO-LOCK-EAST': (24.45, 11.0), 'BIO-LAB': (25.75, 11.0),
    'LAB-OFFICE': (27.05, 11.0), 'AUXILIARY-BOOTH': (27.05, 12.2),
    # Inside the computer (miniaturized)
    'STATION-384': (21.35, 14.93), 'STRIP-NEAR-STATION': (22.65, 14.93),
    'MIDDLE-OF-STRIP': (22.65, 13.73), 'STRIP-NEAR-RELAY': (22.65, 12.53),
}

REGIONS = [  # title, rooms (bounding box drawn around them), tint
    ('S.P.S. Feinstein', ['DECK-EIGHT', 'BRIG', 'ESCAPE-POD', 'REACTOR-LOBBY'], '#5b7fa6'),
    ('Coast & Castle', ['UNDERWATER', 'COURTYARD', 'WEST-WING'], '#4f8f8a'),
    ('Kalamontee Complex', ['BOOTH-1', 'SANFAC-A', 'TRANSPORTATION-SUPPLY', 'BOOTH-2', 'ROBOT-SHOP',
                            'TOOL-ROOM', 'LARGE-OFFICE', 'REACTOR-ELEVATOR', 'PLAIN-HALL'], '#8a7a4f'),
    ('Tower', ['HELICOPTER', 'OBSERVATION-DECK', 'COMM-ROOM'], '#8a6a9a'),
    ('Shuttle Line', ['WAITING-AREA', 'LOWER-ELEVATOR@bottom', 'SHUTTLE-CAR-BETTY', 'ALFIE-CONTROL-EAST',
                      'BETTY-CONTROL-WEST', 'LAWANDA-PLATFORM'], '#6a8a5a'),
    ('Lawanda Complex', ['STATION-384', 'STRIP-NEAR-STATION', 'FORK', 'INFIRMARY', 'LAB-OFFICE', 'AUXILIARY-BOOTH', 'RADIATION-LAB',
                         'CRYO-ANTEROOM', 'SANFAC-F'], '#9a6a5a'),
    ('Inside the Computer (miniaturized)', ['STATION-384', 'STRIP-NEAR-RELAY'], '#5a6a9a'),
]

NAMES = {k: v['desc'] for k, v in RAW.items()}
NAMES['UPPER-ELEVATOR@top'] = 'Upper Elevator'
NAMES['LOWER-ELEVATOR@bottom'] = 'Lower Elevator'
NAMES['PHYSICAL-PLANT-TWO'] = 'Physical Plant'
NAMES['UPPER-ELEVATOR'] = 'Upper Elevator'
NAMES['LOWER-ELEVATOR'] = 'Lower Elevator'
NAMES['TRANSPORTATION-SUPPLY'] = 'Transportation Supply (dark)'
NAMES['MINI-BOOTH'] = 'Miniaturization Booth'
SUBTITLE = {'UPPER-ELEVATOR': 'blue door', 'LOWER-ELEVATOR': 'red door',
            'UPPER-ELEVATOR@top': 'at the top', 'LOWER-ELEVATOR@bottom': 'at the bottom',
            'SHUTTLE-CAR-ALFIE': 'starts west', 'SHUTTLE-CAR-BETTY': 'starts east'}

# ---------------------------------------------------------------- gates
# kind: door (opens freely), lock (a puzzle / item needed), story (opens with game events),
#       ride (vehicle or teleport), floyd (only Floyd fits)
DOOR_GATES = {
    'CORRIDOR-DOOR': None, 'GANGWAY-DOOR': None,
    'POD-DOOR': ('story', 'opens when the ship explodes'),
    'SHUTTLE-DOOR': None,
    'CONFERENCE-DOOR': ('lock', 'combination dial'),
    'STORAGE-WEST-DOOR': ('lock', 'padlock: key from the crevice'),
    'KITCHEN-DOOR': ('lock', 'kitchen access card'),
    'REACTOR-ELEVATOR-DOOR': ('door', 'button opens it'),
    'BIO-DOOR-WEST': ('door', None), 'BIO-DOOR-EAST': ('door', None),
    'RAD-DOOR-WEST': ('door', None), 'RAD-DOOR-EAST': ('door', None),
    'OFFICE-DOOR': ('door', None),
    'CRYO-ELEVATOR-DOOR': ('story', 'opens after the computer is fixed'),
    'NO-MICROBE': ('story', 'south: blocked while the microbe attacks'),
}

COMPASS = ['NORTH', 'NE', 'EAST', 'SE', 'SOUTH', 'SW', 'WEST', 'NW']
VEC = {'NORTH': (0, -1), 'SOUTH': (0, 1), 'EAST': (1, 0), 'WEST': (-1, 0),
       'NE': (1, -1), 'NW': (-1, -1), 'SE': (1, 1), 'SW': (-1, 1),
       'UP': (0.55, -1), 'DOWN': (-0.55, 1), 'IN': (0, 0), 'OUT': (0, 0)}
SHORT = {'NORTH': 'N', 'SOUTH': 'S', 'EAST': 'E', 'WEST': 'W', 'NE': 'NE', 'NW': 'NW',
         'SE': 'SE', 'SW': 'SW', 'UP': 'up', 'DOWN': 'down', 'IN': 'in', 'OUT': 'out'}

def instance(room, other):
    """Which drawn copy of a room an exit attaches to (the elevators appear at both ends)."""
    if room == 'UPPER-ELEVATOR' and other == 'TOWER-CORE': return 'UPPER-ELEVATOR@top'
    if room == 'LOWER-ELEVATOR' and other == 'WAITING-AREA': return 'LOWER-ELEVATOR@bottom'
    return room

# ---------------------------------------------------------------- collect exits
exits = []   # (from, dir, to, gate)
for room, v in RAW.items():
    if room not in POS and room != 'ROOMS': continue
    for e in v['exits']:
        raw = e['raw'].split()
        if raw[0] != 'TO': continue
        to = raw[1]
        gate = None
        if 'IF' in raw:
            flag = raw[raw.index('IF') + 1]
            gate = DOOR_GATES.get(flag)
        exits.append((room, e['dir'], to, gate))

# Exits the game computes in code (PER routines), written out by hand from those routines.
L = ('lock', None)
special = [
    ('DECK-NINE', 'WEST', 'ESCAPE-POD', ('story', 'opens when the ship explodes')),
    ('ESCAPE-POD', 'EAST', 'DECK-NINE', None),
    ('DORM-CORRIDOR', 'EAST', 'CORRIDOR-JUNCTION', None),
    ('CORRIDOR-JUNCTION', 'WEST', 'DORM-CORRIDOR', None),
    ('ADMIN-CORRIDOR', 'NORTH', 'ADMIN-CORRIDOR-N', ('lock', 'rift: lay the ladder across')),
    ('ADMIN-CORRIDOR-N', 'SOUTH', 'ADMIN-CORRIDOR', ('lock', 'rift: lay the ladder across')),
    ('ELEVATOR-LOBBY', 'NORTH', 'UPPER-ELEVATOR', ('lock', 'upper elevator card')),
    ('UPPER-ELEVATOR', 'SOUTH', 'ELEVATOR-LOBBY', None),
    ('ELEVATOR-LOBBY', 'SOUTH', 'LOWER-ELEVATOR', ('lock', 'lower elevator card')),
    ('LOWER-ELEVATOR', 'NORTH', 'ELEVATOR-LOBBY', None),
    ('UPPER-ELEVATOR@top', 'SOUTH', 'TOWER-CORE', None),
    ('WAITING-AREA', 'SOUTH', 'LOWER-ELEVATOR@bottom', ('door', 'call the elevator')),
    ('LOWER-ELEVATOR@bottom', 'NORTH', 'WAITING-AREA', None),
    ('KALAMONTEE-PLATFORM', 'NORTH', 'SHUTTLE-CAR-BETTY', ('story', 'when Betty is here')),
    ('KALAMONTEE-PLATFORM', 'SOUTH', 'SHUTTLE-CAR-ALFIE', ('story', 'when Alfie is here')),
    ('LAWANDA-PLATFORM', 'NORTH', 'SHUTTLE-CAR-BETTY', ('story', 'when Betty is here')),
    ('LAWANDA-PLATFORM', 'SOUTH', 'SHUTTLE-CAR-ALFIE', ('story', 'when Alfie is here')),
    ('SHUTTLE-CAR-BETTY', 'SOUTH', 'KALAMONTEE-PLATFORM', None),
    ('SHUTTLE-CAR-BETTY', 'SOUTH', 'LAWANDA-PLATFORM', None),
    ('SHUTTLE-CAR-ALFIE', 'NORTH', 'KALAMONTEE-PLATFORM', None),
    ('SHUTTLE-CAR-ALFIE', 'NORTH', 'LAWANDA-PLATFORM', None),
    ('CRYO-ELEVATOR', 'NORTH', 'PROJCON-OFFICE', None),
    ('BALCONY', 'DOWN', 'CRAG', ('story', 'floods on day 2')),
    ('WINDING-STAIR', 'DOWN', 'BALCONY', ('story', 'floods on day 4')),
]
exits += special

# Rides: not exits, but ways the game moves you. (from, to, label, one_way)
RIDES = [  # from, port, to, port, curve reach (px), label, one-way

    ('ESCAPE-POD', 'SOUTH', 'UNDERWATER', 'SOUTH', 70, 'the pod launches and sinks offshore', True),
    ('CRYO-ELEVATOR', 'SOUTH', 'CRYO-ANTEROOM', 'NORTH', 30, 'endgame: the elevator descends', True),
    ('MINI-BOOTH', 'SOUTH', 'STATION-384', 'WEST', 200, 'type 384 (miniaturization card)', False),
    ('REACTOR-LOBBY', 'NORTH', 'BRIG', 'SOUTH', 30, 'Blather drags you here', True),
]
# Elevator shafts drawn as routed paths (grid points between the two ends).
SHAFTS = [  # from, port, waypoints, to, port, label, label position (grid)
    ('UPPER-ELEVATOR', 'NORTH', [(9.1, 1.8)], 'UPPER-ELEVATOR@top', 'WEST',
     'blue elevator: up / down', (10.9, 1.8)),
    ('LOWER-ELEVATOR', 'EAST', [(10.75, 7.2), (10.75, 11.55), (4.0, 11.55), (4.0, 14.8)], 'LOWER-ELEVATOR@bottom', 'WEST',
     'red elevator: down / up', (7.0, 11.55)),
    ('STATION-384', 'SOUTH', [(21.35, 15.62), (27.05, 15.62)], 'AUXILIARY-BOOTH', 'SOUTH',
     'once the computer is fixed, you return here', (24.6, 15.62)),
]
ONE_WAY_SHAFTS = {'STATION-384'}

BADGES = {  # notes under a room
    'BOOTH-1': 'teleport (card)', 'BOOTH-2': 'teleport (card)',
    'BOOTH-3': 'teleport (card)',
}
SHUTTLE_TRACK = ('KALAMONTEE-PLATFORM', 'LAWANDA-PLATFORM')

# Exits the game refuses with a message worth showing (stubs).
STUBS = [
    ('REPAIR-ROOM', 'NORTH', 'robot-sized door: Floyd only'),
    ('UNDERWATER', 'WEST', 'N, S, W, down: you swim in place'),
    ('TRANSPORTATION-SUPPLY', 'NORTH', 'N, E, W: lost in the dark'),
    ('REACTOR-ACCESS-STAIRS', 'DOWN', 'down: the stairs loop'),
    ('STRIP-NEAR-RELAY', 'EAST', 'the relay (sealed)'),
    ('REACTOR-LOBBY', 'SOUTH', 'E, S: Blather blocks you'),
    ('DECK-EIGHT', 'NORTH', 'N, E, W: Blather blocks you'),
]

# ---------------------------------------------------------------- geometry
GX, GY = 112, 92          # px per grid cell
BW, BH = 96, 52           # room box size
PAD = 70

VEHICLES = ('UPPER-ELEVATOR', 'LOWER-ELEVATOR', 'SHUTTLE-CAR-ALFIE', 'SHUTTLE-CAR-BETTY',
            'CRYO-ELEVATOR', 'REACTOR-ELEVATOR', 'ESCAPE-POD', 'HELICOPTER')

def size(r):
    """Vehicles (elevators, shuttle cars, the pod) are drawn a little smaller than rooms."""
    if r in CONTAINERS: return CONTAINERS[r]
    return (90, 46) if r.split('@')[0] in VEHICLES else (BW, BH)

# Rooms drawn as a larger box with a vehicle parked inside (no link drawn between them).
CONTAINERS = {}
INSIDE = set()

def center(r):
    x, y = POS[r]
    return x * GX, y * GY

def port(r, d):
    cx, cy = center(r)
    w, h = size(r)
    hw, hh = w / 2, h / 2
    off = {'NORTH': (0, -hh), 'SOUTH': (0, hh), 'EAST': (hw, 0), 'WEST': (-hw, 0),
           'NE': (hw - 4, -hh + 4), 'NW': (-hw + 4, -hh + 4), 'SE': (hw - 4, hh - 4), 'SW': (-hw + 4, hh - 4),
           'UP': (hw * 0.55, -hh), 'DOWN': (-hw * 0.55, hh)}[d]
    return cx + off[0], cy + off[1]

def facing(a, b):
    """The compass side of room a that faces room b (for one-way arrivals and rides)."""
    ax, ay = center(a); bx, by = center(b)
    ang = math.degrees(math.atan2(-(by - ay), bx - ax)) % 360
    return ['EAST', 'NE', 'NORTH', 'NW', 'WEST', 'SW', 'SOUTH', 'SE'][int(((ang + 22.5) % 360) // 45)]

def curve(p1, d1, p2, d2, reach=None):
    dist = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
    k = reach or min(60, max(18, dist * 0.38))
    v1 = VEC[d1]; v2 = VEC[d2]
    n1 = math.hypot(*v1) or 1; n2 = math.hypot(*v2) or 1
    c1 = (p1[0] + v1[0] / n1 * k, p1[1] + v1[1] / n1 * k)
    c2 = (p2[0] + v2[0] / n2 * k, p2[1] + v2[1] / n2 * k)
    return p1, c1, c2, p2

def bez(pts, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = pts
    u = 1 - t
    return (u**3*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x3, u**3*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y3)

OPPOSITE = {'NORTH': 'SOUTH', 'SOUTH': 'NORTH', 'EAST': 'WEST', 'WEST': 'EAST', 'NE': 'SW', 'SW': 'NE',
            'NW': 'SE', 'SE': 'NW', 'UP': 'DOWN', 'DOWN': 'UP'}

def path_d(pts):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = pts
    return f'M{x0:.1f},{y0:.1f} C{x1:.1f},{y1:.1f} {x2:.1f},{y2:.1f} {x3:.1f},{y3:.1f}'

# ---------------------------------------------------------------- pair up exits into links
def pref(dirs):
    for d in COMPASS + ['UP', 'DOWN']:
        if d in dirs: return d
    return None

links = {}
for a, d, b, gate in exits:
    a2, b2 = instance(a, b), instance(b, a)
    if a2 == b2: continue          # loops (drawn as stubs)
    if tuple(sorted([a2, b2])) in INSIDE: continue   # the vehicle is drawn inside the room
    if a2 not in POS or b2 not in POS: print('missing', a2, b2, file=sys.stderr); continue
    key = tuple(sorted([a2, b2]))
    L_ = links.setdefault(key, {'dirs': {}, 'gates': []})
    L_['dirs'].setdefault(a2, []).append(d)
    if gate and gate not in L_['gates']: L_['gates'].append(gate)

# ---------------------------------------------------------------- draw
EXTRA = {'Lawanda Complex': (0, 0, 0, 50)}   # left, top, right, bottom

def region_rect(title, members):
    pts = [center(m) for m in members]
    l, t, r, b = EXTRA.get(title, (0, 0, 0, 0))
    return (min(p[0] for p in pts) - BW / 2 - 16 - l, min(p[1] for p in pts) - BH / 2 - 30 - t,
            max(p[0] for p in pts) + BW / 2 + 16 + r, max(p[1] for p in pts) + BH / 2 + 16 + b)


OWNER = [None]   # the room a gate label belongs to, while a link is drawn

def region_of(room):
    """The innermost region drawn around a room."""
    best = None
    for title, members, _ in REGIONS:
        x0, y0, x1, y1 = region_rect(title, members)
        cx, cy = center(room)
        if x0 <= cx <= x1 and y0 <= cy <= y1 and (best is None or (x1 - x0) * (y1 - y0) < best[1]):
            best = (title, (x1 - x0) * (y1 - y0))
    return best[0] if best else None

START = 'DECK-NINE'          # where the game starts: the static map's "you are here"
HERE_INSET, HERE_R = 11, 8.5  # the marker's center sits this far in from a room's lower-right corner
HERE_RED = '#d62a1e'

def you_are_here(x, y, r=HERE_R):
    """A red disc with a white five-pointed star, centered at (x, y)."""
    pts = []
    for i in range(10):
        ang = math.radians(-90 + 36 * i)
        rad = r * (0.66 if i % 2 == 0 else 0.27)
        pts.append(f'{x + rad * math.cos(ang):.2f},{y + rad * math.sin(ang) + r * 0.04:.2f}')
    return (f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r}" fill="{HERE_RED}" stroke="#ffffff" stroke-width="1.2"/>'
            f'<polygon points="{" ".join(pts)}" fill="#ffffff"/>')

def render(notes, path=None, mark_start=False):
    """Draws the map. `notes` are the room notes found by a first pass, which the region boxes grow to hold."""

    RECTS = {title: region_rect(title, members) for title, members, _ in REGIONS}
    for region, (x0, y0, x1, y1) in (notes or []):
        l, t, r, b = RECTS[region]
        if y0 < t + 30:   # a note up in the title band: lift the top so the title clears it
            t = min(t, y0 - 32)
        RECTS[region] = (min(l, x0 - 12), t, max(r, x1 + 12), max(b, y1 + 10))
    # keep the agreed alignments: tower and Kalamontee tops, Feinstein and coast bottoms,
    # and Lawanda wrapping the computer
    kt = min(RECTS['Kalamontee Complex'][1], RECTS['Tower'][1])
    for k in ('Kalamontee Complex', 'Tower'): RECTS[k] = (RECTS[k][0], kt) + RECTS[k][2:]
    fb = max(RECTS['S.P.S. Feinstein'][3], RECTS['Coast & Castle'][3])
    for k in ('S.P.S. Feinstein', 'Coast & Castle'): RECTS[k] = RECTS[k][:3] + (fb,)
    booth_top = center('MINI-BOOTH')[1] - BH / 2   # the computer's box starts level with the booths' tops
    c = RECTS['Inside the Computer (miniaturized)']
    RECTS['Inside the Computer (miniaturized)'] = (c[0], booth_top, c[2], c[3])
    comp, law = RECTS['Inside the Computer (miniaturized)'], RECTS['Lawanda Complex']
    RECTS['Lawanda Complex'] = (min(law[0], comp[0] - 18), law[1], max(law[2], comp[2] + 18), max(law[3], comp[3] + 18))
    left = min(r[0] for r in RECTS.values()); right = max(r[2] for r in RECTS.values())
    bottom = max(r[3] for r in RECTS.values())
    kal = RECTS['Kalamontee Complex']
    top = min(r[1] for r in RECTS.values())
    EDGE = 60                                   # even margin on every side
    W = right - left + 2 * EDGE; H = bottom - top + 2 * EDGE
    ox, oy = EDGE - left, EDGE - top

    # the legend and compass sit side by side, centered in the space right of the tower, above Lawanda
    band = (RECTS['Tower'][2], kal[1], RECTS['Lawanda Complex'][2], RECTS['Lawanda Complex'][1])
    LEGEND_W, LEGEND_H, COMPASS_R, GAP = 560, 22 + 9 * 25, 84, 110
    COMPASS_SPAN = 2 * (COMPASS_R + 40)
    block_w = LEGEND_W + GAP + COMPASS_SPAN
    bx = band[0] + (band[2] - band[0] - block_w) / 2
    TITLE_BIG, TITLE_SMALL = 128, 96
    TITLE_CAP, TITLE_GAP = 92, 46
    body_h = max(LEGEND_H, COMPASS_SPAN)
    group_top = (band[1] + band[3]) / 2 - (TITLE_CAP + TITLE_GAP + body_h) / 2
    TITLE_BASE = group_top + TITLE_CAP
    by = group_top + TITLE_CAP + TITLE_GAP + body_h / 2
    LEGEND_AT = (bx, by - LEGEND_H / 2 + 10)
    COMPASS_AT = (bx + LEGEND_W + GAP + COMPASS_SPAN / 2, by)

    C = {'bg': '#f6f1e4', 'ink': '#1f2a44', 'room': '#ffffff', 'line': '#1f2a44', 'door': '#1f2a44',
         'lock': '#2563c9', 'story': '#7d3c98', 'ride': '#1f7a8c', 'floyd': '#b9770e', 'stub': '#7f8c8d'}
    out = []
    A = out.append
    A(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" viewBox="0 0 {W:.0f} {H:.0f}" '
      f'font-family="Avenir Next, Helvetica Neue, Helvetica, sans-serif">')
    A(f'<rect width="100%" height="100%" fill="{C["bg"]}"/>')
    A('<defs>')
    for name, col in [('arrow', C['line']), ('arrowStory', C['story']), ('arrowRide', C['ride']), ('arrowLock', C['lock'])]:
        A(f'<marker id="{name}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
          f'<path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
    A('</defs>')
    A(f'<g transform="translate({ox:.1f},{oy:.1f})">')
    # Futura's P has a side bearing; pull the title left so its ink starts at the legend's edge
    A(f'<text class="chrome" x="{LEGEND_AT[0] - TITLE_BIG * 0.0915:.1f}" y="{TITLE_BASE:.0f}" font-family="Futura, Futura PT, Century Gothic, sans-serif" font-weight="500" '
      f'letter-spacing="6" fill="{C["ink"]}"><tspan font-size="{TITLE_BIG}">P</tspan><tspan font-size="{TITLE_SMALL}">LANET</tspan>'
      f'<tspan font-size="{TITLE_BIG}">F</tspan><tspan font-size="{TITLE_SMALL}">ALL</tspan></text>')

    # regions
    for title, members, tint in REGIONS:
        x0, y0, x1, y1 = RECTS[title]
        inside = ' '.join(r for r in POS if region_of(r) == title)
        A(f'<g data-region="{html.escape(title)}" data-rooms="{inside}">')
        A(f'<rect x="{x0:.0f}" y="{y0:.0f}" width="{x1 - x0:.0f}" height="{y1 - y0:.0f}" rx="18" fill="{tint}" fill-opacity="0.10" stroke="{tint}" stroke-opacity="0.55" stroke-width="1.5"/>')
        A(f'<text x="{x0 + 12:.0f}" y="{y0 + 19:.0f}" font-size="14" font-weight="700" letter-spacing="1.2" fill="{tint}">{html.escape(title.upper())}</text>')
        A('</g>')

    labels = []   # drawn last so they sit on top

    def gate_marker(pts, gate, t=0.5):
        kind, text = gate
        x, y = bez(pts, t)
        col = C[kind]
        if kind == 'door':
            # a short bar across the line
            x2, y2 = bez(pts, min(1, t + 0.02)); ang = math.degrees(math.atan2(y2 - y, x2 - x))
            A(f'<rect x="{x - 2.5:.1f}" y="{y - 8:.1f}" width="5" height="16" fill="{col}" transform="rotate({ang:.1f} {x:.1f} {y:.1f})"/>')
        else:
            glyph = {'lock': '\U0001F512', 'story': '?', 'floyd': '⚙'}.get(kind, '?')
            if kind == 'story': A('<g class="clue">')   # a hint: hidden on the explored map
            A(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="9" fill="{col}"/>')
            if kind == 'lock':
                # a padlock drawn in lines (emoji don't print reliably)
                A(f'<rect x="{x - 4:.1f}" y="{y - 1:.1f}" width="8" height="6" rx="1" fill="#fff"/>'
                  f'<path d="M{x - 2.5:.1f},{y - 1:.1f} v-2.5 a2.5,2.5 0 0 1 5,0 v2.5" fill="none" stroke="#fff" stroke-width="1.6"/>')
            else:
                A(f'<text x="{x:.1f}" y="{y + 4:.1f}" font-size="13" font-weight="800" text-anchor="middle" fill="#fff">{glyph}</text>')
            if kind == 'story': A('</g>')
        if text:
            (sx, sy), (ex, ey) = pts[0], pts[3]
            side = abs(ey - sy) > abs(ex - sx)
            if not side and math.hypot(ex - sx, ey - sy) < 90: y -= 26   # short link: label above the rooms
            labels.append((x, y, text, col, side, OWNER[0]))

    NO_TAGS = {('LIBRARY', 'LIBRARY-LOBBY')}   # side by side; the drawing says enough
    ESCALATOR_LINKS = {tuple(sorted(p)) for p in (('LAWANDA-PLATFORM', 'ESCALATOR'), ('ESCALATOR', 'FORK'))}

    def escalator_path(lo, hi):
        """From the lower room's east side to the upper room's west side, shaped like an escalator."""
        h, r = 24, 16
        (ax, ay), (dx, dy) = lo, hi
        bx, by, cx_, cy_ = ax + h, ay, dx - h, dy
        ln = math.hypot(cx_ - bx, cy_ - by); ux, uy = (cx_ - bx) / ln, (cy_ - by) / ln
        return (f'M{ax:.1f},{ay:.1f} L{bx - r:.1f},{by:.1f} Q{bx:.1f},{by:.1f} {bx + ux * r:.1f},{by + uy * r:.1f} '
                f'L{cx_ - ux * r:.1f},{cy_ - uy * r:.1f} Q{cx_:.1f},{cy_:.1f} {cx_ + r:.1f},{cy_:.1f} L{dx:.1f},{dy:.1f}')

    for (a, b), L_ in links.items():
        da, db = L_['dirs'].get(a), L_['dirs'].get(b)
        pa, pb = pref(da) if da else None, pref(db) if db else None
        if pa is None and da: pa = facing(a, b)      # only in/out given
        if pb is None and db: pb = facing(b, a)
        one_way = not (da and db)
        if one_way:
            src, dst, ds = (a, b, pa) if da else (b, a, pb)
            dd = facing(dst, src)
            pts = curve(port(src, ds), ds, port(dst, dd), dd)
        else:
            src, dst = a, b
            pts = curve(port(a, pa), pa, port(b, pb), pb)
            boarding = {a, b} & {'SHUTTLE-CAR-ALFIE', 'SHUTTLE-CAR-BETTY'}   # boarding links keep their curves
            if OPPOSITE.get(pa) == pb and pa not in ('UP', 'DOWN') and not boarding:   # plain two-way passage: straight
                (x0, y0_), (x3, y3) = pts[0], pts[3]
                pts = ((x0, y0_), (x0 + (x3 - x0) / 3, y0_ + (y3 - y0_) / 3),
                       (x0 + 2 * (x3 - x0) / 3, y0_ + 2 * (y3 - y0_) / 3), (x3, y3))
        A(f'<g data-link="{a} {b}">')
        gates = L_['gates']
        col = C['line']
        dash = ''
        if any(g[0] == 'story' for g in gates): col = C['story']
        if any(g[0] == 'lock' for g in gates): col = C['lock']
        marker = ' marker-end="url(#arrowStory)"' if one_way and col == C['story'] else (' marker-end="url(#arrow)"' if one_way else '')
        width = 2.4
        escalator = (a, b) in ESCALATOR_LINKS
        if escalator:
            lo, hi = (a, b) if center(a)[1] > center(b)[1] else (b, a)
            lo_p, hi_p = port(lo, 'EAST'), port(hi, 'WEST')
            A(f'<path d="{escalator_path(lo_p, hi_p)}" fill="none" stroke="{col}" stroke-width="{width}"/>')
            tag_at = {lo: (lo_p[0] + 20, lo_p[1] + 14), hi: (hi_p[0] - 22, hi_p[1] - 8)}
        else:
            story = ' class="story-line"' if col == C['story'] else ''
            A(f'<path{story} d="{path_d(pts)}" fill="none" stroke="{col}" stroke-width="{width}"{dash}{marker}/>')
        # direction tags at each end when the link is bent or vertical
        # Compass exits read from the drawing. Tags mark up/down (with every direction that end
        # accepts, e.g. "S/down") and links you can only take with in/out.
        vertical = any(d in ('UP', 'DOWN') for ds in L_['dirs'].values() for d in ds)
        if (a, b) in NO_TAGS: vertical = False
        for r, dirs, t in ((src, L_['dirs'].get(src), 0.0), (dst, L_['dirs'].get(dst), 1.0)):
            if not dirs: continue
            if vertical:
                shown = [d for d in COMPASS + ['UP', 'DOWN'] if d in dirs]
            elif all(d in ('IN', 'OUT') for ds in L_['dirs'].values() for d in ds):
                if t == 0:   # an in/out-only link gets one label at its middle
                    mx, my = bez(pts, 0.5)
                    upright = abs(pts[3][1] - pts[0][1]) > abs(pts[3][0] - pts[0][0])
                    mx, my, anc = (mx + 7, my + 10, 'start') if upright else (mx, my, 'middle')
                    A(f'<text x="{mx:.1f}" y="{my - 7:.1f}" font-size="9.5" text-anchor="{anc}" fill="{C["ink"]}" '
                      f'stroke="{C["bg"]}" stroke-width="3" paint-order="stroke" font-weight="600">in / out</text>')
                continue
            elif all(d in ('IN', 'OUT') for d in dirs):
                shown = dirs[:1]
            else:
                continue
            tag = '/'.join(SHORT[d] for d in shown)
            x, y = tag_at[r] if escalator else bez(pts, 0.16 if t == 0 else 0.84)
            A(f'<text x="{x:.1f}" y="{y + 3:.1f}" font-size="9.5" text-anchor="middle" fill="{C["ink"]}" '
              f'stroke="{C["bg"]}" stroke-width="3" paint-order="stroke" font-weight="600">{tag}</text>')
        OWNER[0] = a if region_of(a) == region_of(b) else None
        for i, g in enumerate(gates):
            gate_marker(pts, g, 0.5 + 0.12 * i)
        OWNER[0] = None
        A('</g>')
        if (a, b) in [tuple(sorted(['DORM-CORRIDOR', 'CORRIDOR-JUNCTION']))]:
            x, y = bez(pts, 0.5)
            labels.append((x, y - 4, 'a long, featureless hallway (160 moves of walking time)', C['ink'], False))

    # rides
    LABEL_AT = {'UPPER-ELEVATOR': 0.3, 'STATION-384': 0.93}
    for a, da, b, db, reach, text, one in RIDES:
        pts = curve(port(a, da), da, port(b, db), db, reach)
        A(f'<g class="ride" data-link="{a} {b}">')
        m = ' marker-end="url(#arrowRide)"' if one else ' marker-end="url(#arrowRide)" marker-start="url(#arrowRide)"'
        A(f'<path d="{path_d(pts)}" fill="none" stroke="{C["ride"]}" stroke-width="2.2" stroke-dasharray="7 5"{m}/>')
        A('</g>')
        x, y = bez(pts, LABEL_AT.get(a, 0.5))
        if a == 'ESCAPE-POD': y += 18   # under the dip, clear of the boxes
        x2, y2 = bez(pts, LABEL_AT.get(a, 0.5) + 0.02)
        labels.append((x, y, text, C['ride'], 'end' if a == 'STATION-384' else abs(y2 - y) > abs(x2 - x)))

    for a, da, way, b, db, text, (lx_, ly_) in SHAFTS:
        pts = [port(a, da)] + [(x * GX, y * GY) for x, y in way] + [port(b, db)]
        d = 'M' + ' L'.join(f'{x:.1f},{y:.1f}' for x, y in pts)
        A(f'<g class="ride" data-link="{a} {b}">')
        A(f'<path d="{d}" fill="none" stroke="{C["ride"]}" stroke-width="2.2" stroke-dasharray="7 5" stroke-linejoin="round" '
          f'marker-end="url(#arrowRide)"' + ('' if a in ONE_WAY_SHAFTS else ' marker-start="url(#arrowRide)"') + '/>')
        A('</g>')
        labels.append((lx_ * GX, ly_ * GY + 2, text, C['ride'], lx_ * GX == pts[1][0]))

    # shuttle track: rails between the platforms, passing both cars' rows
    k1, k2 = center(SHUTTLE_TRACK[0]), center(SHUTTLE_TRACK[1])
    for yrow, car in ((POS['SHUTTLE-CAR-BETTY'][1], 'Betty'), (POS['SHUTTLE-CAR-ALFIE'][1], 'Alfie')):
        y = yrow * GY
        x0, x1 = k1[0], k2[0]
        A(f'<g data-any="SHUTTLE-CAR-{car.upper()}">')
        # a maglev guideway: a soft glow between two thin rails, capped at each platform
        A(f'<path d="M{x0:.0f},{y:.0f} H{x1:.0f}" stroke="{C["ride"]}" stroke-width="10" stroke-opacity="0.10" stroke-linecap="round"/>')
        for dy in (-4, 4):
            A(f'<path d="M{x0:.0f},{y + dy:.0f} H{x1:.0f}" stroke="{C["ride"]}" stroke-width="1.3" stroke-opacity="0.75"/>')
        for x in (x0, x1):
            A(f'<path d="M{x:.0f},{y - 8:.0f} V{y + 8:.0f}" stroke="{C["ride"]}" stroke-width="3" stroke-linecap="round"/>')
        A('</g>')
    labels.append(((k1[0] + k2[0]) / 2, k1[1] + 4, 'shuttle line: put the shuttle card in a control cabin and ride', C['ride'], False))

    # stubs
    for r, d, text in STUBS:
        p = port(r, d); v = VEC[d]; n = math.hypot(*v)
        q = (p[0] + v[0] / n * 22, p[1] + v[1] / n * 22)
        A('<g class="clue">')
        A(f'<path d="M{p[0]:.1f},{p[1]:.1f} L{q[0]:.1f},{q[1]:.1f}" stroke="{C["stub"]}" stroke-width="2" stroke-dasharray="3 3"/>')
        A(f'<circle cx="{q[0]:.1f}" cy="{q[1]:.1f}" r="3" fill="{C["stub"]}"/>')
        A('</g>')
        if d == 'WEST':   # read leftward from the stub's end
            labels.append((q[0] + 6, q[1] - 4, text, C['stub'], 'end', r))
        elif d == 'EAST':   # read rightward from the stub's end
            labels.append((q[0] - 8, q[1] - 4, text, C['stub'], True, r))
        else:
            labels.append((q[0] + v[0] / n * 6, q[1] + v[1] / n * 10 + (14 if d == 'SOUTH' else 0), text, C['stub'], False, r))

    # rooms
    def wrap(s, n=14):
        words, lines, cur = s.split(), [], ''
        for w in words:
            if len(cur) + len(w) + 1 > n and cur: lines.append(cur); cur = w
            else: cur = (cur + ' ' + w).strip()
        lines.append(cur); return lines

    for r in POS:
        cx, cy = center(r)
        kind_fill = C['room']
        stroke = C['ink']
        special_room = r.split('@')[0] in VEHICLES
        bw, bh = size(r)
        booth = r in ('BOOTH-1', 'BOOTH-2', 'BOOTH-3', 'MINI-BOOTH', 'AUXILIARY-BOOTH', 'STATION-384')
        if special_room: kind_fill = '#e3f1f4'
        if booth: kind_fill = '#e8eefc'
        A(f'<g data-room="{r}">')
        A(f'<rect x="{cx - bw/2:.1f}" y="{cy - bh/2:.1f}" width="{bw}" height="{bh}" rx="{14 if special_room else 7}" fill="{kind_fill}" stroke="{stroke}" stroke-width="1.6"/>')
        lines = wrap(NAMES[r])
        sub = SUBTITLE.get(r)
        total = len(lines) + (1 if sub else 0)
        y0 = cy - (total - 1) * 6.5 + 4
        if r in CONTAINERS: y0 = cy - bh / 2 + 17   # name at the top, the vehicle below it
        for i, ln in enumerate(lines):
            A(f'<text x="{cx:.1f}" y="{y0 + i * 13:.1f}" font-size="11.5" font-weight="600" text-anchor="middle" fill="{C["ink"]}">{html.escape(ln)}</text>')
        if sub:
            A(f'<text x="{cx:.1f}" y="{y0 + len(lines) * 13 - 1:.1f}" font-size="9" font-style="italic" text-anchor="middle" fill="{C["ink"]}" opacity="0.7">{html.escape(sub)}</text>')
        A('</g>')

    if mark_start:   # the static map shows where the game starts
        cx, cy = center(START); w, h = size(START)
        A(you_are_here(cx + w / 2 - HERE_INSET, cy + h / 2 - HERE_INSET))
    else:   # the game moves this one onto the player's room
        A(f'<g id="here" style="display:none">{you_are_here(0, 0)}</g>')

    # labels on top
    for r, text in BADGES.items():
        cx, cy = center(r)
        labels.append((cx, cy + BH / 2 + 24, text, C['ride'], False, r))
    owned = []   # (region, box) for notes that belong to a room, so its region can grow to hold them
    for x, y, text, col, side, *owner in labels:
        if side == 'end': x, y, anchor = x - 14, y + 16, 'end'
        elif side: x, y, anchor = x + 14, y + 16, 'start'
        else: anchor = 'middle'
        if owner and owner[0]:
            w = len(text) * 5.5
            x0 = {'middle': x - w / 2, 'start': x, 'end': x - w}[anchor]
            owned.append((region_of(owner[0]), (x0, y - 22, x0 + w, y - 9)))
        A(f'<text class="clue" x="{x:.1f}" y="{y - 12:.1f}" font-size="9.5" text-anchor="{anchor}" fill="{col}" '
          f'stroke="{C["bg"]}" stroke-width="3.5" paint-order="stroke" font-weight="600">{html.escape(text)}</text>')

    # The title, compass, and legend only appear on the full map.
    A('<g class="chrome">')
    # compass rose: octagonal frame, tick ring, eight-point star, ship's-wheel hub
    def octagon(cx, cy, r):
        return ' '.join(f'{cx + r * math.cos(math.radians(22.5 + 45 * i)):.1f},{cy + r * math.sin(math.radians(22.5 + 45 * i)):.1f}' for i in range(8))

    (rx, ry), R = COMPASS_AT, COMPASS_R
    ink = C['ink']
    A(f'<polygon points="{octagon(rx, ry, R)}" fill="{C["bg"]}" stroke="{ink}" stroke-width="5" stroke-linejoin="miter"/>')
    A(f'<polygon points="{octagon(rx, ry, R - 9)}" fill="none" stroke="{ink}" stroke-width="1.4"/>')
    for deg in range(0, 360, 5):   # tick ring
        t = math.radians(deg); r0, r1 = (R - 30, R - 19) if deg % 45 else (R - 32, R - 16)
        A(f'<line x1="{rx + math.sin(t) * r0:.1f}" y1="{ry - math.cos(t) * r0:.1f}" x2="{rx + math.sin(t) * r1:.1f}" '
          f'y2="{ry - math.cos(t) * r1:.1f}" stroke="{ink}" stroke-width="{1.6 if deg % 45 == 0 else 0.9}"/>')

    def point(deg, length, half, root):
        """One point of the star: a solid blade with a thin light line down its spine."""
        t = math.radians(deg)
        tip = (rx + math.sin(t) * length, ry - math.cos(t) * length)
        base = (rx + math.sin(t) * root, ry - math.cos(t) * root)
        l = (base[0] + math.sin(t - math.pi / 2) * half, base[1] - math.cos(t - math.pi / 2) * half)
        r_ = (base[0] + math.sin(t + math.pi / 2) * half, base[1] - math.cos(t + math.pi / 2) * half)
        A(f'<path d="M{rx:.1f},{ry:.1f} L{l[0]:.1f},{l[1]:.1f} L{tip[0]:.1f},{tip[1]:.1f} L{r_[0]:.1f},{r_[1]:.1f} z" fill="{ink}" stroke="{ink}" stroke-width="1" stroke-linejoin="miter"/>')
        s0 = (rx + math.sin(t) * (root + 6), ry - math.cos(t) * (root + 6))
        s1 = (rx + math.sin(t) * (length - 12), ry - math.cos(t) * (length - 12))
        A(f'<path d="M{s0[0]:.1f},{s0[1]:.1f} L{s1[0]:.1f},{s1[1]:.1f}" stroke="{C["bg"]}" stroke-width="1.6" stroke-linecap="round"/>')

    for deg in (45, 135, 225, 315):
        point(deg, R - 20, 9, 30)
    for deg in (0, 90, 180, 270):
        point(deg, R + 16, 11, 30)
    # hub: a ship's wheel of rings and spokes
    A(f'<circle cx="{rx}" cy="{ry}" r="31" fill="{ink}"/>')
    A(f'<circle cx="{rx}" cy="{ry}" r="26" fill="{C["bg"]}"/>')
    A(f'<circle cx="{rx}" cy="{ry}" r="22" fill="{ink}"/>')
    for i in range(12):
        t = math.radians(i * 30 + 15)
        A(f'<path d="M{rx + math.sin(t) * 12:.1f},{ry - math.cos(t) * 12:.1f} L{rx + math.sin(t) * 20:.1f},{ry - math.cos(t) * 20:.1f}" stroke="{C["bg"]}" stroke-width="3.2" stroke-linecap="round"/>')
    A(f'<circle cx="{rx}" cy="{ry}" r="10" fill="{C["bg"]}"/>')
    A(f'<circle cx="{rx}" cy="{ry}" r="7" fill="{ink}"/>')
    for label, deg in (('N', 0), ('E', 90), ('S', 180), ('W', 270)):
        t = math.radians(deg); dist = R + 32
        A(f'<text x="{rx + math.sin(t) * dist:.1f}" y="{ry - math.cos(t) * dist + 8:.1f}" font-family="Futura, Futura PT, Century Gothic, sans-serif" '
          f'font-size="24" text-anchor="middle" fill="{ink}">{label}</text>')
    for label, deg in (('NE', 45), ('SE', 135), ('SW', 225), ('NW', 315)):
        t = math.radians(deg); dist = R + 18
        A(f'<text x="{rx + math.sin(t) * dist:.1f}" y="{ry - math.cos(t) * dist + 5:.1f}" font-family="Futura, Futura PT, Century Gothic, sans-serif" '
          f'font-size="13" text-anchor="middle" fill="{ink}" opacity="0.8">{label}</text>')


    # legend
    lx, ly = LEGEND_AT
    A(f'<text x="{lx:.0f}" y="{ly:.0f}" font-size="15" font-weight="700" fill="{C["ink"]}">Legend</text>')
    items = [
        ('here', 'You are here'),
        ('line', 'Open passage, leaving each room from the side you type. Tags mark up, down, in, out.'),
        ('arrow', 'One-way: you can go this way but not back.'),
        ('door', 'Door that opens freely (or with a button)'),
        ('lock', 'Locked: needs an item or a puzzle solved (blue line)'),
        ('story', 'Opens or closes with story events (purple line)'),
        ('ride', 'Ride: elevator, shuttle, teleport, miniaturization'),
        ('updown', 'Up and down exits leave and enter at a slant'),
        ('stub', 'Not an exit for you: a refusal, or a loop back to the same room'),
    ]
    for i, (k, text) in enumerate(items):
        x = lx; y = ly + 28 + i * 25
        if k == 'here':
            A(you_are_here(x + 22, y))
        elif k in ('line', 'arrow'):
            A(f'<path d="M{x},{y} h44" stroke="{C["line"]}" stroke-width="2.4"' + (' marker-end="url(#arrow)"' if k == 'arrow' else '') + '/>')
        elif k == 'door':
            A(f'<path d="M{x},{y} h44" stroke="{C["line"]}" stroke-width="2.4"/><rect x="{x + 19.5}" y="{y - 8}" width="5" height="16" fill="{C["door"]}"/>')
        elif k in ('lock', 'story'):
            A(f'<path d="M{x},{y} h44" stroke="{C[k]}" stroke-width="2.4"/><circle cx="{x + 22}" cy="{y}" r="9" fill="{C[k]}"/>')
            if k == 'lock':
                A(f'<rect x="{x + 18}" y="{y - 1}" width="8" height="6" rx="1" fill="#fff"/><path d="M{x + 19.5},{y - 1} v-2.5 a2.5,2.5 0 0 1 5,0 v2.5" fill="none" stroke="#fff" stroke-width="1.6"/>')
            else:
                A(f'<text x="{x + 22}" y="{y + 4.5}" font-size="13" font-weight="800" text-anchor="middle" fill="#fff">?</text>')
        elif k == 'updown':
            A(f'<path d="M{x},{y + 7} q14,0 22,-7 t22,-7" fill="none" stroke="{C["line"]}" stroke-width="2.4"/>')
        elif k == 'ride':
            A(f'<path d="M{x},{y} h44" stroke="{C["ride"]}" stroke-width="2.2" stroke-dasharray="7 5"/>')
        elif k == 'stub':
            A(f'<path d="M{x},{y} h22" stroke="{C["stub"]}" stroke-width="2" stroke-dasharray="3 3"/><circle cx="{x + 22}" cy="{y}" r="3" fill="{C["stub"]}"/>')
        A(f'<text x="{x + 56}" y="{y + 4}" font-size="12.5" fill="{C["ink"]}">{html.escape(text)}</text>')

    A('</g>')   # chrome
    A('</g></svg>')
    if path: open(path, 'w').write('\n'.join(out))
    if path and mark_start:
        # Where each room sits on the page (fractions of the page, from the top left), its name as
        # the game prints it, and which rooms connect: the in-game map places its marker from this.
        rooms = {}
        for r in POS:
            cx, cy = center(r); w, h = size(r)
            rooms[r] = {'name': RAW[r.split('@')[0]]['desc'],
                        'x': round((cx - w / 2 + ox) / W, 5), 'y': round((cy - h / 2 + oy) / H, 5),
                        'w': round(w / W, 5), 'h': round(h / H, 5)}
        pairs = {tuple(sorted(k)) for k in links}
        pairs |= {tuple(sorted((a_, b_))) for a_, _, b_, _, _, _, _ in RIDES}
        pairs |= {tuple(sorted((a_, b_))) for a_, _, _, b_, _, _, _ in SHAFTS}
        json.dump({'width': round(W), 'height': round(H), 'marker': {'inset': HERE_INSET, 'radius': HERE_R},
                   'start': START, 'rooms': rooms, 'links': sorted(list(p) for p in pairs)},
                  open('../../docs/map/planetfall-map.json', 'w'), indent=1)
    for i, a in enumerate(POS):
        for b in list(POS)[i + 1:]:
            (ax, ay), (bx, by) = center(a), center(b); (aw, ah), (bw_, bh_) = size(a), size(b)
            if tuple(sorted([a, b])) in INSIDE: continue
            if abs(ax - bx) < (aw + bw_) / 2 + 12 and abs(ay - by) < (ah + bh_) / 2 + 12:
                if path and mark_start: print('too close:', a, b, file=sys.stderr)
    if path and mark_start: print('rooms drawn:', len(POS), 'links:', len(links), 'size:', int(W), 'x', int(H))
    missing = [r for r in RAW if r not in POS and r != 'ROOMS' and not r.startswith('ROOMS')]
    if path and mark_start: print('rooms not placed:', missing)

    return owned

notes = render(None)
# The static map marks where the game starts; the game's copy leaves the marker to the app,
# which draws it on whatever room the player is in.
render(notes, '../../docs/map/planetfall-map.svg', mark_start=True)
render(notes, '../../docs/map/planetfall-map-base.svg')
