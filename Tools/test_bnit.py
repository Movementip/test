import base64, hashlib, hmac, json, os, random, struct, time, urllib.parse, urllib.request, urllib.error

KEY=b"SqperSzvbntKmv_CbnngeThis_12303!"
ALPH=b"zxcvbnmasdfghjklqwertyuiop1234567890-_QWERTYUIOPASDFGHJKLZXCVBNM"

def custom_b64(data:bytes)->str:
    out=[]
    acc=0
    bits=-6
    for b in data:
        acc=(acc<<8)|b
        bits+=8
        while bits>=0:
            out.append(chr(ALPH[(acc>>bits)&0x3f]))
            bits-=6
    if bits>-6:
        out.append(chr(ALPH[((acc<<8)>>(bits+8)) & 0x3e]))
    while len(out)%4: out.append('.')
    return ''.join(out)

def enc_meta(data:bytes)->bytes:
    salt=os.urandom(4)
    S=list(range(256)); j=0
    for i in range(256):
        j=(j+S[i]+KEY[i&31]+salt[i&3])&255
        S[i],S[j]=S[j],S[i]
    out=bytearray(salt); i=j=0; prev=0x5a
    for p in data:
        i=(i+1)&255
        oldSi=S[i]
        j=(j+oldSi)&255
        oldSj=S[j]
        S[i],S[j]=oldSj,oldSi
        idx=((oldSi+oldSj)&255)^prev
        c=p^S[idx]
        c=((c<<3)&255)|(c>>5)
        c=(c+prev)&255
        prev=c
        out.append(c)
    return bytes(out)

def sign(method,url,time_offset=0):
    u=urllib.parse.urlsplit(url)
    path=urllib.parse.quote(urllib.parse.unquote(u.path or '/'),safe='/%:@!$&\'()*+,;=-._~')
    pairs=urllib.parse.parse_qsl(u.query,keep_blank_values=True)
    first={}
    for k,v in pairs:
        first.setdefault(k,v)
    query='&'.join(f'{k}={first[k]}' for k in sorted(first))
    ts=str(int(time.time()*1000)+time_offset)
    nonce=os.urandom(16).hex()
    boot='UNKNOWN_BOOT'; inode='NO_APK_INODE'
    canonical=f'{method}:{path}:{query}:{ts}:{nonce}:'.encode()+b':'+boot.encode()+b':'+inode.encode()
    mac=hmac.new(KEY,canonical,hashlib.sha256).hexdigest()
    meta=f'{mac}|{ts}|{nonce}|{boot}|{inode}|1'.encode()
    core=custom_b64(enc_meta(meta))
    trace=os.urandom(16).hex()
    trace=f'{trace[:8]}-{trace[8:12]}-{trace[12:16]}-{trace[16:20]}-{trace[20:]}'
    client=custom_b64(os.urandom(24))
    return {'X-Accept-Red':'1','X-Core-Token':core,'X-Client-Meta':client,'X-Request-Trace-Id':trace}

def req(url,signed=False,ldi='7e595d40b9b542d1',tz='Asia/Yekaterinburg',offset=0):
    h={'Accept':'application/json','Accept-Language':'ru','LDI':ldi,'TZ':tz,'X-App-Version':'207','X-Platform':'android','X-Theme':'dark','User-Agent':'LaneMusic/1.0 (Android; Mobile)','Connection':'close'}
    if signed: h.update(sign('GET',url,offset))
    r=urllib.request.Request(url,headers=h,method='GET')
    try:
        with urllib.request.urlopen(r,timeout=12) as resp:
            body=resp.read()
            print('\nURL',url,'signed',signed,'STATUS',resp.status)
            print('HEADERS',dict(resp.headers))
            print('BODY_HEX',body.hex())\n            print('BODY_HEX',body.hex())\n        print('BODY',body[:2000].decode('utf-8','replace'))
            return resp.status,body,dict(resp.headers)
    except urllib.error.HTTPError as e:
        body=e.read()
        print('\nURL',url,'signed',signed,'STATUS',e.code)
        print('HEADERS',dict(e.headers))
        print('BODY',body[:2000].decode('utf-8','replace'))
        return e.code,body,dict(e.headers)
    except Exception as e:
        print('\nURL',url,'signed',signed,'ERROR',repr(e)); return 0,b'',{}

# clock endpoint is unsigned in Android server-discovery fallback
st,body,_=req('https://laneapi.com/time',False)
offset=0
if st==200:
    try:
        server=json.loads(body).get('timestamp')
        if server: offset=int(server)-int(time.time()*1000)
    except: pass
print('TIME OFFSET',offset)

for host in ['https://laneapi.com','https://ru.laneapi.com']:
    req(host+'/reserve',True,offset=offset)
    req(host+'/auth/7e595d40b9b542d1',True,offset=offset)
