open Asn1Engine
open Asn1PTypes
open CryptoUtil

exception NotFound of string
exception MessageTooLong
exception InvalidBlockType
exception PaddingError
exception InvalidSignature


(* TODO: Define a private key / public key type? *)

let hash_funs : (int list, string -> string) Hashtbl.t = Hashtbl.create 10

let get_hash_fun_by_name n =
  try
    let oid = Hashtbl.find rev_oid_directory n in
    let f = Hashtbl.find hash_funs oid in
    (oid, f)
  with Not_found -> raise (NotFound ("Unknown hash function " ^ n))

let get_hash_fun_by_oid oid =
  try Hashtbl.find hash_funs oid
  with Not_found -> raise (NotFound ("Unknown hash oid " ^ (string_of_oid oid)))



let find_not_null s i =
  let s_len = String.length s in
  let rec aux i =
    if i = s_len || s.[i] != '\x00'
    then i
    else aux (i+1)
  in aux i

let normalize_modulus n =
  let n_len = String.length n in
  let to_drop = find_not_null n 0 in
  let new_len = n_len - to_drop in
  String.sub n to_drop new_len

let format_encryption_block rnd_state block_type padding_len d =
  let padding = match block_type with
    | 0 -> String.make padding_len '\x00'
    | 1 -> String.make padding_len '\xff'
    | 2 -> RandomEngine.random_string rnd_state padding_len
    | _ -> raise InvalidBlockType
  in
  let tmp1 = String.make 1 '\x00' in
  let tmp2 = String.make 1 (char_of_int block_type) in
  tmp1 ^ tmp2 ^ padding ^ tmp1 ^ d


let encrypt rnd_state block_type d n c =
  let normalized_n = normalize_modulus n in
  let k = String.length normalized_n in
  let d_len = String.length d in
  if d_len > k - 11
  then raise MessageTooLong;
  let encryption_block = format_encryption_block rnd_state block_type (k - d_len - 3) d in
  exp_mod encryption_block c normalized_n


(* TODO: block_type should be optional *)

let decrypt block_type expected_len ed n c =
  let normalized_n = normalize_modulus n in
  let encryption_block = exp_mod ed c normalized_n in
  let res = ref true in

  if encryption_block.[0] != '\x00'
  or encryption_block.[1] != (char_of_int block_type)
  then res := false;

  let block_len = String.length encryption_block in
  let d_start =
    try
      match block_type with
	| 1
	| 2 -> begin
	  let tmp = String.index_from encryption_block 2 '\x00' in
	  if tmp < 10 then raise Not_found;
	  let l = block_len - tmp - 1 in
	  match expected_len with
	    | None -> tmp + 1
	    | Some len ->
	      if len = l
	      then tmp + 1
	      else raise Not_found
	end
	| 0 -> begin
	  let first_non_null = find_not_null encryption_block 2 in
	  match expected_len with
	    | None -> first_non_null
	    | Some len ->
	      if len < block_len - first_non_null
	      then raise Not_found;
	      block_len - len
	end
	| _ -> raise Not_found
    with Not_found ->
      res := false;
      0
  in
  if !res
  then String.sub encryption_block d_start (block_len - d_start)
  else raise PaddingError


struct pkcs1_asn1_struct_content = {
  hash_function : X509Basics.algorithmIdentifier;
  hash_digest : der_octetstring
}
asn1_alias pkcs1_asn1_struct

let raw_sign rnd_state typ hash msg n d =
  let oid, f = get_hash_fun_by_name hash in
  let digest = f msg in
  let asn1_struct = {
    hash_function = {
      X509Basics.algorithmId = oid;
      (* TODO: Clean that up: params should depend on the oid *)
      X509Basics.algorithmParams = Some (X509Basics.NoParams ())
    };
    hash_digest = digest
  } in
  encrypt rnd_state typ (dump_pkcs1_asn1_struct asn1_struct) n d

let raw_verify typ msg s n e =
  try
    let digest_info = decrypt typ None s n e in
    let input = Parsifal.input_of_string "DigestInfo" digest_info in
    let asn1_obj = parse_der_object input in
    (* TODO: This is rather ugly. Could it be a little cleaner *)
    match asn1_obj with
      | {a_class = C_Universal; a_tag = T_Sequence; a_content = Constructed
	[{a_class = C_Universal; a_tag = T_Sequence; a_content = Constructed
	    [{a_class = C_Universal; a_tag = T_OId; a_content = OId oid};
	     {a_class = C_Universal; a_tag = T_Null; a_content = Null}]};
	 {a_class = C_Universal; a_tag = T_OctetString; a_content = String (digest, _)}]}
      | {a_class = C_Universal; a_tag = T_Sequence; a_content = Constructed
	  [{a_class = C_Universal; a_tag = T_Sequence; a_content = Constructed
	    [{a_class = C_Universal; a_tag = T_OId; a_content = OId oid}]};
	   {a_class = C_Universal; a_tag = T_OctetString; a_content = String (digest, _)}]} ->
	let f = get_hash_fun_by_oid oid in
	f msg = digest
      | _ -> false
  with
    | Not_found _ | Parsifal.ParsingException _ -> false



let hash_fun_list = [
  [42;840;113549;2;5], "md5", X509Basics.APT_Null, md5sum;
  [43;14;3;2;26], "sha1", X509Basics.APT_Null, sha1sum;
  [96;840;1;101;3;4;2;1], "sha256", X509Basics.APT_Null, sha256sum;
(*  "sha384", [96;840;1;101;3;4;2;2], sha384sum;
  "sha512", [96;840;1;101;3;4;2;3], sha512sum;
  "sha224", [96;840;1;101;3;4;2;4], sha224sum;*)
]

let _ =
  List.iter (X509Basics.populate_alg_directory hash_funs) hash_fun_list
