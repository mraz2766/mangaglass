import json, base64
from Crypto.Cipher import AES

def decrypt(cipher_hex, key_str, iv_str):
    cipher_bytes = bytes.fromhex(cipher_hex)
    key_bytes = key_str.encode('utf-8')
    iv_bytes = iv_str.encode('utf-8')
    
    cipher = AES.new(key_bytes, AES.MODE_CBC, iv_bytes)
    plain = cipher.decrypt(cipher_bytes)
    return plain[:-plain[-1]].decode('utf-8')

ccz = "op0zzpvv.nzn.o0p"
results = "2gWE7oi3xc0TwmBI1955520aed27c5ff24625500697ddeae32b723ef5862e1d83833d0c25a16991c80afb621caf4ed213ef010a16301eacbc1d608be1227f570cc601a49a0f253b783c73a8aadf9d99e9266cae2f0f879db3b477adece835986858963982b0f4e88ddf684c305069bebc30b97818815a1a9948d72b6c694d36bbceef8a42e1dfd6c51ccaf9cd06f21935268aa4f7c8a61f2da88ce6da7d02c135923458966aa8d266b5a6fef4c2185750047779532c658ff01821ee4e2de834ffda1fb77144e7f4d2d4e30acb64d4e4382b3e12c6251279d2e3bbab62aacb93420fb98728913b471903c026b094f7810859c58979915efb16c16eca6dfc048879f1aadcbdc8547fb"
iv = results[:16]
cipher_hex = results[16:]
key = ccz

print(decrypt(cipher_hex, key, iv))
