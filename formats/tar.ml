open Parsifal
open BasePTypes
open PTypes


enum file_type (8, UnknownVal UnknownFileType) =
  | 0 -> NormalFile
  | 0x30 -> NormalFile
  | 0x31 -> HardLink
  | 0x32 -> SymbolicLink
  | 0x33 -> CharacterSpecial
  | 0x34 -> BlockSpecial
  | 0x35 -> Directory
  | 0x36 -> FIFO
  | 0x37 -> ContiguousFile


type tar_numstring = int

let parse_tar_numstring len input =
  let octal_value = parse_string (len - 1) input in
  drop_bytes 1 input;
  try int_of_string ("0o" ^ octal_value)
  with _ -> raise (ParsingException (CustomException "int_of_string", _h_of_si input))

let dump_tar_numstring len v =
  Printf.sprintf "%*.*o\x00" len len v

(* TODO: change stg to get len in here? *)
let value_of_tar_numstring i = VSimpleInt i


type optional_tar_numstring = int option

let parse_optional_tar_numstring len input =
  match try_parse (parse_tar_numstring len) input with
  | None ->
    drop_bytes len input;
    None
  | x -> x

let dump_optional_tar_numstring len = function
  | None -> String.make len '\x00'
  | Some v -> dump_tar_numstring len v

let value_of_optional_tar_numstring v = try_value_of value_of_tar_numstring v

struct ustar_header = {
  ustar_magic : magic("ustar");
  _ustar_magic_padding : binstring(3);
  owner_user : string(32);
  owner_group : string(32);
  device_major : optional_tar_numstring[8];
  device_minor : optional_tar_numstring[8];
  filename_prefix : string(155)
}

let parse_last_entry name input =
  if name.[0] = '\x00'
  then raise ParsingStop

struct tar_header = {
  file_name : string(100);
  parse_checkpoint _last_entry : last_entry(file_name);
  file_mode : tar_numstring[8];
  owner_uid : tar_numstring[8];
  owner_gid : tar_numstring[8];
  file_size : tar_numstring[12];
  timestamp : tar_numstring[12];
  checksum  : string(8);
  file_type : file_type;
  linked_file : string(100);
  optional ustar_header : ustar_header;
  hdr_padding : binstring
}

(* let check_crc32 _hdr _content _padding = () *)

struct tar_entry [with_lwt] = {
  header : container(512) of tar_header;
  file_content : binstring(header.file_size);
  file_padding : binstring(512 - (header.file_size mod 512))
  (* checksum_verification : check of check_crc32 (header, *)
  (*                                   file_content, file_padding); *)
}

alias tar_file [with_lwt] = list of tar_entry