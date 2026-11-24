// ==============================================================================
// Module:      HTTP Response Parser (response.cl)
// Project:     Cluster cURL (HTTP/HTTPS Transfer Client)
// Author:      zk-mohammad <ZaidKhan-alamgir@proton.me>
// License:     Cluster Community & Fair-Source License (CCFL v2.0)
// Description: HTTP status line, headers extraction, and chunked transfer decoding.
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
// Params:   res        - Structured HttpResponse
//           search_key - Header name to look up (e.g. "content-type", "location")
// Returns:  Header value string or empty string if not found
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
// Function: parse_hex_chunk_size
// Syntax:   fn parse_hex_chunk_size(s: string) -> int
// Purpose:  Parses hexadecimal chunk size prefix in HTTP chunked transfer streams.
// Params:   s - Chunk header line string
// Returns:  Integer size in bytes
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
// Params:   raw_body - Raw chunked HTTP response payload
// Returns:  Decoded unified body string
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
            pos = data_start + chunk_sz
            if pos < blen and byte_at(raw_body, pos) == 13:
                pos = pos + 1
            if pos < blen and byte_at(raw_body, pos) == 10:
                pos = pos + 1
        else:
            return out

    return out

// ------------------------------------------------------------------------------
// Function: parse_http_response
// Syntax:   fn parse_http_response(raw: string) -> HttpResponse
// Purpose:  Parses raw wire HTTP response bytes into status, headers, and body.
// Params:   raw - Complete HTTP response received from server
// Returns:  Structured HttpResponse model
// ------------------------------------------------------------------------------
fn parse_http_response(raw: string) -> HttpResponse:
    rlen := len(raw)
    hdr_end := -1
    sep_len := 4

    i := 0
    while i < rlen - 3:
        if byte_at(raw, i) == 13 and byte_at(raw, i + 1) == 10 and byte_at(raw, i + 2) == 13 and byte_at(raw, i + 3) == 10:
            hdr_end = i
            sep_len = 4
            i = rlen
        elif byte_at(raw, i) == 10 and byte_at(raw, i + 1) == 10:
            hdr_end = i
            sep_len = 2
            i = rlen
        i = i + 1

    headers_str := raw
    body_str := ""

    if hdr_end >= 0:
        headers_str = substring(raw, 0, hdr_end)
        body_start := hdr_end + sep_len
        if body_start < rlen:
            body_str = substring(raw, body_start, rlen - body_start)

    lines: vector[string] = []
    cur := ""
    i = 0
    while i < len(headers_str):
        b := byte_at(headers_str, i)
        if b == 10:
            lines.push(cur)
            cur = ""
        elif b != 13:
            cur = cur + chr(b)
        i = i + 1
    if len(cur) > 0:
        lines.push(cur)

    proto := "HTTP/1.1"
    status_code := 200
    status_text := "OK"
    headers: vector[HttpHeader] = []

    if len(lines) > 0:
        status_line := lines[0]
        s1 := -1
        s2 := -1
        j := 0
        while j < len(status_line):
            if byte_at(status_line, j) == 32:
                if s1 < 0:
                    s1 = j
                elif s2 < 0:
                    s2 = j
            j = j + 1

        if s1 > 0:
            proto = substring(status_line, 0, s1)
            if s2 > s1:
                code_str := substring(status_line, s1 + 1, s2 - s1 - 1)
                status_code = to_int(code_str)
                status_text = substring(status_line, s2 + 1, len(status_line) - s2 - 1)
            else:
                code_str := substring(status_line, s1 + 1, len(status_line) - s1 - 1)
                status_code = to_int(code_str)
                status_text = ""

        line_idx := 1
        while line_idx < len(lines):
            line := lines[line_idx]
            colon_pos := -1
            k := 0
            while k < len(line):
                if byte_at(line, k) == 58: // ':'
                    colon_pos = k
                    k = len(line)
                k = k + 1

            if colon_pos > 0:
                h_key := substring(line, 0, colon_pos)
                h_val := substring(line, colon_pos + 1, len(line) - colon_pos - 1)
                if len(h_val) > 0 and byte_at(h_val, 0) == 32:
                    h_val = substring(h_val, 1, len(h_val) - 1)
                headers.push(HttpHeader(h_key, h_val))
            line_idx = line_idx + 1

    res := HttpResponse(proto, status_code, status_text, headers, headers_str, body_str)

    te := get_response_header(res, "transfer-encoding")
    if te == "chunked":
        res.body = decode_chunked_body(body_str)

    return res
