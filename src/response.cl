// ==============================================================================
// Module:      HTTP Response Parser (response.cl)
// Project:     Cluster cURL (HTTP/HTTPS Transfer Client)
// Author:      zk-mohammad <ZaidKhan-alamgir@proton.me>
// License:     Cluster Community & Fair-Source License (CCFL v2.0)
// Description: HTTP status line, headers extraction, chunked transfer decoding,
//              and cookie jar serialization.
// ==============================================================================

model HttpResponse:
    proto: string
    status_code: int
    status_text: string
    headers: vector[HttpHeader]
    headers_raw: string
    body: string

// ------------------------------------------------------------------------------
// Function: get_response_header
// Syntax:   fn get_response_header(res: HttpResponse, search_key: string) -> string
// Purpose:  Performs case-insensitive header lookup on the response headers.
// ------------------------------------------------------------------------------
fn get_response_header(res: HttpResponse, search_key: string) -> string:
    target := ""
    i := 0
    while i < len(search_key):
        b := byte_at(search_key, i)
        if b >= 65 and b <= 90:
            target = target + chr(b + 32)
        else:
            target = target + chr(b)
        i = i + 1

    i = 0
    hlen := len(res.headers)
    while i < hlen:
        h := res.headers[i]
        cur_k := ""
        j := 0
        while j < len(h.key):
            b := byte_at(h.key, j)
            if b >= 65 and b <= 90:
                cur_k = cur_k + chr(b + 32)
            else:
                cur_k = cur_k + chr(b)
            j = j + 1

        if cur_k == target:
            return h.val
        i = i + 1

    return ""

// ------------------------------------------------------------------------------
// Function: get_response_cookies
// Syntax:   fn get_response_cookies(res: HttpResponse) -> vector[string]
// Purpose:  Extracts all Set-Cookie values from response headers.
// ------------------------------------------------------------------------------
fn get_response_cookies(res: HttpResponse) -> vector[string]:
    let cookies: vector[string] = []
    let mut i: int = 0
    while i < len(res.headers):
        h := res.headers[i]
        let mut k_lower: string = ""
        let mut j: int = 0
        while j < len(h.key):
            b := byte_at(h.key, j)
            if b >= 65 and b <= 90:
                k_lower = k_lower + chr(b + 32)
            else:
                k_lower = k_lower + chr(b)
            j = j + 1
        if k_lower == "set-cookie":
            cookies.push(h.val)
        i = i + 1
    return cookies

// ------------------------------------------------------------------------------
// Function: save_cookies_to_jar
// Syntax:   fn save_cookies_to_jar(res: HttpResponse, filepath: string) -> int
// Purpose:  Persists Set-Cookie response entries into a Netscape cookie jar file.
// ------------------------------------------------------------------------------
fn save_cookies_to_jar(res: HttpResponse, filepath: string) -> int:
    cookies := get_response_cookies(res)
    if len(cookies) == 0:
        return 0
    let mut buf: string = "# Netscape HTTP Cookie File\n"
    let mut i: int = 0
    while i < len(cookies):
        buf = buf + cookies[i] + "\n"
        i = i + 1
    file_write(filepath, buf)
    return len(cookies)

// ------------------------------------------------------------------------------
// Function: parse_hex_chunk_size
// Syntax:   fn parse_hex_chunk_size(s: string) -> int
// Purpose:  Parses hexadecimal chunk size prefix in HTTP chunked transfer streams.
// ------------------------------------------------------------------------------
fn parse_hex_chunk_size(s: string) -> int:
    val := 0
    i := 0
    slen := len(s)
    while i < slen:
        b := byte_at(s, i)
        nibble := -1
        if b >= 48 and b <= 57:
            nibble = b - 48
        elif b >= 97 and b <= 102:
            nibble = b - 87
        elif b >= 65 and b <= 70:
            nibble = b - 55
        else:
            i = slen

        if nibble >= 0:
            val = (val << 4) | nibble
        i = i + 1
    return val

// ------------------------------------------------------------------------------
// Function: decode_chunked_body
// Syntax:   fn decode_chunked_body(raw_body: string) -> string
// Purpose:  Decodes RFC 7230 chunked transfer-encoded stream into unchunked body bytes.
// ------------------------------------------------------------------------------
fn decode_chunked_body(raw_body: string) -> string:
    out := ""
    blen := len(raw_body)
    pos := 0

    while pos < blen:
        crlf_pos := -1
        i := pos
        while i < blen - 1:
            if byte_at(raw_body, i) == 13 and byte_at(raw_body, i + 1) == 10:
                crlf_pos = i
                i = blen
            elif byte_at(raw_body, i) == 10:
                crlf_pos = i
                i = blen
            i = i + 1

        if crlf_pos < 0:
            return out

        size_line := substring(raw_body, pos, crlf_pos - pos)
        chunk_sz := parse_hex_chunk_size(size_line)

        if chunk_sz == 0:
            return out

        data_start := crlf_pos + 2
        if byte_at(raw_body, crlf_pos) == 10:
            data_start = crlf_pos + 1

        if data_start + chunk_sz <= blen:
            out = out + substring(raw_body, data_start, chunk_sz)
            pos = data_start + chunk_sz + 2
        else:
            return out

    return out

// ------------------------------------------------------------------------------
// Function: parse_http_response
// Syntax:   fn parse_http_response(raw: string) -> HttpResponse
// Purpose:  Parses raw HTTP/1.1 wire response into structured HttpResponse model.
// ------------------------------------------------------------------------------
fn parse_http_response(raw: string) -> HttpResponse:
    rlen := len(raw)
    if rlen < 12:
        let empty_h: vector[HttpHeader] = []
        return HttpResponse("HTTP/1.1", 0, "No response", empty_h, "", "")

    sep_pos := -1
    i := 0
    while i < rlen - 3:
        if byte_at(raw, i) == 13 and byte_at(raw, i + 1) == 10 and byte_at(raw, i + 2) == 13 and byte_at(raw, i + 3) == 10:
            sep_pos = i
            i = rlen
        i = i + 1

    header_block := ""
    body_block := ""

    if sep_pos >= 0:
        header_block = substring(raw, 0, sep_pos)
        if sep_pos + 4 < rlen:
            body_block = substring(raw, sep_pos + 4, rlen - (sep_pos + 4))
    else:
        header_block = raw

    lines := split_lines(header_block)
    if len(lines) == 0:
        let empty_h: vector[HttpHeader] = []
        return HttpResponse("HTTP/1.1", 0, "Empty", empty_h, "", "")

    status_line := lines[0]
    proto := "HTTP/1.1"
    code := 200
    text := "OK"

    s_sp1 := -1
    s_sp2 := -1
    j := 0
    while j < len(status_line):
        if byte_at(status_line, j) == 32:
            if s_sp1 < 0:
                s_sp1 = j
            elif s_sp2 < 0:
                s_sp2 = j
                j = len(status_line)
        j = j + 1

    if s_sp1 > 0:
        proto = substring(status_line, 0, s_sp1)
        if s_sp2 > s_sp1:
            code = to_int(substring(status_line, s_sp1 + 1, s_sp2 - s_sp1 - 1))
            if s_sp2 + 1 < len(status_line):
                text = substring(status_line, s_sp2 + 1, len(status_line) - s_sp2 - 1)
        else:
            code = to_int(substring(status_line, s_sp1 + 1, len(status_line) - s_sp1 - 1))

    headers: vector[HttpHeader] = []
    k := 1
    while k < len(lines):
        line := lines[k]
        c_pos := -1
        m := 0
        while m < len(line):
            if byte_at(line, m) == 58: // ':'
                c_pos = m
                m = len(line)
            m = m + 1

        if c_pos > 0:
            hk := substring(line, 0, c_pos)
            hv := ""
            val_start := c_pos + 1
            while val_start < len(line) and byte_at(line, val_start) == 32:
                val_start = val_start + 1
            if val_start < len(line):
                hv = substring(line, val_start, len(line) - val_start)
            headers.push(HttpHeader(hk, hv))
        k = k + 1

    res_temp := HttpResponse(proto, code, text, headers, header_block, body_block)
    te := get_response_header(res_temp, "transfer-encoding")
    if te == "chunked":
        body_block = decode_chunked_body(body_block)

    return HttpResponse(proto, code, text, headers, header_block, body_block)
