const crypto = require('crypto');

function decrypt(cipher_hex, key_str, iv_str) {
    const cipher_bytes = Buffer.from(cipher_hex, 'hex');
    const key_bytes = Buffer.from(key_str, 'utf8');
    const iv_bytes = Buffer.from(iv_str, 'utf8');
    
    const decipher = crypto.createDecipheriv('aes-128-cbc', key_bytes, iv_bytes);
    decipher.setAutoPadding(true);
    
    let plain = decipher.update(cipher_bytes);
    plain = Buffer.concat([plain, decipher.final()]);
    
    return plain.toString('utf8');
}

const ccz = "op0zzpvv.nzn.o0p";
const results = "2gWE7oi3xc0TwmBI1955520aed27c5ff24625500697ddeae32b723ef5862e1d83833d0c25a16991c80afb621caf4ed213ef010a16301eacbc1d608be1227f570cc601a49a0f253b783c73a8aadf9d99e9266cae2f0f879db3b477adece835986858963982b0f4e88ddf684c305069bebc30b97818815a1a9948d72b6c694d36bbceef8a42e1dfd6c51ccaf9cd06f21935268aa4f7c8a61f2da88ce6da7d02c135923458966aa8d266b5a6fef4c2185750047779532c658ff01821ee4e2de834ffda1fb77144e7f4d2d4e30acb64d4e4382b3e12c6251279d2e3bbab62aacb93420fb98728913b471903c026b094f7810859c58979915efb16c16eca6dfc048879f1aadcbdc8547fb";
try {
    const iv = results.substring(0, 16);
    const cipher_hex = results.substring(16);
    const text = decrypt(cipher_hex, ccz, iv);
    console.log("DECRYPTED:", text.substring(0, 100));
} catch(e) { console.error("ERR:", e); }
