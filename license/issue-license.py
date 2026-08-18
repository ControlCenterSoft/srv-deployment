#!/usr/bin/env python3
import argparse,base64,json,subprocess,tempfile,time,uuid
from pathlib import Path

def b64u(data:bytes)->str:return base64.urlsafe_b64encode(data).decode().rstrip('=')
p=argparse.ArgumentParser()
p.add_argument('--private-key',required=True)
p.add_argument('--device-id',required=True)
p.add_argument('--license-id',default='')
p.add_argument('--expires-at',type=int,default=0)
a=p.parse_args()
payload={'edition':'Professional','device_id':a.device_id,'license_id':a.license_id or str(uuid.uuid4()),'issued_at':int(time.time())}
if a.expires_at:payload['expires_at']=a.expires_at
raw=json.dumps(payload,separators=(',',':'),sort_keys=True).encode()
with tempfile.TemporaryDirectory() as td:
    src=Path(td)/'payload.json'; sig=Path(td)/'sig.bin'; src.write_bytes(raw)
    subprocess.check_call(['openssl','dgst','-sha256','-sign',a.private_key,'-out',str(sig),str(src)])
    print(json.dumps({'payload':b64u(raw),'signature':b64u(sig.read_bytes()),'license':payload},ensure_ascii=False,indent=2))
