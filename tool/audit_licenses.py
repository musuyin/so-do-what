import json, pathlib, urllib.parse
root=pathlib.Path(__file__).resolve().parents[1]
config=root/'.dart_tool/package_config.json'
data=json.loads(config.read_text())
lines=['# 已锁定依赖许可核查','', '生成依据：当前 pubspec.lock 与实际包目录 LICENSE。含传递依赖及开发测试依赖。', '', '| 包 | 版本 | 许可标识/首行 |','| --- | --- | --- |']
notices=['Third-party license texts for the locked dependency graph.']
for p in data['packages']:
    if p['name']=='so_do_what': continue
    uri=urllib.parse.urlparse(p['rootUri'])
    if uri.scheme=='file':
        path=pathlib.Path(urllib.parse.unquote(uri.path).lstrip('/'))
    else: path=(config.parent / p['rootUri']).resolve()
    licenses=list(path.glob('LICENSE*'))
    
    if not licenses and 'flutter' in str(path):
        parents=[x/'LICENSE' for x in path.parents if (x/'LICENSE').exists()]
        licenses=parents[:1]
    text=licenses[0].read_text(encoding='utf-8',errors='replace') if licenses else 'MISSING LICENSE'
    low=text.lower()
    kind='MIT' if 'permission is hereby granted, free of charge' in low else 'Apache-2.0' if 'apache license' in low else 'BSD-3-Clause' if 'neither the name' in low else 'BSD-2-Clause' if 'redistribution and use' in low else text.splitlines()[0][:90]
    spec=(path/'pubspec.yaml').read_text(encoding='utf-8',errors='replace')
    versions=[s.split(':',1)[1].strip() for s in spec.splitlines() if s.startswith('version:')]
    lines.append(f"| {p['name']} | {versions[0] if versions else 'SDK'} | {kind} |")
    notices.extend(['\n\n'+'='*72, p['name'],text])
lines.extend(['','运行时只使用本地能力。依赖树中的 http/web 等传递包不代表本应用提供网络服务。Android release 合并权限另行检查。', '', 'Flutter Material Icons 随 SDK 提供（Apache-2.0）；Flutter/Dart SDK 采用 BSD 许可，详细文本随 SDK 分发。系统中文字体由设备提供，未分发字体文件。', '', '本项目：Apache-2.0（用户于 2026-11-13 选择）。原创绘图和合成音效随项目采用相同许可证。'])
(root/'docs/dependency-audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(root/'docs/third-party-licenses.txt').write_text('\n'.join(notices),encoding='utf-8')
print(f'Audited {len(data["packages"])-1} packages')

