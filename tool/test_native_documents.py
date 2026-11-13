import os,pathlib,subprocess,time,xml.etree.ElementTree as ET,re
from android_test_env import resolve_tools
root,flutter,adb=resolve_tools()
device=os.environ.get('ANDROID_DEVICE','emulator-5554')
base=[adb,'-s',device]
def call(*args):return subprocess.check_output(base+list(args),stderr=subprocess.STDOUT)
def nodes():
    call('shell','uiautomator','dump','/sdcard/so-do-what-ui.xml')
    return ET.fromstring(call('exec-out','cat','/sdcard/so-do-what-ui.xml'))
def tap(node):
    nums=list(map(int,re.findall(r'\d+',node.attrib['bounds'])))
    call('shell','input','tap',str((nums[0]+nums[2])//2),str((nums[1]+nums[3])//2))
log=root/'.tooling/documents-device.log'
with log.open('w',encoding='utf-8') as out:
    proc=subprocess.Popen([flutter,'test','integration_test/documents_device_test.dart','--dart-define=NATIVE_DOCUMENTS_AUTOMATION=true','-d',device],stdout=out,stderr=subprocess.STDOUT,cwd=root)
    saved=restored=cancelled=False
    deadline=time.monotonic()+240
    while proc.poll() is None and time.monotonic()<deadline:
        text=log.read_text(encoding='utf-8',errors='replace')
        if not saved and 'NATIVE_SAVE_OPEN' in text:
            tree=nodes()
            candidates=[n for n in tree.iter('node') if n.attrib.get('text','').upper() in ('保存','SAVE') and n.attrib.get('enabled')=='true']
            if candidates: tap(candidates[-1]); saved=True; print('Native Save confirmed',flush=True)
        if not restored and 'NATIVE_RESTORE_OPEN' in text:
            tree=nodes()
            candidates=[n for n in tree.iter('node') if n.attrib.get('text','').startswith('random-picker-backup-')]
            if candidates: tap(candidates[0]); restored=True; print('Native backup selected',flush=True)
        if not cancelled and 'NATIVE_CANCEL_OPEN' in text:
            tree=nodes()
            if any('documentsui' in n.attrib.get('package','') for n in tree.iter('node')):
                call('shell','input','keyevent','4');cancelled=True;print('Native Save cancelled',flush=True)
        time.sleep(.5)
    if proc.poll() is None: proc.terminate();raise RuntimeError('Native documents test timeout')
    if proc.returncode: raise RuntimeError('Native documents test failed; see .tooling/documents-device.log')
    assert saved and restored and cancelled
print('Android system documents acceptance passed')
