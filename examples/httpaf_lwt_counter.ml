open Httpaf

module Session = struct
  module Backend = struct
    include Session.Lift.IO(Lwt)(Session_cookie)
    let create = Session_cookie.create
  end
  include Session_httpaf_lwt.Make(Backend)

  let set_default_period = Session_cookie.set_default_period
  let create = Session_cookie.create
end

let signer =
  Session_cookie.Signer.make
    "6qWiqeLJqZC/UrpcTLIcWOS/35SrCPzWskO/bDkIXBGH9fCXrDphsBj4afqigTKe"

let increment t session =
  let open Session in
  let value = string_of_int (1 + int_of_string session.value) in
  set t ~value session

let cookie = "__counter_session"

let request_handler reqd =
  let open Lwt.Syntax in
  Lwt.async (fun () ->
    let Httpaf.Request.{ headers; _ } = Reqd.request reqd in
    let backend = Session.create ~signer () in
    let* session = Session.of_header_or_create backend cookie "0" headers in
    print_endline session.value;
    let* () = increment backend session in
    let+ headers = Session.to_cookie_hdrs backend cookie session in
    let response_body = Printf.sprintf "%s" session.Session.value in
    Reqd.respond_with_string reqd (Response.create ~headers `OK) response_body)

let error_handler ?request:_ error start_response =
  let response_body = start_response Headers.empty in
  begin match error with
  | `Exn _ ->
    Body.write_string response_body ("An error occured\n");
  | #Status.standard as error ->
    Body.write_string response_body (Status.default_reason_phrase error)
  end;
  Body.close_writer response_body
    
let () =
  let open Lwt.Syntax in
  let listen_address = Unix.(ADDR_INET (inet_addr_loopback, 8080)) in
  let connection_handler addr fd =
    Httpaf_lwt_unix.Server.create_connection_handler
      ~request_handler:(fun _ -> request_handler)
      ~error_handler:(fun _ -> error_handler)
      addr
      fd
  in
  Lwt.async (fun () ->
    let* _ =
      Lwt_io.establish_server_with_client_socket listen_address connection_handler
    in
    Lwt.return_unit);
  let forever, _ = Lwt.wait () in
  Lwt_main.run forever
