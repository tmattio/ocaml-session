module Signer = struct
  type t =
    { secret : string
    ; salt : string
    }

  let make ?(salt = "salt.signer") secret = { secret; salt }

  let constant_time_compare' a b init =
    let len = String.length a in
    let result = ref init in
    for i = 0 to len - 1 do
      result := !result lor Char.(compare a.[i] b.[i])
    done;
    !result = 0

  let constant_time_compare a b =
    if String.length a <> String.length b then
      constant_time_compare' b b 1
    else
      constant_time_compare' a b 0

  let derive_key t =
    Mirage_crypto.Hash.mac
      `SHA1
      ~key:(Cstruct.of_string t.secret)
      (Cstruct.of_string t.salt)

  let get_signature t value =
    value
    |> Cstruct.of_string
    |> Mirage_crypto.Hash.mac `SHA1 ~key:(derive_key t)
    |> Cstruct.to_string
    |> Base64.encode_exn

  let sign t data = String.concat "." [ data; get_signature t data ]

  let verified t value signature =
    if constant_time_compare signature (get_signature t value) then
      Some value
    else
      None

  let unsign t data =
    match String.split_on_char '.' data |> List.rev with
    | signature :: value ->
      let value = value |> List.rev |> String.concat "." in
      verified t value signature
    | _ ->
      None
end

type key = string

type value = string

type period = int64

type session =
  { value : value option
  ; expiry : period
  }

let sexp_of_session session = 
  let p = (session.expiry, session.value) in
  Sexplib.Conv.(
    sexp_of_pair sexp_of_int64 (sexp_of_option sexp_of_string) p
  )

let session_of_sexp sexp = 
  let (expiry, value) =
    Sexplib.Conv.(pair_of_sexp int64_of_sexp (option_of_sexp string_of_sexp)) sexp
  in
  { value; expiry }

type t =
  { signer : Signer.t
  ; mutable default_period : period
  }

let create ~signer () =
  { signer
      (* One week. If this changes, change module documentation. *)
  ; default_period = Int64.of_int (60 * 60 * 24 * 7)
  }

let now () = Int64.of_float (Unix.time ())

let default_period t = t.default_period

let set_default_period t period = t.default_period <- period

let get t key =
  match Signer.unsign t.signer key with
  | Some v ->
    (try
      let sexp = Sexplib.Sexp.of_string v in
      let result = session_of_sexp sexp in
      let period = Int64.(sub result.expiry (now ())) in
      if Int64.compare period 0L < 0 then
        Error Session.S.Not_found
      else
        match result.value with
        | None ->
          Error Session.S.Not_set
        | Some value ->
          Ok (value, period)
       with
      | _ ->
        Error Session.S.Not_valid)
  | None ->
    Error Session.S.Not_valid

let set ?expiry:_ _t _key _value = ()

let clear _t _key = ()

let generate ?expiry:_ ?value:_ _t = ""

let encode_key t _key (value, period) =
  let value = sexp_of_session
    { value = Some value
    ; expiry = Int64.(add period (now ())) 
    } |> Sexplib.Sexp.to_string
  in
  Signer.sign t.signer value
