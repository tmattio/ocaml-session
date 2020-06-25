(** Lwt-based session manager for Httpaf. *)

open Session_httpaf

(** Create an Lwt-based session manager given a compatible backend. *)
module Make(B:Backend with type +'a io = 'a Lwt.t) : S
  with type +'a io = 'a Lwt.t
   and type backend = B.t
   and type key = string
   and type value = string
   and type period = int64
