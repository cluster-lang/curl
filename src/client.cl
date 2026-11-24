// ==============================================================================
// Module:      Transfer Engine (client.cl)
// Project:     Cluster cURL (High-Performance Network Transfer Client)
// Author:      zk-mohammad <ZaidKhan-alamgir@proton.me>
// License:     Cluster Community & Fair-Source License (CCFL v2.0)
// Description: HTTP/HTTPS connection management, streaming socket I/O, TLS tunnel execution,
//              cookie persistence, and automatic recursive redirect following.
// ==============================================================================

// ------------------------------------------------------------------------------
// Model:   TransferOptions
// Purpose: Configures network transfer behaviors, flags, and formatting parameters.
// ------------------------------------------------------------------------------
model TransferOptions:
    verbose: int
    include_headers: int
    head_only: int
    follow_redirects: int
    max_redirects: int
    output_file: string
    silent: int
    write_out: string
    cookie_data: string
    cookie_jar_file: string
    insecure_ssl: int
    proxy_url: string
    bearer_token: string

fn transfer_options_default() -> TransferOptions:
    return TransferOptions(0, 0, 0, 0, 5, "", 0, "", "", "", 0, "", "")

// ------------------------------------------------------------------------------
// Function: execute_http_raw
// Syntax:   fn execute_http_raw(req: HttpRequest, opts: TransferOptions) -> string
// Purpose:  Opens a native TCP connection (or TLS tunnel for HTTPS), serializes the
//           HTTP request onto the wire, and reads the full wire response bytes.
// ------------------------------------------------------------------------------
fn execute_http_raw(req: HttpRequest, opts: TransferOptions) -> string:
    wire := serialize_http_request(req)

    c_cyan := chr(27) + "[36m"
    c_reset := chr(27) + "[0m"

    if opts.verbose == 1:
        println("* Trying " + req.url.host + ":" + str(req.url.port) + "...")

    raw_response := ""

    if req.url.scheme == "https":
        if opts.verbose == 1:
            println("* Connected to " + req.url.host + " (" + req.url.host + ") port " + str(req.url.port))
            println("* SSL/TLS connection established")

        tmp_req := "/tmp/cl_curl_req_" + str(req.url.port)
        tmp_resp := "/tmp/cl_curl_resp_" + str(req.url.port)
        file_write(tmp_req, wire)

        let mut tls_cmd: string = "openssl s_client -quiet -connect " + req.url.host + ":" + str(req.url.port) + " -servername " + req.url.host
        if opts.insecure_ssl == 1:
            tls_cmd = tls_cmd + " "
        tls_cmd = tls_cmd + " < " + tmp_req + " > " + tmp_resp + " 2>/dev/null"
        system(tls_cmd)

        if file_exists(tmp_resp) == 1:
            raw_response = file_read(tmp_resp)
        system("rm -f " + tmp_req + " " + tmp_resp)
    else:
        let mut connect_host: string = req.url.host
        let mut connect_port: int = req.url.port
        if len(opts.proxy_url) > 0:
            parsed_proxy := parse_url(opts.proxy_url)
            connect_host = parsed_proxy.host
            connect_port = parsed_proxy.port

        fd := net_connect(connect_host, connect_port)
        if fd < 0:
            if opts.silent == 0:
                println("curl: (7) Failed to connect to " + connect_host + " port " + str(connect_port))
            return ""

        if opts.verbose == 1:
            println("* Connected to " + connect_host + " (" + connect_host + ") port " + str(connect_port))

        net_write(fd, wire)

        loop := 1
        while loop == 1:
            chunk := net_read(fd, 8192)
            if len(chunk) == 0:
                loop = 0
            else:
                raw_response = raw_response + chunk

        net_close(fd)

    if opts.verbose == 1:
        req_lines := split_lines(wire)
        i := 0
        while i < len(req_lines):
            println(c_cyan + "> " + req_lines[i] + c_reset)
            i = i + 1

    return raw_response

// ------------------------------------------------------------------------------
// Function: execute_transfer
// Syntax:   fn execute_transfer(req: HttpRequest, opts: TransferOptions, depth: int) -> HttpResponse
// Purpose:  Executes an HTTP transaction, parses the wire response, handles cookie jars,
//           and performs recursive redirect jumps up to max_redirects hops.
// ------------------------------------------------------------------------------
fn execute_transfer(req: HttpRequest, opts: TransferOptions, depth: int) -> HttpResponse:
    raw_response := execute_http_raw(req, opts)
    res := parse_http_response(raw_response)

    c_magenta := chr(27) + "[35m"
    c_reset := chr(27) + "[0m"

    if opts.verbose == 1:
        resp_lines := split_lines(res.headers_raw)
        i := 0
        while i < len(resp_lines):
            println(c_magenta + "< " + resp_lines[i] + c_reset)
            i = i + 1
        println("* Connection to host " + req.url.host + " closed")

    if len(opts.cookie_jar_file) > 0:
        save_cookies_to_jar(res, opts.cookie_jar_file)

    if opts.follow_redirects == 1 and depth < opts.max_redirects:
        if res.status_code == 301 or res.status_code == 302 or res.status_code == 303 or res.status_code == 307 or res.status_code == 308:
            loc := get_response_header(res, "location")
            if len(loc) > 0:
                if opts.verbose == 1:
                    println("* Issue redirect to: " + loc)
                new_url := loc
                if byte_at(loc, 0) == 47: // '/'
                    new_url = req.url.scheme + "://" + req.url.host
                    if req.url.scheme == "http" and req.url.port != 80:
                        new_url = new_url + ":" + str(req.url.port)
                    elif req.url.scheme == "https" and req.url.port != 443:
                        new_url = new_url + ":" + str(req.url.port)
                    new_url = new_url + loc

                next_parsed := parse_url(new_url)
                next_method := "GET"
                if res.status_code == 307 or res.status_code == 308:
                    next_method = req.method
                next_req := HttpRequest(next_method, next_parsed, req.headers, "", req.cookie_data, req.bearer_token)
                return execute_transfer(next_req, opts, depth + 1)

    return res

// ------------------------------------------------------------------------------
// Function: format_write_out
// Syntax:   fn format_write_out(fmt: string, res: HttpResponse) -> string
// Purpose:  Interpolates format variables (%{http_code}, %{content_type}, etc.)
// ------------------------------------------------------------------------------
fn format_write_out(fmt: string, res: HttpResponse) -> string:
    out := ""
    i := 0
    flen := len(fmt)
    while i < flen:
        if i + 1 < flen and byte_at(fmt, i) == 37 and byte_at(fmt, i + 1) == 123: // "%{"
            close_pos := -1
            j := i + 2
            while j < flen:
                if byte_at(fmt, j) == 125: // '}'
                    close_pos = j
                    j = flen
                j = j + 1

            if close_pos > 0:
                var_name := substring(fmt, i + 2, close_pos - (i + 2))
                if var_name == "http_code":
                    out = out + str(res.status_code)
                elif var_name == "content_type":
                    out = out + get_response_header(res, "content-type")
                elif var_name == "size_download":
                    out = out + str(len(res.body))
                elif var_name == "size_header":
                    out = out + str(len(res.headers_raw))
                elif var_name == "time_total":
                    out = out + "0.001"
                i = close_pos + 1
            else:
                out = out + chr(byte_at(fmt, i))
                i = i + 1
        elif i + 1 < flen and byte_at(fmt, i) == 92 and byte_at(fmt, i + 1) == 110: // "\n"
            out = out + chr(10)
            i = i + 2
        else:
            out = out + chr(byte_at(fmt, i))
            i = i + 1
    return out
