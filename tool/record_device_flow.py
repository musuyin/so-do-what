import os,pathlib,subprocess,time
from android_test_env import resolve_tools
root,flutter,adb=resolve_tools()
device=os.environ.get('ANDROID_DEVICE','emulator-5554')
base=[adb,'-s',device]
def adb_call(*args): return subprocess.run(base+list(args),capture_output=True,check=True)
log=root/'.tooling/device-recording.log'
recorder=None
try:
    adb_call('shell','settings','put','system','accelerometer_rotation','0')
    adb_call('shell','settings','put','system','user_rotation','0')
    adb_call('shell','wm','density','360')
    with log.open('w',encoding='utf-8') as out:
        process=subprocess.Popen([flutter,'test','integration_test/drawing_device_test.dart','-d',device],stdout=out,stderr=subprocess.STDOUT,cwd=root)
        deadline=time.monotonic()+240
        while process.poll() is None and time.monotonic()<deadline:
            if recorder is None and 'RECORDING_READY' in log.read_text(encoding='utf-8',errors='replace'):
                recorder=subprocess.Popen(base+['shell','screenrecord','--time-limit','14','/sdcard/so-do-what-gacha.mp4'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                print('Recording Android gacha flow',flush=True)
            time.sleep(.5)
        if process.poll() is None: process.terminate(); raise RuntimeError('Device test timed out')
        if process.returncode: raise RuntimeError('Device test failed; see .tooling/device-recording.log')
    assert recorder is not None
    recorder.wait(timeout=30)
    (root/'docs/recordings').mkdir(exist_ok=True)
    adb_call('pull','/sdcard/so-do-what-gacha.mp4',str(root/'docs/recordings/gacha-android.mp4'))
    print('Android drawing test passed and recording saved')
finally:
    adb_call('shell','wm','density','reset')
    adb_call('shell','settings','put','system','accelerometer_rotation','1')
