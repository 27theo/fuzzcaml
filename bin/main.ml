(* Argument specification *)
let usage_str = "fuzzcaml -t <target_url> [-w <wordlist>] [-s <success_codes>]"
let target_url = ref ""
let wordlist_arg = ref ""
let success_codes_arg = ref ""

let arg_spec =
  [
    ("-t", Arg.Set_string target_url, "Set target url");
    ( "-w",
      Arg.Set_string wordlist_arg,
      "Set wordlist (defaults to wordlists/cve_paths.txt)" );
    ( "-s",
      Arg.Set_string success_codes_arg,
      "Set success codes (delimited by a comma e.g. -s 200,300,400)" );
  ]

(* Utils *)
let usage_and_exit () =
  Arg.usage arg_spec usage_str;
  exit 1

let ensure_trailing_slash url =
  if String.ends_with ~suffix:"/" url then url else String.cat url "/"

let string_is_empty s = String.equal (String.trim s) ""

(* Where the magic happens... *)
let fuzz_site urls success_codes =
  let check_page url =
    let%lwt result = Ezcurl_lwt.get ~url () in
    match result with
    | Ok response ->
        let msg =
          if List.mem response.code success_codes then "Success" else "Fail"
        in
        Lwt_io.printf "[%d] %s %s\n%!" response.code msg url
    | Error (code, err_str) ->
        let code = Curl.int_of_curlCode code in
        Lwt_io.printf "Curl error %d : %s\n  %s\n" code url err_str
  in

  (* Iterate and wait *)
  let stream = Lwt_stream.of_list urls in
  let max_concurrency = 50 in
  (*                    ^^ Change as required *)
  let worker () = Lwt_stream.iter_n ~max_concurrency check_page stream in
  let%lwt () = worker () in

  Lwt.return_unit

let () =
  Arg.parse arg_spec (fun _ -> usage_and_exit ()) usage_str;

  (* Target URL *)
  if string_is_empty !target_url then usage_and_exit ();
  let url = ensure_trailing_slash !target_url in

  (* Success codes *)
  let success_codes =
    if string_is_empty !success_codes_arg then [ 200 ]
    else
      try List.map int_of_string (String.split_on_char ',' !success_codes_arg)
      with _ ->
        prerr_endline
          "Error: Success codes should be a comma delimited list of integers";
        exit 1
  in

  (* Wordlist *)
  let wordlist =
    if string_is_empty !wordlist_arg then "wordlists/cve.txt" else !wordlist_arg
  in

  (* Read pages from wordlist *)
  let pages =
    try In_channel.with_open_text wordlist (fun ic -> In_channel.input_lines ic)
    with _ ->
      Printf.eprintf "Error: Failed to read lines from wordlist at '%s'\n"
        wordlist;
      exit 1
  in

  (* Concatenate urls ahead of fuzzing *)
  let urls = List.map (String.cat url) pages in

  (* Perform the fuzzing *)
  Lwt_main.run (fuzz_site urls success_codes)
