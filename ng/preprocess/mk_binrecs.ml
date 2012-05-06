let rec ocaml_type_of_field_type = function
  | FT_Char -> "char"
  | FT_Integer _ -> "int"
  | FT_IPv4 | FT_IPv6 -> "string"
  | FT_String _ -> "string"
  | FT_List (_, subtype) ->
    "(" ^ (ocaml_type_of_field_type subtype) ^ ") list"
  | FT_Custom t -> t

let rec parse_fun_of_field_type name = function
  | FT_Char -> "parse_char"
  | FT_Integer IT_UInt8 -> "parse_uint8"
  | FT_Integer IT_UInt16 -> "parse_uint16"
  | FT_Integer IT_UInt24 -> "parse_uint24"
  | FT_Integer IT_UInt32 -> "parse_uint32"
  | FT_IPv4 -> "parse_string 4"
  | FT_IPv6 -> "parse_string 16"
  | FT_String (FixedLen n) -> "parse_string " ^ (string_of_int n)
  | FT_String (VarLen int_t) ->
    "parse_varlen_string \"" ^ name ^ "\" " ^ (parse_fun_of_field_type name (FT_Integer int_t))
  | FT_String Remaining -> "parse_rem_string"
  | FT_List (FixedLen n, subtype) ->
    "parse_list " ^ (string_of_int n) ^ " (" ^ (parse_fun_of_field_type name subtype) ^ ")"
  | FT_List (VarLen int_t, subtype) ->
    "parse_varlen_list \"" ^ name ^ "\" " ^ (parse_fun_of_field_type name (FT_Integer int_t)) ^
    " (" ^ (ocaml_type_of_field_type subtype) ^ ")"
  | FT_List (Remaining, subtype) ->
    "parse_rem_list (" ^ (parse_fun_of_field_type name subtype) ^ ")"
  | FT_Custom t -> "parse_" ^ t

let rec dump_fun_of_field_type = function
  | FT_Char -> "dump_char"
  | FT_Integer IT_UInt8 -> "dump_uint8"
  | FT_Integer IT_UInt16 -> "dump_uint16"
  | FT_Integer IT_UInt24 -> "dump_uint24"
  | FT_Integer IT_UInt32 -> "dump_uint32"

  | FT_String (VarLen int_t) ->
    "dump_varlen_string " ^ (dump_fun_of_field_type (FT_Integer int_t))
  | FT_IPv4
  | FT_IPv6
  | FT_String _ -> "dump_string"

  | FT_List (VarLen int_t, subtype) ->
    "dump_varlen_list " ^ (dump_fun_of_field_type (FT_Integer int_t)) ^
    " (" ^ (dump_fun_of_field_type subtype) ^ ")"
  | FT_List (_, subtype) ->
    "dump_list (" ^ (dump_fun_of_field_type subtype) ^ ")"

  | FT_Custom t -> "dump_" ^ t


let mk_desc_type (name, fields) =
  Printf.printf "type %s = {\n" name;
  let aux (fn, ft) =
    Printf.printf "  %s : %s;\n" fn (ocaml_type_of_field_type ft)
  in
  List.iter aux fields;
  print_endline "}\n\n"


let mk_parse_fun (name, fields) =
  Printf.printf "let parse_%s input =\n" name;
  let parse_aux (fn, ft) =
    Printf.printf "  let _%s = %s input in\n" fn (parse_fun_of_field_type name ft)
  in
  let mkrec_aux (fn, ft) = Printf.printf "    %s = _%s;\n" fn fn in
  List.iter parse_aux fields;
  print_endline "  {";
  List.iter mkrec_aux fields;
  print_endline "  }\n"


let mk_dump_fun (name, fields) =
  Printf.printf "let dump_%s %s =\n" name name;
  let dump_aux (fn, ft) =
    Printf.sprintf "  %s %s.%s" (dump_fun_of_field_type ft) name fn
  in
  print_endline (String.concat " ^ \n" (List.map dump_aux fields));
  print_endline "\n"


let handle_desc (desc : description) =
  print_endline "open ParsingEngine";
  print_endline "open DumpingEngine\n";
  mk_desc_type desc;
  mk_parse_fun desc;
  mk_dump_fun desc;
  print_newline ()


let _ =
  List.iter handle_desc descriptions