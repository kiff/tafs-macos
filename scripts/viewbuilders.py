#!/usr/bin/env python3
"""Fails for a SwiftUI builder with more than 10 views in it (docs/building.md).

On macOS 12 the app is built with Swift 5.7 and its SDK, whose ViewBuilder takes at most 10
views in one block; a newer SDK takes any number, so a newer build can't tell. This counts each
block's top-level statements (a line that isn't a modifier, a closing brace, a comment,
else/case/default or a continuation) in the blocks a view is built in.
Usage: scripts/viewbuilders.py FILE..."""
import re, sys
LIMIT = 10
def strip(src):
    # remove comments and string literals (simple, incl. raw #"..."# and multiline """)
    out=[];i=0;n=len(src)
    while i<n:
        if src.startswith('//',i):
            j=src.find('\n',i); i = n if j<0 else j; continue
        if src.startswith('/*',i):
            j=src.find('*/',i+2); i = n if j<0 else j+2; continue
        m=re.match(r'(#*)"""',src[i:])
        if m:
            h=m.group(1); end='"""'+h; j=src.find(end,i+len(m.group(0))); 
            seg=src[i:(n if j<0 else j+len(end))]; out.append('""'+'\n'*seg.count('\n')); i=(n if j<0 else j+len(end)); continue
        m=re.match(r'(#+)"',src[i:])
        if m:
            h=m.group(1); end='"'+h; j=src.find(end,i+len(m.group(0)))
            out.append('""'); i=(n if j<0 else j+len(end)); continue
        if src[i]=='"':
            j=i+1
            while j<n and src[j]!='"':
                if src[j]=='\\': j+=1
                elif src[j]=='\n': break
                j+=1
            out.append('""'); i=j+1; continue
        out.append(src[i]); i+=1
    return ''.join(out)
def check(path):
    src=strip(open(path).read())
    lines=src.split('\n')
    # map each '{' to its block; collect top-level statement starts per block
    stack=[]; found=[]
    depth_paren=0
    for ln,line in enumerate(lines,1):
        s=line.strip()
        # statement start at current block if line begins a new statement
        if stack and depth_paren==0 and s and not s.startswith(('.', '}', ')', ']', 'else', 'case ', 'default', '#', '&&', '||', '?', ':', '+', '-', '*', '=', ',', 'catch')):
            prev = stack[-1]
            if prev['last_end_continues'] is False:
                prev['count']+=1; prev['lines'].append(ln)
        for k,ch in enumerate(line):
            if ch in '([': depth_paren+=1
            elif ch in ')]': depth_paren=max(0,depth_paren-1)
            elif ch=='{':
                stack.append({'start':ln,'count':0,'lines':[],'last_end_continues':False,'paren':depth_paren,'head':line.strip()})
                depth_paren=0
            elif ch=='}':
                if stack:
                    b=stack.pop(); depth_paren=b['paren']
                    if b['count']>LIMIT: found.append(b)
        if stack:
            stack[-1]['last_end_continues'] = s.endswith((',', '(', '[', '&&', '||', '+', '=', '?', ':', '->', '.')) if s else stack[-1]['last_end_continues']
    return found
if __name__ == '__main__':  # `strip` is also scripts/swift57patterns.py's
    bad=0
    for p in sys.argv[1:]:
        for b in check(p):
            h=b['head']
            if re.search(r'\b(VStack|HStack|ZStack|LazyVStack|LazyHStack|Group|ScrollView|Section|List|Form|Menu|ToolbarItemGroup|NavigationView|GeometryReader|body|some View|ViewBuilder|overlay|background|safeAreaInset|label|content|header|footer|sheet|popover|alert|confirmationDialog|toolbar|Button|ForEach)\b', h) or h.endswith('in') or h=='{':
                print(f"{p}:{b['start']}: {b['count']} children > {LIMIT}: {h[:90]}"); bad+=1
    sys.exit(1 if bad else 0)
