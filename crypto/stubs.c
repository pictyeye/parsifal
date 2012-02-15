#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/fail.h>

#include "md5.h"
#include "sha1.h"
#include "sha2.h"
#include "sha4.h"
#include "aes.h"
#include <gmp.h>


value md5sum (value caml_s) {
  CAMLparam1 (caml_s);
  CAMLlocal1 (caml_res);

  caml_res = caml_alloc_string (16);
  // TODO: Check the allocation succeeded ?
  unsigned char* res = (unsigned char*) String_val (caml_res);

  const unsigned char* s = (const unsigned char*) String_val (caml_s);
  size_t n = caml_string_length(caml_s);

  md5 (s, n, res);

  CAMLreturn (caml_res);
}
  
value sha1sum (value caml_s) {
  CAMLparam1 (caml_s);
  CAMLlocal1 (caml_res);

  caml_res = caml_alloc_string (20);
  // TODO: Check the allocation succeeded ?
  unsigned char* res = (unsigned char*) String_val (caml_res);

  const unsigned char* s = (const unsigned char*) String_val (caml_s);
  size_t n = caml_string_length(caml_s);

  sha1 (s, n, res);

  CAMLreturn (caml_res);
}

value sha224_256sum (value caml_s, value caml_is224) {
  CAMLparam2 (caml_s, caml_is224);
  CAMLlocal1 (caml_res);

  int is224 = Bool_val (caml_is224);
  caml_res = caml_alloc_string (is224 ? 28 : 32);
  // TODO: Check the allocation succeeded ?
  unsigned char* res = (unsigned char*) String_val (caml_res);

  const unsigned char* s = (const unsigned char*) String_val (caml_s);
  size_t n = caml_string_length(caml_s);

  sha2 (s, n, res, is224);

  CAMLreturn (caml_res);
}

value sha384_512sum (value caml_s, value caml_is384) {
  CAMLparam2 (caml_s, caml_is384);
  CAMLlocal1 (caml_res);

  int is384 = Bool_val (caml_is384);
  caml_res = caml_alloc_string (is384 ? 48 : 64);
  // TODO: Check the allocation succeeded ?
  unsigned char* res = (unsigned char*) String_val (caml_res);

  const unsigned char* s = (const unsigned char*) String_val (caml_s);
  size_t n = caml_string_length(caml_s);

  sha4 (s, n, res, is384);

  CAMLreturn (caml_res);
}


value aes_cbc (value caml_encrypt, value caml_key, value caml_iv, value caml_input) {
  CAMLparam4 (caml_encrypt, caml_key, caml_iv, caml_input);
  CAMLlocal1 (caml_output);

  int do_encrypt = Bool_val (caml_encrypt);
  int res;
  size_t key_length, input_length;
  unsigned char* key;
  aes_context ctx;

  key_length = caml_string_length(caml_key);
  key = (unsigned char*) String_val (caml_key);
  if (do_encrypt)
    res = aes_setkey_enc (&ctx, key, key_length * 8);
  else
    res = aes_setkey_dec (&ctx, key, key_length * 8);
  if (res != 0) caml_failwith ("context");

  input_length = caml_string_length(caml_input);
  caml_output = caml_alloc_string (input_length);
  // TODO: Check wether the allocation succeeded? Does it raise an exception?

  if (aes_crypt_cbc (&ctx, do_encrypt ? AES_ENCRYPT : AES_DECRYPT, input_length,
		     (unsigned char*) String_val (caml_iv),
		     (unsigned char*) String_val (caml_input),
		     (unsigned char*) String_val (caml_output)) != 0)
    caml_failwith ("crypt");

  CAMLreturn (caml_output);
}


const char* hexachar = "0123456789abcdef";
const char hexachar_rev[256] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 0, 0, 0,
				0,10,11,12,13,14,15, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0,10,11,12,13,14,15, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

static int os2ip (mpz_t* res, value caml_value) {
  const char* x_str = String_val (caml_value);
  size_t x_size = caml_string_length(caml_value);
  char* x_hexa = (char*) malloc (x_size * 2 + 1);
  size_t i;

  if (x_hexa == NULL) return 0;

  for (i = 0; i<x_size; i++) {
    x_hexa[2 * i] = hexachar[(x_str [i] >> 4) & 0xf];
    x_hexa[2 * i + 1] = hexachar[x_str [i] & 0xf];
  }
  x_hexa [2 * x_size] = 0;

  mpz_init_set_str (*res, x_hexa, 16);

  free (x_hexa);
  return (res != NULL);
}


static int i2osp (value* res, mpz_t val, size_t len) {
  size_t i, s_len;
  char* s;
  char* os_res;

  *res = caml_alloc_string (len);
  os_res = String_val (*res);
  // TODO: Could this fail?

  s = mpz_get_str (NULL, 16, val);
  s_len = strlen (s);

  for (i=0; i<(s_len/2); i++)
    os_res[len-1-i] = (hexachar_rev[(int) s[(s_len - 1) - 2 * i - 1]] << 4) | hexachar_rev[(int) s[(s_len - 1) - 2 * i]];

  if (s_len % 2 != 0)
    os_res[len-1-(s_len/2)] = hexachar_rev[(int) s[0]];

  free (s);

  return 1;
}




value exp_mod (value caml_x, value caml_e, value caml_n) {
  CAMLparam3 (caml_x, caml_e, caml_n);
  CAMLlocal1 (caml_res);

  mpz_t x, e, n;
  size_t n_len;
  int res;

  if (!os2ip (&x, caml_x))
    goto error;
  if (!os2ip (&e, caml_e))
    goto free_x;
  if (!os2ip (&n, caml_n))
    goto free_e;

  n_len = (mpz_sizeinbase (n, 16) + 1) / 2;
  mpz_powm (x, x, e, n);
  res = i2osp (&caml_res, x, n_len);
  mpz_clear (x); mpz_clear (e); mpz_clear (n);
  if (!res)
    caml_failwith ("Not enough memory");
  else
    CAMLreturn (caml_res);

 free_e:
  mpz_clear (e);
 free_x:
  mpz_clear (x);
 error:
  caml_failwith ("Not enough memory");
}



value gcd (value caml_a, value caml_b) {
  CAMLparam2 (caml_a, caml_b);
  CAMLlocal1 (caml_res);

  mpz_t a, b;
  size_t res_len;
  int res;

  if (!os2ip (&a, caml_a))
    goto error;
  if (!os2ip (&b, caml_b))
    goto free_a;

  mpz_gcd (a, a, b);
  res_len = (mpz_sizeinbase (a, 16) + 1) / 2;
  res = i2osp (&caml_res, a, res_len);
  mpz_clear (b); mpz_clear (a);
  if (!res)
    caml_failwith ("Not enough memory");
  else
    CAMLreturn (caml_res);

 free_a:
  mpz_clear (a);
 error:
  caml_failwith ("Not enough memory");
}


value lcm (value caml_a, value caml_b) {
  CAMLparam2 (caml_a, caml_b);
  CAMLlocal1 (caml_res);

  mpz_t a, b;
  size_t res_len;
  int res;

  if (!os2ip (&a, caml_a))
    goto error;
  if (!os2ip (&b, caml_b))
    goto free_a;

  mpz_lcm (a, a, b);
  res_len = (mpz_sizeinbase (a, 16) + 1) / 2;
  res = i2osp (&caml_res, a, res_len);
  mpz_clear (b); mpz_clear (a);
  if (!res)
    caml_failwith ("Not enough memory");
  else
    CAMLreturn (caml_res);

 free_a:
  mpz_clear (a);
 error:
  caml_failwith ("Not enough memory");
}


value divq (value caml_a, value caml_b) {
  CAMLparam2 (caml_a, caml_b);
  CAMLlocal1 (caml_res);

  mpz_t a, b;
  size_t res_len;
  int res;

  if (!os2ip (&a, caml_a))
    goto error;
  if (!os2ip (&b, caml_b))
    goto free_a;

  mpz_fdiv_q (a, a, b);
  res_len = (mpz_sizeinbase (a, 16) + 1) / 2;
  res = i2osp (&caml_res, a, res_len);
  mpz_clear (b); mpz_clear (a);
  if (!res)
    caml_failwith ("Not enough memory");
  else
    CAMLreturn (caml_res);

 free_a:
  mpz_clear (a);
 error:
  caml_failwith ("Not enough memory");
}


value mul (value caml_a, value caml_b) {
  CAMLparam2 (caml_a, caml_b);
  CAMLlocal1 (caml_res);

  mpz_t a, b;
  size_t res_len;
  int res;

  if (!os2ip (&a, caml_a))
    goto error;
  if (!os2ip (&b, caml_b))
    goto free_a;

  mpz_mul (a, a, b);
  res_len = (mpz_sizeinbase (a, 16) + 1) / 2;
  res = i2osp (&caml_res, a, res_len);
  mpz_clear (b); mpz_clear (a);
  if (!res)
    caml_failwith ("Not enough memory");
  else
    CAMLreturn (caml_res);

 free_a:
  mpz_clear (a);
 error:
  caml_failwith ("Not enough memory");
}


value is_prime (value caml_p) {
  CAMLparam1 (caml_p);
  CAMLlocal1 (caml_res);

  mpz_t p;
  int res;

  if (!os2ip (&p, caml_p))
    goto error;

  res = mpz_probab_prime_p (p, 10) > 0;
  mpz_clear (p);
  CAMLreturn (Val_bool (res));

 error:
  caml_failwith ("Not enough memory");
}
