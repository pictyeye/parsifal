open Types


(* Generic param helpers *)

let param_from_bool_ref name reference =
  (name,
   Some (fun () -> V_Bool !reference),
   Some (fun x -> reference := eval_as_bool (x)))

let param_from_int_ref name reference =
  (name,
   Some (fun () -> V_Int !reference),
   Some (fun x -> reference := eval_as_int (x)))


(* ParserInterface and Module functor *)

module type ParserInterface = sig
  type t
  val name : string
  val params : (string * getter option * setter option) list

  val parse : string -> char Stream.t -> t option
  val dump : t -> string
  val enrich : t -> (string, value) Hashtbl.t -> unit
  val update : (string, value) Hashtbl.t -> t
  val to_string : t -> string
end;;




module MakeParserModule = functor (Parser : ParserInterface) -> struct
  type t = Parser.t
  let name = Parser.name
  let param_getters = Hashtbl.create 10
  let param_setters = Hashtbl.create 10

  (* Object handling *)

  let count = ref 0
  let objects : (int, t) Hashtbl.t = Hashtbl.create 10
  let object_count () = V_Int (Hashtbl.length objects)

  let erase_obj = function
    | ObjectRef i -> Hashtbl.remove objects i

  let find_obj = function
    | ObjectRef i -> Hashtbl.find objects i

  let find_index = function
    | ObjectRef i ->
      if (Hashtbl.mem objects i)
      then i else raise Not_found


  let _register obj =
    let obj_ref = ObjectRef (!count) in
    Hashtbl.replace objects (!count) obj;
    Gc.finalise erase_obj obj_ref;
    incr count;
    obj_ref


  (* Operations on objects *)

  let register obj = V_Object (name, _register obj, Hashtbl.create 10)

  let enrich o d =
    if not (Hashtbl.mem d "@enriched") then begin
      Parser.enrich (find_obj o) d;
      Hashtbl.replace d "@enriched" V_Unit
    end

  let _update index d =
    if Hashtbl.mem d "@modified" then begin
      let new_obj = Parser.update d in
      Hashtbl.replace objects index new_obj;
      Hashtbl.remove d "@modified"
    end

  let update o d =
    let index = find_index o in
    _update index d


  let equals (ref1, d1) (ref2, d2) =
    let i1 = find_index ref1
    and i2 = find_index ref2 in
    _update i1 d1;
    _update i2 d2;
    Hashtbl.find objects i1 = Hashtbl.find objects i2


  (* Object constructions *)

  let stream_of_input = function
    | V_BinaryString s | V_String s -> ("(inline)", Stream.of_string s)
    | V_Stream (name, s) -> (name, s)
    | _ -> raise (ContentError "String or stream expected")

  let parse input =
    let stream_name, stream = stream_of_input input in
    match Parser.parse stream_name stream with
      | None -> V_Unit
      | Some obj -> register obj
    
  let make d =
    let dict = eval_as_dict d in
    let obj = Parser.update dict in
    Hashtbl.replace dict "@enriched" V_Unit;
    V_Object (name, _register obj, dict)


  (* Object export *)

  let apply f v =
    let (n, r, d) = eval_as_object v in
    if n <> name then raise (ContentError "Foreign object");
    let index = find_index r in
    _update index d;
    f (Hashtbl.find objects index)

  let dump =
    let dump_aux obj = V_BinaryString (Parser.dump obj)
    in apply dump_aux

  let to_string =
    let to_string_aux obj = V_String (Parser.to_string obj)
    in apply to_string_aux


  let init () =
    let no_getter () = raise Not_found in
    let no_setter _ = raise (ContentError ("Read-only field")) in
    let populate_param (param_name, getter, setter) =
      Hashtbl.replace param_getters param_name (Common.pop_option getter no_getter);
      Hashtbl.replace param_setters param_name (Common.pop_option setter no_setter);
    in
    let mk_fun f = Some (fun () -> V_Function (NativeFun f)) in
    List.iter populate_param Parser.params;
    populate_param ("name", Some (fun () -> V_String name), None);
    populate_param ("object_count", Some object_count, None);
    populate_param ("parse", mk_fun (one_value_fun parse), None);
    populate_param ("make", mk_fun (one_value_fun parse), None);
    populate_param ("dump", mk_fun (one_value_fun dump), None);
    populate_param ("to_string", mk_fun (one_value_fun to_string), None);
    ()

    (* TODO: Add a _dict or _params magic objects ? Remove all _ ? *)

end
