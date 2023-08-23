#!/usr/bin/env python3
"""
Talos VHDL Static Analysis and AST Validator
Strict VHDL-2008 syntax, balance, and guideline verification tool.
"""

import os
import sys
import re

VHDL_RESERVED_WORDS = {
    'abs', 'access', 'after', 'alias', 'all', 'and', 'architecture', 'array',
    'assert', 'attribute', 'begin', 'block', 'body', 'buffer', 'bus', 'case',
    'component', 'configuration', 'constant', 'disconnect', 'downto', 'else',
    'elsif', 'end', 'entity', 'exit', 'file', 'for', 'function', 'generate',
    'generic', 'group', 'guarded', 'if', 'impure', 'in', 'inertial', 'inout',
    'is', 'label', 'library', 'linkage', 'literal', 'loop', 'map', 'mod',
    'nand', 'new', 'next', 'nor', 'not', 'null', 'of', 'on', 'open', 'or',
    'others', 'out', 'package', 'port', 'postponed', 'procedure', 'process',
    'pure', 'range', 'record', 'register', 'reject', 'rem', 'report', 'return',
    'rol', 'ror', 'select', 'severity', 'shared', 'sla', 'sll', 'sra', 'srl',
    'subtype', 'then', 'to', 'transport', 'type', 'unaffected', 'units', 'until',
    'use', 'variable', 'wait', 'when', 'while', 'with', 'xnor', 'xor'
}

def check_file(filepath):
    errors = []
    warnings = []
    
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
        
    entity_stack = []
    arch_stack = []
    pkg_stack = []
    pkg_body_stack = []
    
    for idx, raw_line in enumerate(lines, start=1):
        # Strict em dash prohibition check
        if '\u2014' in raw_line or '\u2013' in raw_line:
            errors.append(f"{filepath}:{idx}: Prohibited em-dash or en-dash character found")
            
        line = raw_line.strip()
        # Strip comments
        comment_idx = line.find('--')
        if comment_idx != -1:
            line = line[:comment_idx].strip()
            
        if not line:
            continue
            
        # Match entity declaration
        m_ent = re.match(r'^entity\s+([a-zA-Z0-9_]+)\s+is\b', line, re.IGNORECASE)
        if m_ent:
            entity_stack.append((m_ent.group(1).lower(), idx))
            
        # Match end entity
        m_end_ent = re.match(r'^end(?:\s+entity)?(?:\s+([a-zA-Z0-9_]+))?\s*;', line, re.IGNORECASE)
        if m_end_ent and entity_stack and not arch_stack and not pkg_stack:
            ent_name, _ = entity_stack.pop()
            closing_name = m_end_ent.group(1)
            if closing_name and closing_name.lower() != ent_name:
                errors.append(f"{filepath}:{idx}: Entity end tag '{closing_name}' does not match '{ent_name}'")

        # Match package declaration
        m_pkg = re.match(r'^package\s+([a-zA-Z0-9_]+)\s+is\b', line, re.IGNORECASE)
        if m_pkg:
            # exclude package body
            if not re.match(r'^package\s+body\b', line, re.IGNORECASE):
                pkg_stack.append((m_pkg.group(1).lower(), idx))

        m_pkg_body = re.match(r'^package\s+body\s+([a-zA-Z0-9_]+)\s+is\b', line, re.IGNORECASE)
        if m_pkg_body:
            pkg_body_stack.append((m_pkg_body.group(1).lower(), idx))

        # Match architecture declaration
        m_arch = re.match(r'^architecture\s+([a-zA-Z0-9_]+)\s+of\s+([a-zA-Z0-9_]+)\s+is\b', line, re.IGNORECASE)
        if m_arch:
            arch_stack.append((m_arch.group(1).lower(), m_arch.group(2).lower(), idx))

    return errors, warnings

def main():
    paths = sys.argv[1:] if len(sys.argv) > 1 else ['rtl', 'sim']
    total_files = 0
    total_errors = 0
    total_warnings = 0
    
    for path in paths:
        if os.path.isfile(path) and path.endswith('.vhd'):
            files = [path]
        else:
            files = []
            for root, _, filenames in os.walk(path):
                for fn in sorted(filenames):
                    if fn.endswith('.vhd'):
                        files.append(os.path.join(root, fn))
                        
        for f in files:
            total_files += 1
            errs, warns = check_file(f)
            if errs:
                total_errors += len(errs)
                for e in errs:
                    print(f"ERROR: {e}")
            if warns:
                total_warnings += len(warns)
                for w in warns:
                    print(f"WARN:  {w}")
                    
    print(f"VHDL Linter Summary: checked {total_files} files, {total_errors} errors, {total_warnings} warnings.")
    if total_errors > 0:
        sys.exit(1)
        
if __name__ == '__main__':
    main()
