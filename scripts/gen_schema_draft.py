#!/usr/bin/env python3
"""Generate a DRAFT schema for the did.* tables that have no DDL anywhere.

This reverse-engineers CREATE TABLE statements from the GORM model structs by
static analysis (no DB connection required). The output is a STARTING POINT for
review, not an authoritative schema -- see the header it writes into the file.

Usage:  python3 scripts/gen_schema_draft.py
Writes: db/draft_schema_from_models.sql
"""
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── discover which tables still lack DDL ─────────────────────────────────────
TABLE_REF = re.compile(r'\bdid\.([a-z_][a-z0-9_]*)')
CREATE_TBL = re.compile(r'CREATE TABLE (?:IF NOT EXISTS )?(?:did\.)?([a-zA-Z_][a-zA-Z0-9_]*)',
                        re.I)

# Viper config keys and hostnames that look like did.<word> but are not tables.
NOT_TABLES = {'url', 'wallet', 'adurl', 'adv2url', 'authnull', 'kloudlearn'}


def walk(base, exts):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in ('vendor', '.git', 'node_modules')]
        for fn in filenames:
            if fn.endswith(exts):
                yield os.path.join(dirpath, fn)


def referenced_tables():
    found = set()
    for p in walk(os.path.join(ROOT, 'internal'), ('.go',)):
        src = open(p, encoding='utf-8', errors='replace').read()
        found |= set(TABLE_REF.findall(src))
    return found - NOT_TABLES


def tables_with_ddl():
    found = set()
    for p in walk(os.path.join(ROOT, 'internal'), ('.sql',)):
        src = open(p, encoding='utf-8', errors='replace').read()
        found |= {t.lower() for t in CREATE_TBL.findall(src)}
    return found


# ── parse model structs and their TableName() ────────────────────────────────
STRUCT_RE = re.compile(r'^type\s+(\w+)\s+struct\s*\{(.*?)^\}', re.S | re.M)
# TableName bodies are sometimes single-line, sometimes a multi-line return.
TABLENAME_RE = re.compile(
    r'func\s*\(\s*\w*\s*\*?(\w+)\s*\)\s*TableName\(\)\s*string\s*\{(.*?)\}', re.S)
RETURN_STR_RE = re.compile(r'return\s+"([^"]+)"')


def parse_models():
    """-> {table_name: [(field_name, go_type, gorm_tag), ...]}"""
    structs = {}      # struct name -> fields
    tablenames = {}   # struct name -> table
    for p in walk(os.path.join(ROOT, 'internal'), ('.go',)):
        if '/sqlc/' in p.replace(os.sep, '/'):
            continue  # sqlc tables already have real DDL
        src = open(p, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
        src_nc = '\n'.join(l for l in src.split('\n') if not l.strip().startswith('//'))

        for name, body in STRUCT_RE.findall(src_nc):
            fields = []
            for line in body.split('\n'):
                line = line.strip()
                if not line or line.startswith('//'):
                    continue
                tag = ''
                mt = re.search(r'`([^`]*)`', line)
                if mt:
                    tag = mt.group(1)
                    line = line[:mt.start()].strip()
                parts = line.split()
                if len(parts) < 2:
                    continue  # embedded struct or malformed
                fname, ftype = parts[0], parts[1]
                if not re.match(r'^[A-Za-z_]\w*$', fname):
                    continue
                fields.append((fname, ftype, tag))
            if fields:
                structs.setdefault(name, fields)

        for name, body in TABLENAME_RE.findall(src_nc):
            mr = RETURN_STR_RE.search(body)
            if mr:
                tablenames.setdefault(name, mr.group(1))

    out = {}
    prov = {}
    for sname, table in tablenames.items():
        t = table.split('.')[-1].lower()
        if sname in structs:
            if t not in out:
                out[t] = structs[sname]
                prov[t] = (sname, 'TableName()')

    # Fallback: models without an explicit TableName() rely on GORM's default
    # naming strategy (snake_case, pluralised). Index every struct under the
    # names GORM would derive so they can be matched against the missing list.
    for sname, fields in structs.items():
        base = snake(sname)
        cands = [base, base + 's', base + 'es']
        if base.endswith('y'):
            cands.append(base[:-1] + 'ies')
        if base.endswith('s'):
            cands.append(base + 'es')
        for c in cands:
            if c not in out:
                out[c] = fields
                prov[c] = (sname, 'inferred from struct name')
    return out, structs, tablenames, prov


# ── Go type -> PostgreSQL type ───────────────────────────────────────────────
TYPE_MAP = OrderedDict([
    ('sql.NullString', ('varchar', True)),
    ('sql.NullInt64', ('bigint', True)),
    ('sql.NullInt32', ('integer', True)),
    ('sql.NullInt16', ('smallint', True)),
    ('sql.NullBool', ('boolean', True)),
    ('sql.NullTime', ('timestamp', True)),
    ('sql.NullFloat64', ('double precision', True)),
    ('uuid.UUID', ('uuid', False)),
    ('time.Time', ('timestamp', False)),
    ('json.RawMessage', ('jsonb', True)),
    ('datatypes.JSON', ('jsonb', True)),
    ('[]byte', ('bytea', True)),
    ('int64', ('bigint', False)),
    ('int32', ('integer', False)),
    ('int16', ('smallint', False)),
    ('int8', ('smallint', False)),
    ('uint8', ('smallint', False)),
    ('uint', ('bigint', False)),
    ('int', ('integer', False)),
    ('float64', ('double precision', False)),
    ('float32', ('real', False)),
    ('bool', ('boolean', False)),
    ('string', ('varchar', False)),
])


def pg_type(gotype):
    base = gotype.lstrip('*')
    nullable = gotype.startswith('*')
    if base.startswith('[]') and base != '[]byte':
        return None, False  # slice association -- not a column
    if base in TYPE_MAP:
        t, n = TYPE_MAP[base]
        return t, (n or nullable)
    return None, False


def parse_tag(tag):
    """Extract the gorm tag settings we care about."""
    g = {}
    m = re.search(r'gorm:"([^"]*)"', tag)
    if m:
        for part in m.group(1).split(';'):
            part = part.strip()
            if not part:
                continue
            if ':' in part:
                k, v = part.split(':', 1)
                g[k.strip().lower()] = v.strip()
            else:
                g[part.strip().lower()] = True
    j = ''
    mj = re.search(r'json:"([^",]*)', tag)
    if mj:
        j = mj.group(1)
    return g, j


def snake(name):
    s = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', name)
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s)
    return s.lower()


def column_for(fname, ftype, tag):
    g, jname = parse_tag(tag)
    if g.get('-') or g.get('column') == '-':
        return None
    col = g.get('column') or jname or snake(fname)
    col = col.split(',')[0]
    if not re.match(r'^[a-z_][a-z0-9_]*$', col):
        col = snake(fname)

    explicit = g.get('type')
    if explicit:
        pgt, nullable = explicit, True
    else:
        pgt, nullable = pg_type(ftype)
        if pgt is None:
            return None
        if pgt == 'varchar':
            size = g.get('size')
            pgt = 'varchar(%s)' % size if size else 'varchar(255)'

    is_pk = bool(g.get('primarykey') or g.get('primary_key'))
    auto = bool(g.get('autoincrement') or g.get('auto_increment'))
    if is_pk and auto and not explicit:
        pgt = 'bigserial' if pgt == 'bigint' else 'serial'

    parts = ['\t%s %s' % (col, pgt)]
    if is_pk:
        parts.append('PRIMARY KEY')
    else:
        if 'not null' in g or g.get('notnull'):
            parts.append('NOT NULL')
        else:
            # Draft stays permissive: without the real schema we cannot know which
            # columns are NOT NULL, and a wrong NOT NULL breaks inserts.
            parts.append('NULL')
        if g.get('default') not in (None, True):
            parts.append("DEFAULT %s" % g['default'])
        if g.get('uniqueindex') or g.get('unique'):
            parts.append('UNIQUE')
    return ' '.join(parts), col


def main():
    missing = sorted(referenced_tables() - tables_with_ddl())
    by_table, structs, tablenames, prov = parse_models()

    resolved, unresolved = [], []
    for t in missing:
        if t in by_table:
            resolved.append(t)
        else:
            unresolved.append(t)

    out = []
    out.append('-- ============================================================================')
    out.append('-- DRAFT ONLY -- NOT AUTHORITATIVE. DO NOT PUT THIS IN db-init/.')
    out.append('-- ============================================================================')
    out.append('--')
    out.append('-- Reverse-engineered from the GORM model structs by')
    out.append('-- scripts/gen_schema_draft.py. It exists because the real schema for these')
    out.append('-- tables lives only in a running database -- see db/README.md.')
    out.append('--')
    out.append('-- What this CANNOT know, and what you must therefore review:')
    out.append('--   * real column widths (varchar(255) is a guess wherever gorm has no size)')
    out.append('--   * NOT NULL vs NULL (left permissive: NULL unless the tag says otherwise)')
    out.append('--   * DEFAULT values not present in a gorm tag')
    out.append('--   * indexes, foreign keys, sequences, check constraints')
    out.append('--   * anything stored in a column the Go model does not map')
    out.append('--')
    out.append('-- Verify against a live database before trusting it:')
    out.append('--   pg_dump --schema-only --schema=did ... > db-init/01_schema.sql')
    out.append('--')
    out.append('-- Tables referenced by code with no DDL: %d' % len(missing))
    out.append('--   drafted here from a model:            %d' % len(resolved))
    out.append('--   no model found, still undefined:      %d' % len(unresolved))
    out.append('--')
    out.append('-- Each table below records which struct it came from. "inferred from struct')
    out.append('-- name" means the model has no TableName() and the match was made by applying')
    out.append("-- GORM's default naming strategy -- those are the ones most likely to be wrong.")
    out.append('-- ============================================================================')
    out.append('')
    out.append('CREATE SCHEMA IF NOT EXISTS did;')
    out.append('')

    for t in resolved:
        cols, seen = [], set()
        for fname, ftype, tag in by_table[t]:
            r = column_for(fname, ftype, tag)
            if not r:
                continue
            line, col = r
            if col in seen:
                continue
            seen.add(col)
            cols.append(line)
        if not cols:
            continue
        sname, how = prov.get(t, ('?', '?'))
        out.append('-- drafted from model %s (%s)' % (sname, how))
        out.append('CREATE TABLE IF NOT EXISTS did.%s (' % t)
        out.append(',\n'.join(cols))
        out.append(');')
        out.append('')

    if unresolved:
        out.append('-- ----------------------------------------------------------------------------')
        out.append('-- No GORM model with a TableName() maps to these %d tables, so nothing could' % len(unresolved))
        out.append('-- be drafted for them. They must come from a real pg_dump:')
        for t in unresolved:
            out.append('--   did.%s' % t)
        out.append('-- ----------------------------------------------------------------------------')
        out.append('')

    dest = os.path.join(ROOT, 'db', 'draft_schema_from_models.sql')
    open(dest, 'w').write('\n'.join(out) + '\n')
    print('wrote %s' % os.path.relpath(dest, ROOT))
    print('  missing tables:     %d' % len(missing))
    print('  drafted:            %d' % len(resolved))
    print('  still undefined:    %d' % len(unresolved))
    return 0


if __name__ == '__main__':
    sys.exit(main())
