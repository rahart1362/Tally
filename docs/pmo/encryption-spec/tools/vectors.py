import struct
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidTag
import cryptography
from cryptography.hazmat.backends.openssl import backend
print("lib:", "python-cryptography", cryptography.__version__, "|", backend.openssl_version_text())
MAGIC=b"TLYV"
def header(file_byte, key_id): return MAGIC + bytes([1, file_byte, 0, 0]) + struct.pack(">I", key_id)
def seal(key, nonce, fb, kid, pt):
    h=header(fb,kid); return h + nonce + AESGCM(key).encrypt(nonce, pt, h)
key=bytes(range(32)); nonce=bytes(range(0xa0,0xac))
for name,fb,kid,pt in [("TV1 snapshot",1,1,b'{"v":1}'),("TV2 snapshot empty",1,1,b''),
                       ("TV3 glance",2,7,"Due: MATH 221 – Problem Set 4".encode()),
                       ("TV4 ledger",4,0xDEADBEEF,b'[]')]:
    b=seal(key,nonce,fb,kid,pt)
    assert AESGCM(key).decrypt(b[12:24], b[24:], b[:12])==pt
    print(f"{name}: file=0x{fb:02x} keyID=0x{kid:08x} pt={pt!r} len={len(b)}\n  {b.hex()}")
b=seal(key,nonce,1,1,b'{"v":1}')
for label,mut in [("N2 file byte -> glance", b[:5]+b"\x02"+b[6:]),("N3 keyID -> 2", b[:8]+struct.pack(">I",2)+b[12:])]:
    try: AESGCM(key).decrypt(mut[12:24], mut[24:], mut[:12]); print(label,"UNEXPECTED OK")
    except InvalidTag: print(label,"-> InvalidTag")
