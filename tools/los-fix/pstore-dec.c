// pstore-dec.c — decrypt AOSP PSTORE_ENCRYPTION pmsg files (AES-256-GCM).
// Ground truth: system/core/fs_mgr/liblp/pstore.cpp + include/liblp/pstore.h
//   key  = SHA256(hex(LE64(entropy)) || ":" || ascii(LE64(boot_count)))   [32B]
//   iv   = LE64(boot_count) || LE32(record_counter)                        [12B]
//   out  = AES256GCM_decrypt(key, iv, enc[payload]) || enc[tag(16)]
// Record framing in file (pstore.cpp ReadPstore / pstore.h pstore_record):
//   offset 0x00: type   u32 (0xA0D5A47C boot, 0x8B3E52F1 shutdown)
//   offset 0x04: zlen   u32 (compressed bytes; >raw_len => uncompressed)
//   offset 0x08: clen   u32 (always = raw_len here)
//   offset 0x0C: klen   u32 (compressed key length; 0 => plaintext record)
//   offset 0x10: counter u64 (record_counter -> iv[8:12])
//   offset 0x18: payload zlen bytes (4-aligned)
//   offset ...: key area klen bytes (RSA-wrapped DEK; klen==0 here)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <openssl/evp.h>
#include <openssl/sha.h>

static uint64_t rd64(const unsigned char *p){uint64_t v;memcpy(&v,p,8);return v;}
static uint32_t rd32(const unsigned char *p){uint32_t v;memcpy(&v,p,4);return v;}

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: %s entropy.txt(2 lines) pmsg-file out\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "r");
    char l1[128] = {0}, l2[128] = {0};
    if (!f || !fgets(l1, sizeof l1, f) || !fgets(l2, sizeof l2, f)) { fprintf(stderr, "bad entropy file\n"); return 2; }
    fclose(f);
    uint64_t entropy = strtoull(l1, 0, 0), bootcnt = strtoull(l2, 0, 0);
    if (!entropy) { fprintf(stderr, "entropy=0\n"); return 2; }

    // key input: "%016llx" of entropy (16 ascii hex chars) + ":" + 8 raw LE bytes of boot_count
    char hexbuf[17]; snprintf(hexbuf, sizeof hexbuf, "%016llx", (unsigned long long)entropy);
    unsigned char keyin[25]; memcpy(keyin, hexbuf, 16); keyin[16] = ':';
    memcpy(keyin + 17, &bootcnt, 8);
    unsigned char key[32];
    SHA256(keyin, 25, key);

    f = fopen(argv[2], "rb");
    if (!f) { perror("open pmsg"); return 2; }
    unsigned char hdr[0x18];
    if (fread(hdr, 1, 0x18, f) != 0x18) { fprintf(stderr, "short file\n"); return 2; }
    uint32_t type = rd32(hdr), zlen = rd32(hdr + 4), clen = rd32(hdr + 8), klen = rd32(hdr + 12);
    uint64_t counter = rd64(hdr + 0x10);
    fprintf(stderr, "type=0x%08x zlen=%u clen=%u klen=%u counter=%llu\n",
            type, zlen, clen, klen, (unsigned long long)counter);
    if (clen == 0 || clen != zlen) { fprintf(stderr, "note: clen!=zlen (compressed) - not handled\n"); }
    if (klen != 0) fprintf(stderr, "note: klen=%u (RSA-wrapped) - treating payload as direct GCM anyway\n", klen);

    unsigned char *enc = malloc(clen + 16);
    if (fread(enc, 1, clen + 16, f) != clen + 16) { fprintf(stderr, "short payload\n"); return 2; }
    fclose(f);

    unsigned char iv[12]; memcpy(iv, &bootcnt, 8); uint32_t c32 = (uint32_t)counter; memcpy(iv + 8, &c32, 4);

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    unsigned char *out = malloc(clen + 16);
    int len = 0, total = 0, ok = 0;
    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL)
        && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL)
        && EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv)
        && EVP_DecryptUpdate(ctx, out, &len, enc, clen)) {
        total = len;
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, enc + clen);
        ok = EVP_DecryptFinal_ex(ctx, out + total, &len);
        total += len;
    }
    if (ok > 0) {
        FILE *o = fopen(argv[3], "wb"); fwrite(out, 1, total, o); fclose(o);
        fprintf(stderr, "DECRYPT_OK wrote %d bytes to %s\n", total, argv[3]);
        return 0;
    }
    fprintf(stderr, "DECRYPT_FAIL (tag mismatch)\n");
    return 1;
}
