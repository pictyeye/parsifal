open Camlp4
open Camlp4.PreCast
open Camlp4.PreCast.Ast
open Syntax


(***************************)
(* Common camlp4 functions *)
(***************************)

let uid_of_ident = function
  | IdUid (_, u) -> u
  | i -> Loc.raise (loc_of_ident i) (Failure "uppercase identifier expected")

let lid_of_ident = function
  | IdLid (_, l) -> l
  | i -> Loc.raise (loc_of_ident i) (Failure "lowercase identifier expected")

let lid_of_expr = function
  | <:expr< $lid:id$ >> -> id
  | e -> Loc.raise (loc_of_expr e) (Failure "lowercase identifier expected")

let exp_true _loc = <:expr< $uid:"True"$ >>
let exp_false _loc = <:expr< $uid:"False"$ >>
let exp_bool _loc b = if b then exp_true _loc else exp_false _loc

let rec exp_of_list _loc = function
  | [] -> <:expr< $uid:"[]"$ >>
  | e::r -> <:expr< $uid:"::"$ $e$ $exp_of_list _loc r$ >>


let list_of_com_expr =
  let rec _list_of_com_expr = function
    | ExNil _ -> []
    | ExCom (_, e1, e2) -> (_list_of_com_expr e1)@(_list_of_com_expr e2)
    | e -> [e]
  in function
  | ExTup (_loc, e) -> _list_of_com_expr e
  | e -> [e]

let list_of_sem_expr =
  let rec _list_of_sem_expr = function
    | ExNil _ -> []
    | ExSem (_, e1, e2) -> (_list_of_sem_expr e1)@(_list_of_sem_expr e2)
    | e -> [e]
  in function
  | ExSeq (_loc, e) -> _list_of_sem_expr e
  | e -> [e]


let exp_qname _loc m n = match m with
  | None -> <:expr< $lid:n$ >>
  | Some module_name -> <:expr< $uid:module_name$.$lid:n$ >>

let qname_ident = function
  | <:ident< $lid:n$ >> -> None, n
  | <:ident< $uid:module_name$.$lid:n$ >> -> Some module_name, n
  | i -> Loc.raise (loc_of_ident i) (Failure "invalid identifier")

let mk_pm_fun _loc fname cases =
  let mk_case (p, e) = <:match_case< $p$ -> $e$ >> in
  let cases = List.map mk_case cases in
  let body = <:expr< fun [ $list:cases$ ] >>
  and fun_name = <:patt< $lid:fname$ >> in
  let bindings = <:binding< $pat:fun_name$ = $exp:body$ >> in
  [ <:str_item< value $bindings$ >> ]


let rec apply_exprs _loc e = function
  | [] -> e
  | a::r -> apply_exprs _loc <:expr< $e$ $a$ >> r


let mk_multiple_args_fun _loc fname argnames ?optargs:(optargnames=[]) body =
  let rec _mk_multiple_args_fun = function
    | [] -> body
    | arg::r -> <:expr< fun $ <:patt< $lid:arg$ >> $ -> $exp:_mk_multiple_args_fun r$ >>
  in
  let rec _mk_multiple_optargs_fun = function
    | [] -> _mk_multiple_args_fun argnames
    | (arg, e)::r -> <:expr< fun $pat:PaOlbi (_loc, arg, <:patt< $lid:arg$ >>, e)$ -> $exp:_mk_multiple_optargs_fun r$ >>
  in
  let b = <:binding< $pat: <:patt< $lid:fname$ >> $ = $exp:_mk_multiple_optargs_fun optargnames$ >>
  in <:str_item< value $b$ >>



(********************************************)
(* Types representing the new constructions *)
(********************************************)

(* Common *)

type parsifal_option =
  | DoLwt
  | ExactParser
  | EnrichByDefault
  | ExhaustiveChoices
  | Param of string list

type parsifal_construction =
  | Enum
  | Struct
  | Union
  | Alias
  | ASN1Alias

let check_options construction options =
  let rec aux opts = match construction, opts with
    | Enum, (_loc, ExactParser)::_ ->
      Loc.raise _loc (Failure "with_exact/top is not allowed for an enum.")
    | Enum, (_loc, Param _)::_ ->
      Loc.raise _loc (Failure "params are not allowed for an enum.")
    | (Enum|Struct|Alias|ASN1Alias), (_loc, EnrichByDefault)::_ ->
      Loc.raise _loc (Failure "enrich is only allowed for unions.")
    | (Enum|Struct|Alias|ASN1Alias), (_loc, ExhaustiveChoices)::_ ->      
      Loc.raise _loc (Failure "exhaustive is only allowed for unions.")
    | _, (_, o)::r -> o::(aux r)
    | _, [] -> []
  in aux options

let mk_params opts =
  let rec _mk_params = function
    | [] -> []
    | (Param l)::r -> l::(_mk_params r)
    | _::r -> _mk_params r
  in List.concat (_mk_params opts)


(* Enums *)

type enum_unknown_behaviour =
  | UnknownVal of string
  | Exception of string

type enum_description = {
  ename : string;
  size : int;
  echoices : (Loc.t * string * string * string) list;
  unknown_behaviour : enum_unknown_behaviour;
  edo_lwt : bool;
}


(* PTypes *)

type field_len =
  | ExprLen of expr    (* size in bytes of the field *)
  | VarLen of string   (* name of the integer type used *)
  | Remaining

type ptype =
  | PT_Empty
  | PT_Char
  | PT_Int of string                        (* name of the integer type *)
  | PT_String of field_len * bool
  | PT_Array of expr * ptype
  | PT_List of field_len * ptype
  | PT_Container of field_len * ptype  (* the string corresponds to the integer type for the field length *)
  | PT_Custom of (string option) * string * expr list * expr list (* the expr lists are the args to give to parse / dump *)
  | PT_CheckFunction of (string option) * string * expr list * bool  (* the last boolean is set if the function is in fact a reference *)


(* Records *)

type struct_description = {
  rname : string;
  fields : (Loc.t * string * ptype * bool) list;
  rdo_lwt : bool;
  rdo_exact : bool;
  rparse_params : string list;
  rdump_params : string list;
}


(* Unions *)

type union_description = {
  uname : string;
  uchoices : (Loc.t * patt * string * ptype) list;   (* loc, discriminating value, constructor, subtype *)
  unparsed_constr : string;
  unparsed_type : ptype;
  udo_lwt : bool;
  udo_exact : bool;
  uenrich : bool;
  uexhaustive : bool;
  uparse_params : string list;
  udump_params : string list;
}


(* Aliases *)

type alias_description = {
  aname : string;
  atype : ptype;
  ado_lwt : bool;
  ado_exact : bool;
  aparse_params : string list;
  adump_params : string list;
}


(* ASN1 Aliases *)
(* TODO: Add options [keep header/keep raw string] *)

type asn1_alias_type =
  | Primitive of ptype
  | Sequence of ptype
  | SequenceOf of ptype

type asn1_alias_description = {
  aaname : string;
  aaheader : string * string;
  aatype : asn1_alias_type;
  aado_lwt : bool;
  aado_exact : bool;
  aaparse_params : string list;
  aadump_params : string list;
}


(***************************)
(* Input AST interpreter   *)
(*   AST -> ParsifalSyntax *)
(***************************)

(* Options *)

let opts_of_seq_expr expr =
  let opt_of_exp e =
    let _loc = loc_of_expr e in
    match e with
    | <:expr< $lid:"with_lwt"$ >>   -> [_loc, DoLwt]
    | <:expr< $lid:"with_exact"$ >> -> [_loc, ExactParser]
    | <:expr< $lid:"top"$ >>        -> [_loc, DoLwt; _loc, ExactParser]
    | <:expr< $lid:"enrich"$ >>     -> [_loc, EnrichByDefault]
    | <:expr< $lid:"exhaustive"$ >> -> [_loc, ExhaustiveChoices]
    | <:expr< $lid:"param"$ $e$ >>  -> [_loc, Param (List.map lid_of_expr (list_of_com_expr e))]
    | _ -> Loc.raise (loc_of_expr e) (Failure "unknown option")
  in
  List.concat (List.map opt_of_exp (list_of_sem_expr expr))


(* Enum choices *)

let rec choices_of_match_cases = function
  | McNil _ -> []
  | McOr (_, m1, m2) ->
    (choices_of_match_cases m1)@(choices_of_match_cases m2)
  | McArr (_loc, <:patt< $int:i$ >>, <:expr< >>,
	   ExTup (_, ExCom (_, <:expr< $uid:c$ >>, <:expr< $str:s$ >> ))) ->
    [_loc, i, c, s]
  | McArr (_loc, <:patt< $int:i$ >>, <:expr< >>, <:expr< $uid:c$ >> ) ->
    [_loc, i, c, c]
  | mc -> Loc.raise (loc_of_match_case mc) (Failure "Invalid choice for an enum")


(* PTypes *)

type decorator_type = (expr option) * (expr option)

let expr_list_of_decorator = function
  | None -> []
  | Some e -> list_of_sem_expr e

let ptype_of_ident name decorator subtype =
  match name, decorator, subtype with
    | <:ident< $lid:"char"$ >>, (None, None), None -> PT_Char
    | <:ident< $lid:("uint8"|"uint16"|"uint24"|"uint32" as int_t)$ >>, (None, None), None -> PT_Int int_t

    | <:ident< $lid:"list"$ >>, (None, None), Some t ->
      PT_List (Remaining, t)
    | <:ident< $lid:"list"$ >>, (None, Some e), Some t ->
      PT_List (ExprLen e, t)
    | <:ident< $lid:"list"$ >>, (Some <:expr< $lid:("uint8"|"uint16"|"uint24"|"uint32" as int_t)$ >>, None), Some t ->
      PT_List (VarLen int_t, t)
    | <:ident< $lid:"list"$ >> as i,   _, _ ->
      Loc.raise (loc_of_ident i) (Failure "invalid list type")

    | <:ident< $lid:"array"$ >>, (None, Some e), Some t ->
      PT_Array (e, t)

    | <:ident< $lid:"container"$ >>, (None, Some e), Some t ->
      PT_Container (ExprLen e, t)
    | <:ident< $lid:"container"$ >>, (Some <:expr< $lid:("uint8"|"uint16"|"uint24"|"uint32" as int_t)$ >>, None), Some t ->
      PT_Container (VarLen int_t, t)
    | <:ident< $lid:"container"$ >> as i, _, _ ->
      Loc.raise (loc_of_ident i) (Failure "invalid container type")

    | <:ident< $lid:"string"$ >>,    (None, None), None-> PT_String (Remaining, false)
    | <:ident< $lid:"binstring"$ >>, (None, None), None -> PT_String (Remaining, true)
    | <:ident< $lid:"string"$ >>,    (None, Some e), None ->
      PT_String (ExprLen e, false)
    | <:ident< $lid:"binstring"$ >>, (None, Some e), None ->
      PT_String (ExprLen e, true)
    | <:ident< $lid:"string"$ >>,    (Some <:expr< $lid:("uint8"|"uint16"|"uint24"|"uint32" as int_t)$ >>, None), None ->
      PT_String (VarLen int_t, false)
    | <:ident< $lid:"binstring"$ >>, (Some <:expr< $lid:("uint8"|"uint16"|"uint24"|"uint32" as int_t)$ >>, None), None ->
      PT_String (VarLen int_t, true)
    | <:ident< $lid:("string" | "binstring")$ >> as i, _, _ ->
      Loc.raise (loc_of_ident i) (Failure "invalid string type")

    | <:ident< $lid:"check"$ >>,    (None, None), Some (PT_Custom (m, n, args, [])) ->
      PT_CheckFunction (m, n, args, false)
    | <:ident< $lid:"checkref"$ >>, (None, None), Some (PT_Custom (m, n, args, [])) ->
      PT_CheckFunction (m, n, args, true)
    | <:ident< $lid:("check"|"checkref")$ >> as i, _, _ ->
      Loc.raise (loc_of_ident i) (Failure "invalid check declaration")

    | custom_identifier, (dec1, dec2), None ->
      let module_name, name = qname_ident (custom_identifier)
      and e1 = expr_list_of_decorator dec1
      and e2 = expr_list_of_decorator dec2 in
      PT_Custom (module_name, name, e1@e2, e1)

    | i, _, _ -> Loc.raise (loc_of_ident i) (Failure "invalid identifier for a type")



(*****************************)
(* OCaml definitions         *)
(*   ParsifalSyntax -> OCaml *)
(*****************************)

(* Enum exception *)

let mk_enum_exception _loc enum = match enum with
  | {unknown_behaviour = Exception e} ->
    [ <:str_item< exception  $typ:<:ctyp< $uid:e$ >>$  >> ]
  | _ -> []


(* Enum type *)

let mk_enum_type _loc enum =
  let ctors = List.map (fun (_loc, _, n, _) -> <:ctyp< $uid:n$ >>) enum.echoices in
  let suffix_choice = match enum.unknown_behaviour with
    | UnknownVal v -> [ <:ctyp< $ <:ctyp< $uid:v$ >> $ of int >> ]
    | _ -> []
  in
  let ctyp_ctors = ctors@suffix_choice in
  [ <:str_item< type $lid:enum.ename$ = [ $list:ctyp_ctors$ ] >> ]


(* Enum primitive functions *)

let mk_string_of_enum _loc enum =
  let mk_case (_loc, _, n, d) = <:patt< $uid:n$ >>, <:expr< $str:d$ >> in
  let _cases = List.map mk_case enum.echoices in
  let cases = match enum.unknown_behaviour with
    | UnknownVal v ->
      let p = <:patt< $ <:patt< $uid:v$ >> $ $ <:patt< $lid:"i"$ >> $ >>
      and e = <:expr< $str:"Unknown " ^ enum.ename ^ " ("$ ^ (string_of_int i) ^ $str:")"$ >>
      in _cases@[p, e]
    | _ -> _cases
  and fname = "string_of_" ^ enum.ename in
  mk_pm_fun _loc fname cases

let mk_int_of_enum _loc enum =
  let mk_case (_loc, v, n, _) = <:patt< $uid:n$ >>, <:expr< $int:v$ >> in
  let _cases = List.map mk_case enum.echoices in
  let cases = match enum.unknown_behaviour with
    | UnknownVal v ->
      let p = <:patt< $ <:patt< $uid:v$ >> $ $ <:patt< $lid:"i"$ >> $ >>
      and e = <:expr< $lid:"i"$ >>
      in _cases@[p, e]
    | _ -> _cases
  and fname = "int_of_" ^ enum.ename in
  mk_pm_fun _loc fname cases

let mk_enum_of_int _loc enum =
  let mk_case (_loc, v, n, _) = <:patt< $int:v$ >>, <:expr< $uid:n$ >> in
  let _cases = List.map mk_case enum.echoices in
  let last_p, last_e = match enum.unknown_behaviour with
    | UnknownVal v ->
      <:patt< $lid:"i"$ >>,
      <:expr< $ <:expr< $uid:v$ >> $ $ <:expr< $lid:"i"$ >> $ >>
    | Exception e ->
      <:patt< _ >>, <:expr< raise $uid:e$ >>
  in
  let cases = _cases@[last_p, last_e]
  and fname = enum.ename ^ "_of_int" in
  mk_pm_fun _loc fname cases

let mk_enum_of_string _loc enum =
  let mk_case (_loc, _, n, d) = <:patt< $str:d$ >>, <:expr< $uid:n$ >> in
  let _cases = List.map mk_case enum.echoices in
  let last_p = <:patt< $lid:"s"$ >>
  and eoi = <:expr< $lid:enum.ename ^ "_of_int"$ >> in
  let last_e = <:expr< $eoi$  (int_of_string s) >> in
  let cases = _cases@[last_p, last_e]
  and fname = enum.ename ^ "_of_string" in
  mk_pm_fun _loc fname cases


(* PTypes *)

let rec ocaml_type_of_ptype _loc = function
  | PT_Empty
  | PT_CheckFunction _ -> <:ctyp< $lid:"unit"$ >>
  | PT_Char -> <:ctyp< $lid:"char"$ >>
  | PT_Int _ -> <:ctyp< $lid:"int"$ >>
  | PT_String _ -> <:ctyp< $lid:"string"$ >>
  | PT_List (_, subtype) -> <:ctyp< list $ocaml_type_of_ptype _loc subtype$ >>
  | PT_Array (_, subtype) -> <:ctyp< array $ocaml_type_of_ptype _loc subtype$ >>
  | PT_Container (_, subtype) -> ocaml_type_of_ptype _loc subtype
  | PT_Custom (None, n, _, _) -> <:ctyp< $lid:n$ >>
  | PT_Custom (Some m, n, _, _) -> <:ctyp< $uid:m$.$lid:n$ >>


(* Struct type *)

let ocaml_type_of_field_type _loc t opt =
  let real_t = ocaml_type_of_ptype _loc t in
  if opt then <:ctyp< option $real_t$ >> else real_t

let rec remove_dummy_fields = function
  | [] -> []
  | (_, _, PT_Empty, _)::r | (_, _, PT_CheckFunction _, _)::r -> remove_dummy_fields r
  | f::r -> f::(remove_dummy_fields r)

let mk_struct_type _loc record =
  let mk_line (_loc, n, t, opt) = <:ctyp< $lid:n$ : $ocaml_type_of_field_type _loc t opt$ >> in
  let ctyp_fields = List.map mk_line (remove_dummy_fields record.fields) in
  [ <:str_item< type $lid:record.rname$ = { $list:ctyp_fields$ } >> ]


(* Union type *)

let keep_unique_cons union =
  let rec _keep_unique_cons names accu = function
  | [] -> List.rev accu
  | ((_, _, n, _) as c)::r  ->
    if List.mem n names
    then _keep_unique_cons names accu r
    else _keep_unique_cons (n::names) (c::accu) r
  in _keep_unique_cons [] [] union.uchoices

let mk_union_enrich_bool _loc union =
  let bool_name = <:patt< $lid:"enrich_" ^ union.uname$ >>
  and bool_val = <:expr< ref $exp_bool _loc union.uenrich$ >> in
  [ <:str_item< value $ <:binding< $pat:bool_name$ = $exp:bool_val$ >> $ >> ]

let mk_union_type _loc union =
  let rec mk_ctors = function
    | [] ->
      [ <:ctyp< $ <:ctyp< $uid:union.unparsed_constr$ >> $ of
	  $ocaml_type_of_ptype _loc union.unparsed_type$ >> ]
    | (_loc, _, n, PT_Empty)::r ->
      (<:ctyp< $uid:n$ >>)::(mk_ctors r)
    | (_loc, _, n, t)::r ->	
      ( <:ctyp< $ <:ctyp< $uid:n$ >> $ of
          $ocaml_type_of_ptype _loc t$ >> )::(mk_ctors r)
  in
  let ctyp_ctors = mk_ctors (keep_unique_cons union) in
  [ <:str_item< type $lid:union.uname$ = [ $list:ctyp_ctors$ ] >> ]


(* Alias type *)

let mk_alias_type _loc alias =
  [ <:str_item< type $lid:alias.aname$ = $ocaml_type_of_ptype _loc alias.atype$ >> ]


(* ASN1 Alias type *)
let mk_asn1_alias_type _loc alias =
  match alias.aatype with
  | Primitive subtype
  | Sequence subtype ->
    [ <:str_item< type $lid:alias.aaname$ = $ocaml_type_of_ptype _loc subtype$ >> ]
  | SequenceOf subtype -> 
    [ <:str_item< type $lid:alias.aaname$ = list $ocaml_type_of_ptype _loc subtype$ >> ]


(*****************************)
(* OCaml functions           *)
(*   ParsifalSyntax -> OCaml *)
(*****************************)

(* Common *)

type function_type = Parse | LwtParse | Dump | Print

let rec fun_of_ptype ftype _loc name t =
  let prefix = match ftype with
    | Parse -> "parse_" | LwtParse -> "lwt_parse_"
    | Dump -> "dump_"   | Print -> "print_"
  in
  let mkf fname = exp_qname _loc (Some "Parsifal") (prefix ^ fname) in
  match t, ftype with
  (* Trivial ptypes *)
    | PT_Empty, _ -> mkf "empty"
    | PT_Char, _ -> mkf "char"
    | PT_Int int_t, _ -> mkf int_t

  (* String *)
    | PT_String (VarLen int_t, _), Dump ->
      <:expr< $mkf "varlen_string"$ $mkf int_t$ >>
    | PT_String (_, _), Dump -> mkf "string"

    | PT_String (_, true), Print -> mkf "binstring"
    | PT_String (_, false), Print -> mkf "printablestring"

    | PT_String (ExprLen e, _), (Parse|LwtParse) ->
      <:expr< $mkf "string"$ $e$ >>
    | PT_String (VarLen int_t, _), (Parse|LwtParse) ->
      <:expr< $mkf "varlen_string"$ $str:name$ $mkf int_t$ >>
    | PT_String (Remaining, _), (Parse|LwtParse) ->
      mkf "rem_string"

  (* List *)
    | PT_List (VarLen int_t, subtype), Dump ->
      <:expr< $mkf "varlen_list"$ $mkf int_t$
	      $fun_of_ptype ftype _loc name subtype$ >>
    | PT_List (_, subtype), (Dump|Print) ->
      <:expr< $mkf "list"$ $fun_of_ptype ftype _loc name subtype$ >>

    | PT_List (ExprLen e, subtype), (Parse|LwtParse) ->
      <:expr< $mkf "list"$ $e$
              $fun_of_ptype ftype _loc name subtype$ >>
    | PT_List (Remaining, subtype), (Parse|LwtParse) ->
      <:expr< $mkf "rem_list"$
              $fun_of_ptype ftype _loc name subtype$ >>
    (* For VarLen lists, the items are parsed in string_inputs *)
    | PT_List (VarLen int_t, subtype), (Parse|LwtParse) ->
      <:expr< $mkf "varlen_list"$ $str:name$ $mkf int_t$
              $fun_of_ptype Parse _loc name subtype$ >>

  (* Array *)
    | PT_Array (_, subtype), (Dump|Print) ->
      <:expr< $mkf "array"$ $fun_of_ptype ftype _loc name subtype$ >>

    | PT_Array (e, subtype), (Parse|LwtParse) ->
      <:expr< $mkf "array"$ $e$
              $fun_of_ptype ftype _loc name subtype$ >>

  (* Container *)
    | PT_Container (VarLen int_t, subtype), Dump ->
      <:expr< $mkf "container"$ $mkf int_t$
	      $fun_of_ptype ftype _loc name subtype$ >>

    (* For containers, the subtype is always parsed with strings *)
    | PT_Container (ExprLen e, subtype), (Parse|LwtParse) ->
      <:expr< $mkf "container"$ $str:name$ $e$
              $fun_of_ptype Parse _loc name subtype$ >>
    | PT_Container (VarLen int_t, subtype), (Parse|LwtParse) ->
      <:expr< $mkf "varlen_container"$ $str:name$ $mkf int_t$
              $fun_of_ptype Parse _loc name subtype$ >>

    (* General case *)
    | PT_Container (_, subtype), _ ->
      fun_of_ptype ftype _loc name subtype

  (* Custom *)
    | PT_Custom (m, n, e, _), (Parse|LwtParse) ->
      apply_exprs _loc (exp_qname _loc m (prefix ^ n)) e
    | PT_Custom (m, n, _, e), Dump ->
      apply_exprs _loc (exp_qname _loc m (prefix ^ n)) e
    | PT_Custom (m, n, _, _), Print -> exp_qname _loc m (prefix ^ n)

  (* Check functions *)
    | PT_CheckFunction (m, n, e, false), (Parse|LwtParse) ->
      if ftype = Dump then <:expr< $str:""$ >>
      else apply_exprs _loc (exp_qname _loc m (prefix ^ n)) e
    | PT_CheckFunction (m, n, e, true), (Parse|LwtParse) ->
      if ftype = Dump then <:expr< $str:""$ >>
      else apply_exprs _loc ( <:expr< ! $exp_qname _loc m (prefix ^ n)$ >> ) e

    | PT_CheckFunction _, (Dump|Print) -> mkf "empty"


let mk_exact_parse_fun _loc name parse_params =
  let partial_params = List.map (fun p -> <:expr< $lid:p$ >>) parse_params
  and params = parse_params@["input"] in
  let parse_fun = apply_exprs _loc (exp_qname _loc None ("parse_" ^ name)) partial_params in
  let body = <:expr< Parsifal.exact_parse $parse_fun$ input >> in
  [ mk_multiple_args_fun _loc ("exact_parse_" ^ name) params body ]


(* Enum *)

let mk_enum_parse_fun _loc enum = 
  if enum.size mod 8 = 0 then begin
    let fname = "parse_" ^ enum.ename
    and parse_int_fun = exp_qname _loc (Some "Parsifal") ("parse_uint" ^ (string_of_int enum.size))
    and eoi = <:expr< $lid:enum.ename ^ "_of_int"$ >> in
    let body = <:expr< $eoi$ ($parse_int_fun$ input) >> in
    [ mk_multiple_args_fun _loc fname ["input"] body ]
  end else []

let mk_enum_lwt_parse_fun _loc enum =
  if enum.edo_lwt && enum.size mod 8 = 0 then begin
    let fname = "lwt_parse_" ^ enum.ename
    and lwt_parse_int_fun = exp_qname _loc (Some "Parsifal") ("lwt_parse_uint" ^ (string_of_int enum.size))
    and eoi = <:expr< $lid:enum.ename ^ "_of_int"$ >> in
    let body = <:expr< Lwt.bind ($lwt_parse_int_fun$ input) (Lwt.wrap1 $eoi$) >> in
    [ mk_multiple_args_fun _loc fname ["input"] body ]
  end else []

let mk_enum_dump_fun _loc enum =
  if enum.size mod 8 = 0 then begin
    let fname = "dump_" ^ enum.ename
    and dump_int_fun = exp_qname _loc (Some "Parsifal") ("dump_uint" ^ (string_of_int enum.size))
    and ioe = <:expr< $lid:"int_of_" ^ enum.ename$ >> in
    let body = <:expr< $dump_int_fun$ ($ioe$ $lid:enum.ename$) >> in
    [ mk_multiple_args_fun _loc fname [enum.ename] body ]
  end else []

let mk_enum_print_fun _loc enum =
  let fname = "print_" ^ enum.ename
  and print_fun = exp_qname _loc (Some "Parsifal") ("print_enum")
  and ioe = <:expr< $lid:"int_of_" ^ enum.ename$ >>
  and soe = <:expr< $lid:"string_of_" ^ enum.ename$ >> in
  let body = <:expr< $print_fun$ $soe$ $ioe$ $int:string_of_int (enum.size / 4)$
              ~indent:indent ~name:name $lid:enum.ename$ >>
  and optargs = ["indent", <:expr< $str:""$ >>; "name", <:expr< $str:enum.ename$ >>] in
  [ mk_multiple_args_fun _loc fname [enum.ename] ~optargs:optargs body ]


(* Struct *)

let mk_struct_parse_fun _loc record =
  let rec mk_body = function
    | [] ->
      let single_assign (_loc, n, _, _) = <:rec_binding< $lid:n$ = $exp: <:expr< $lid:n$ >> $ >> in
      let assignments = List.map single_assign (remove_dummy_fields record.fields) in
      <:expr< { $list:assignments$ } >>
    | (_loc, n, t, optional)::r ->
      let tmp = mk_body r
      and f = fun_of_ptype Parse _loc n t in
      if optional
      then <:expr< let $lid:n$ = Parsifal.try_parse $f$ input in $tmp$ >>
      else <:expr< let $lid:n$ = $f$ input in $tmp$ >>
  in
  let body = mk_body record.fields in
  let params = record.rparse_params@["input"] in
  [ mk_multiple_args_fun _loc ("parse_" ^ record.rname) params body ]

let mk_struct_lwt_parse_fun _loc record =
  let rec mk_body = function
    | [] ->
      let single_assign (_loc, n, _, _) = <:rec_binding< $lid:n$ = $exp: <:expr< $lid:n$ >> $ >> in
      let assignments = List.map single_assign (remove_dummy_fields record.fields) in
      <:expr< Lwt.return { $list:assignments$ } >>
    | (_loc, n, t, optional)::r ->
      let tmp = mk_body r
      and f = fun_of_ptype LwtParse _loc n t in
      if optional
      then <:expr< Lwt.bind (LwtParsingEngine.try_lwt_parse $f$ input) (fun $lid:n$ -> $tmp$ ) >>
      else <:expr< Lwt.bind ($f$ input) (fun $lid:n$ -> $tmp$ ) >>
  in
  if record.rdo_lwt then begin
    let body = mk_body record.fields in
    let params = record.rparse_params@["input"] in
    [ mk_multiple_args_fun _loc ("lwt_parse_" ^ record.rname) params body ]
  end else []

let mk_struct_exact_parse _loc record =
  if record.rdo_exact
  then mk_exact_parse_fun _loc record.rname record.rparse_params
  else []


let mk_struct_dump_fun _loc record =
  let dump_one_field (_loc, n, t, optional) =
    let f = fun_of_ptype Dump _loc n t in
    if optional
    then <:expr< Parsifal.try_dump $f$ $lid:record.rname$.$lid:n$ >>
    else <:expr< $f$ $lid:record.rname$.$lid:n$ >>
  in
  let fields_dumped_expr = exp_of_list _loc (List.map dump_one_field (remove_dummy_fields record.fields)) in
  let body =
    <:expr< let $lid:"fields_dumped"$ = $fields_dumped_expr$ in
	    String.concat "" fields_dumped >>
  in
  let params = record.rdump_params@[record.rname] in
  [ mk_multiple_args_fun _loc ("dump_" ^ record.rname) params body ]

let mk_struct_print_fun _loc record =
  let print_one_field (_loc, n, t, optional) =
    let f = fun_of_ptype Print _loc n t in
    if optional
    then <:expr< Parsifal.try_print $f$ ~indent:new_indent ~name:$str:n$ $lid:record.rname$.$lid:n$ >>
    else <:expr< $f$ ~indent:new_indent ~name:$str:n$ $lid:record.rname$.$lid:n$ >>
  in
  let fields_printed_expr = exp_of_list _loc (List.map print_one_field (remove_dummy_fields record.fields)) in
  let body =
    <:expr< let new_indent = indent ^ "  " in
	    let $lid:"fields_printed"$ = $fields_printed_expr$ in
	    indent ^ name ^ " {\\n" ^
	    (String.concat "" fields_printed) ^
	    indent ^ "}\\n" >>
  in
  [ mk_multiple_args_fun _loc ("print_" ^ record.rname) [record.rname]
      ~optargs:(["indent", <:expr< $str:""$ >>; "name", <:expr< $str:record.rname$ >> ]) body ]


(* Union *)

let mk_union_parse_fun _loc union =
  let mk_case = function
    | (_loc, p, c, PT_Empty) ->
      <:match_case< $p$ -> $ <:expr< $uid:c$ >> $ >>
    | (_loc, p, c, t) ->
      let parse_fun = fun_of_ptype Parse _loc union.uname t in
      <:match_case< $p$ -> $ <:expr< $uid:c$ >> $ ($parse_fun$ input) >>
  and mk_unparsed =
    let parse_fun = fun_of_ptype Parse _loc union.uname union.unparsed_type in
    <:expr< $uid:union.unparsed_constr$ ($parse_fun$ input) >>
  in
  let parsed_cases = List.map mk_case union.uchoices
  and last_case = <:match_case< _ -> $mk_unparsed$ >> in
  let cases = if union.uexhaustive then parsed_cases else parsed_cases@[last_case] in
  let body =
    <:expr< if Parsifal.should_enrich $lid:"enrich_" ^ union.uname$ enrich
      then match discriminator with [ $list:cases$ ]
      else $mk_unparsed$ >>
  in
  let params = union.uparse_params@["discriminator"; "input"] in
  [ mk_multiple_args_fun _loc ("parse_" ^ union.uname)
      ~optargs:["enrich", exp_false _loc] params body ]

let mk_union_lwt_parse_fun _loc union =
  let mk_case = function
    | (_loc, p, c, PT_Empty) ->
      <:match_case< $p$ -> Lwt.return $ <:expr< $uid:c$ >> $ >>
    | (_loc, p, c, t) ->
      let parse_fun = fun_of_ptype LwtParse _loc union.uname t in
      <:match_case< $p$ -> Lwt.bind ($parse_fun$ input) (fun v -> Lwt.return ($ <:expr< $uid:c$ >> $ v)) >>
  and mk_unparsed =
    let parse_fun = fun_of_ptype LwtParse _loc union.uname union.unparsed_type in
    <:expr< Lwt.bind ($parse_fun$ input) (fun v -> Lwt.return ($ <:expr< $uid:union.unparsed_constr$ >> $ v)) >>
  in
  if union.udo_lwt then begin
    let parsed_cases = List.map mk_case union.uchoices
    and last_case = <:match_case< _ -> $mk_unparsed$ >> in
    let cases = if union.uexhaustive then parsed_cases else parsed_cases@[last_case] in
    let body =
      <:expr< if Parsifal.should_enrich $lid:"enrich_" ^ union.uname$ enrich
	then match discriminator with [ $list:cases$ ]
	else $mk_unparsed$ >>
    in
    let params = union.uparse_params@["discriminator"; "input"] in
    [ mk_multiple_args_fun _loc ("lwt_parse_" ^ union.uname)
	~optargs:["enrich", exp_false _loc] params body ]
  end else []

let mk_union_exact_parse _loc union =
  if union.udo_exact
  then mk_exact_parse_fun _loc union.uname (union.uparse_params@["discriminator"])
  else []


let mk_union_dump_fun _loc union =
  let mk_case = function
    | _loc, _, c, PT_Empty ->
      <:match_case< $ <:patt< $uid:c$ >> $ -> "" >>
    | _loc, n, c, t ->
      <:match_case< ( $ <:patt< $uid:c$ >> $  $ <:patt< $lid:"x"$ >> $ ) ->
                    $ <:expr< $fun_of_ptype Dump _loc union.uname t$ x >> $ >>
  in
  let last_case =
    <:match_case< ( $ <:patt< $uid:union.unparsed_constr$ >> $  $ <:patt< $lid:"x"$ >> $ ) ->
                  $ <:expr< $fun_of_ptype Dump _loc union.uname union.unparsed_type$ x >> $ >>
  in
  let cases = (List.map mk_case (keep_unique_cons union))@[last_case] in
  let body = <:expr< fun [ $list:cases$ ] >> in
  [ mk_multiple_args_fun _loc ("dump_" ^ union.uname) union.udump_params body ]

let mk_union_print_fun _loc union =
  let mk_case = function
    | _loc, _, c, PT_Empty ->
      <:match_case< $ <:patt< $uid:c$ >> $ ->
      Parsifal.print_binstring ~indent:indent ~name:name "" >>
    | _loc, n, c, t ->
      <:match_case< ( $ <:patt< $uid:c$ >> $  $ <:patt< $lid:"x"$ >> $ ) ->
                    $ <:expr< $fun_of_ptype Print _loc union.uname t$ ~indent:indent ~name:name x >> $ >>
  in
  let last_case =
    <:match_case< ( $ <:patt< $uid:union.unparsed_constr$ >> $  $ <:patt< $lid:"x"$ >> $ ) ->
                  $ <:expr< $fun_of_ptype Print _loc union.uname union.unparsed_type$
                                  ~indent:indent ~name:(name ^ "[Unparsed]") x >> $ >>
  in
  let cases = (List.map mk_case (keep_unique_cons union))@[last_case] in
  let body = <:expr< fun [ $list:cases$ ] >> in
  [ mk_multiple_args_fun _loc ("print_" ^ union.uname) [] 
      ~optargs:(["indent", <:expr< $str:""$ >>; "name", <:expr< $str:union.uname$ >> ]) body ]


(* Alias *)

let mk_alias_parse_fun _loc alias =
  let body = <:expr< $fun_of_ptype Parse _loc alias.aname alias.atype$ >> in
  [ mk_multiple_args_fun _loc ("parse_" ^ alias.aname) alias.aparse_params body ]

let mk_alias_lwt_parse_fun _loc alias =
  if alias.ado_lwt then begin
    let body = <:expr< $fun_of_ptype LwtParse _loc alias.aname alias.atype$ >> in
    [ mk_multiple_args_fun _loc ("lwt_parse_" ^ alias.aname) alias.aparse_params body ]
  end else []

let mk_alias_exact_parse_fun _loc alias =
  if alias.ado_exact
  then mk_exact_parse_fun _loc alias.aname alias.aparse_params
  else []

let mk_alias_dump_fun _loc alias =
  let body = <:expr< $fun_of_ptype Dump _loc alias.aname alias.atype$ >> in
  [ mk_multiple_args_fun _loc ("dump_" ^ alias.aname) alias.adump_params body ]
  
let mk_alias_print_fun _loc alias =
  let body = <:expr< $fun_of_ptype Print _loc alias.aname alias.atype$ >> in
  [ mk_multiple_args_fun _loc ("print_" ^ alias.aname) [] 
      ~optargs:(["indent", <:expr< $str:""$ >>; "name", <:expr< $str:alias.aname$ >> ]) body ]


(************************)
(* Camlp4 grammar rules *)
(************************)

let mk_str_items funs _loc x =
  let _apply f = f _loc x in
  let rec mk_sequence = function
    | [] -> <:str_item< >>
    | [si] -> <:str_item< $si$ >>
    | si::r -> <:str_item< $si$; $mk_sequence r$ >>
  in
  mk_sequence (List.concat (List.map _apply funs))


EXTEND Gram
  GLOBAL: str_item;

  option_list: [[
    -> []
  | "["; "]" -> []
  | "["; _opts = expr; "]" -> opts_of_seq_expr _opts
  ]];


  enum_unknown_behaviour: [[
    "Exception"; x = ident -> Exception (uid_of_ident x)
  | "UnknownVal"; x = ident -> UnknownVal (uid_of_ident x)
  ]];


  ptype_decorator: [[
    "("; e = expr; ")" -> (None, Some e)
  | "["; e = expr; "]" -> (Some e, None)
  | "["; e1 = expr; "]"; "("; e2 = expr; ")" -> (Some e1, Some e2)
  | -> (None, None)
  ]];

  ptype: [[
    "("; t = SELF; ")" -> t
  | type_name = ident; e = ptype_decorator; t = OPT [ "of"; _t = ptype -> _t ] ->
    ptype_of_ident type_name e t
  ]];


  struct_field: [[
    optional = OPT [ "optional" -> () ]; name = ident; ":"; field = ptype  ->
    (_loc, lid_of_ident name, field, optional != None)
  ]];


  union_choice: [[
    "|"; discr_val = patt; "->"; constructor = ident; "of"; t = ptype ->
      (_loc, discr_val, uid_of_ident constructor, t)
  | "|"; discr_val = patt; "->"; constructor = ident ->
      (_loc, discr_val, uid_of_ident constructor, PT_Empty)
  ]];

  union_unparsed_behaviour: [[
    unparsed_const = ident -> (uid_of_ident unparsed_const, PT_String (Remaining, true))
  | unparsed_const = ident; "of"; unparsed_type = ptype -> (uid_of_ident unparsed_const, unparsed_type)
  ]];


  str_item: [[
    "enum"; enum_name = ident; opts = option_list;
    "("; sz = INT; ","; u_b = enum_unknown_behaviour; ")";
    "="; _choices = match_case ->
    let choices = choices_of_match_cases _choices
    and options = check_options Enum opts in
    let enum_descr = {
      ename = lid_of_ident enum_name;
      size = int_of_string sz;
      echoices = choices;
      unknown_behaviour = u_b;
      edo_lwt = List.mem DoLwt options
    } in
    let fns = [mk_enum_exception; mk_enum_type; mk_string_of_enum;
	       mk_int_of_enum; mk_enum_of_int; mk_enum_of_string;
	       mk_enum_parse_fun; mk_enum_lwt_parse_fun;
	       mk_enum_dump_fun; mk_enum_print_fun ] in
    mk_str_items fns _loc enum_descr
      
  | "struct"; struct_name = ident; opts = option_list; "=";
    "{"; fields = LIST1 struct_field SEP ";"; "}" ->
    let options = check_options Struct opts in
    let record_descr = {
      rname = lid_of_ident struct_name;
      fields = fields;
      rdo_lwt = List.mem DoLwt options;
      rdo_exact = List.mem ExactParser options;
      rparse_params = mk_params options;
      rdump_params = [] (* TODO: For now? *)
    } in
    let fns = [mk_struct_type; mk_struct_parse_fun;
	       mk_struct_lwt_parse_fun; mk_struct_exact_parse;
	       mk_struct_dump_fun; mk_struct_print_fun ] in
    mk_str_items fns _loc record_descr

  | "union"; union_name = ident; opts = option_list;
    "("; u_b = union_unparsed_behaviour; ")";
    "="; choices = LIST1 union_choice ->
    let options = check_options Union opts in
    let union_descr = {
      uname = lid_of_ident union_name;
      uchoices = choices;
      unparsed_constr = fst u_b;
      unparsed_type = snd u_b;
      udo_lwt = List.mem DoLwt options;
      udo_exact = List.mem ExactParser options;
      uenrich = List.mem EnrichByDefault options;
      uexhaustive = List.mem ExhaustiveChoices options;
      uparse_params = mk_params options;
      udump_params = [] (* TODO: For now? *)
    } in
    let fns = [mk_union_enrich_bool; mk_union_type;
	       mk_union_parse_fun; mk_union_lwt_parse_fun;
	       mk_union_exact_parse;
	       mk_union_dump_fun; mk_union_print_fun ] in
    mk_str_items fns _loc union_descr

  | "alias"; alias_name = ident; opts = option_list;
    "="; type_aliased = ptype ->
    let options = check_options Alias opts in
    let alias_descr = {
      aname = lid_of_ident alias_name;
      atype = type_aliased;
      ado_lwt = List.mem DoLwt options;
      ado_exact = List.mem ExactParser options;
      aparse_params = mk_params options;
      adump_params = [] (* TODO: For now? *)
    } in
    let fns = [mk_alias_type; mk_alias_parse_fun;
               mk_alias_lwt_parse_fun; mk_alias_exact_parse_fun;
	       mk_alias_dump_fun; mk_alias_print_fun ] in
    mk_str_items fns _loc alias_descr

  | "asn1_alias"; asn1_alias_name = ident; opts = option_list ->
    let options = check_options ASN1Alias opts in
    let n = lid_of_ident asn1_alias_name in
    let asn1_alias_descr = {
      aaname = n;
      aaheader = ("C_Universal", "T_Sequence") ;
      aatype = Sequence (PT_Custom (None, n ^ "_content", [], []));
      aado_lwt = List.mem DoLwt options;
      aado_exact = List.mem ExactParser options;
      aaparse_params = mk_params options;
      aadump_params = [] (* TODO: For now? *)
    } in
    let fns = [mk_asn1_alias_type;
	       (* mk_asn1_alias_parse_fun; *)
               (* mk_asn1_alias_lwt_parse_fun; mk_asn1_alias_exact_parse_fun; *)
  	       (* mk_asn1_alias_dump_fun; mk_asn1_alias_print_fun *)
	      ] in
    mk_str_items fns _loc asn1_alias_descr
  ]];
END
;;
