// ==============================================================================
// Module:      Transfer Engine (client.cl)
// Project:     Cluster cURL (High-Performance Network Transfer Client)
// Author:      zk-mohammad <ZaidKhan-alamgir@proton.me>
// License:     Cluster Community & Fair-Source License (CCFL v2.0)
// Description: HTTP/HTTPS connection management, streaming socket I/O, TLS tunnel execution,
//              and automatic recursive redirect following.
// ==============================================================================

// ------------------------------------------------------------------------------
// Model:   TransferOptions
// Purpose: Configures network transfer behaviors, flags, and formatting parameters.
// Fields:
//   verbose:          1 to log protocol interaction details (> req, < resp), 0 otherwise
//   include_headers:  1 to include response headers in standard output
//   head_only:        1 to issue HEAD and suppress body output
//   follow_redirects: 1 to automatically follow HTTP 3xx Location responses
//   max_redirects:    Maximum number of redirect hops allowed before aborting
//   output_file:      Destination filepath, or empty string for standard output
//   silent:           1 to suppress error and progress messages
//   write_out:        Custom format string for post-transfer metrics
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
        println("* Trying " + req.url.host + ":" + req.url.port + "...")

    raw_response := ""

    if req.url.scheme == "https":
        // HTTPS transfer over TLS tunnel
        if opts.verbose == 1:
            println("* Connected to " + req.url.host + " (" + req.url.host + ") port " + req.url.port)
            println("* SSL/TLS connection established")

        tmp_req := "/tmp/cl_curl_req_" + req.url.port
        tmp_resp := "/tmp/cl_curl_resp_" + req.url.port
        file_write(tmp_req, wire)

        tls_cmd := "openssl s_client -quiet -connect " + req.url.host + ":" + req.url.port + " -servername " + req.url.host + " < " + tmp_req + " > " + tmp_resp + " 2>/dev/null"
        system(tls_cmd)

        raw_response = file_read(tmp_resp)
        system("rm -f " + tmp_req + " " + tmp_resp)
    else:
        // Cluster native TCP socket transfer
        fd := net_connect(req.url.host, req.url.port)
        if fd < 0:
            if opts.silent == 0:
                println("curl: (7) Failed to connect to " + req.url.host + " port " + req.url.port)
            return ""

        if opts.verbose == 1:
            println("* Connected to " + req.url.host + " (" + req.url.host + ") port " + req.url.port)

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
// Purpose:  Executes an HTTP transaction, parses the wire response, prints verbose logs if
//           requested, and handles recursive redirect jumps up to max_redirects hops.
// ------------------------------------------------------------------------------
fn execute_transfer(req: HttpRequest, opts: TransferOptions, depth: int) -> HttpResponse:
    raw_response := execute_http_raw(req, opts)
    res := parse_http_response(raw_response)

    c_magenta := chr(27) + "[35m"
    c_reset := chr(27) + "[0m"

    if opts.verbose == 1:
        // Print response headers
        resp_lines := split_lines(res.headers_raw)
        i := 0
        while i < len(resp_lines):
            println(c_magenta + "< " + resp_lines[i] + c_reset)
            i = i + 1
        println("* Connection to host " + req.url.host + " closed")

    // Handle redirect following (-L)
    if opts.follow_redirects == 1 and depth < opts.max_redirects:
        if res.status_code == 301 or res.status_code == 302 or res.status_code == 303 or res.status_code == 307 or res.status_code == 308:
            loc := get_response_header(res, "location")
            if len(loc) > 0:
                if opts.verbose == 1:
                    println("* Issue redirect to: " + loc)
                new_url := loc
                // If relative redirect, build full URL
                if byte_at(loc, 0) == 47: // '/'
                    new_url = req.url.scheme + "://" + req.url.host
                    if req.url.scheme == "http" and req.url.port != 80:
                        new_url = new_url + ":" + req.url.port
                    elif req.url.scheme == "https" and req.url.port != 443:
                        new_url = new_url + ":" + req.url.port
                    new_url = new_url + loc

                next_parsed := parse_url(new_url)
                next_method := "GET"
                if res.status_code == 307 or res.status_code == 308:
                    next_method = req.method
                next_req := HttpRequest(next_method, next_parsed, req.headers, "")
                return execute_transfer(next_req, opts, depth + 1)

    return res
