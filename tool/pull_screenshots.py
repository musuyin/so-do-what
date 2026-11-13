import pathlib, re, base64
log=pathlib.Path('.tooling/visual-evidence.log').read_text(encoding='utf-8',errors='replace')
folder=pathlib.Path('docs/screenshots'); folder.mkdir(parents=True,exist_ok=True)
count=0
for name,data in re.findall(r'EVIDENCE:([\w-]+):([A-Za-z0-9+/=]+)',log):
    content=base64.b64decode(data)
    assert content.startswith(b'\x89PNG'),name
    (folder/f'{name}.png').write_bytes(content)
    count+=1
assert count==10,f'Expected 10 screenshots, got {count}'
print('Captured',count,'Android rendered screens')
