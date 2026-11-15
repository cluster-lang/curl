// ============================================================================
//  cluster-curl: Core Transfer Engine (src/client.cl)
//  HTTP/HTTPS Connection Management, Streaming I/O & Redirect Following
// ============================================================================

model TransferOptions:
    verbose: int
    include_headers: int
    head_only: int
    follow_redirects: int
    max_redirects: int
    output_file: string
    silent: int
    write_out: string

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
        // Pure Cluster native TCP socket transfer
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
        // Print request lines
        req_lines := split_lines(wire)
        i := 0
        while i < len(req_lines):
            println(c_cyan + "> " + req_lines[i] + c_reset)
            i = i + 1

    return raw_response

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
