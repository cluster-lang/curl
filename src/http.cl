// ==============================================================================
// Module:      HTTP Protocol Engine (http.cl)
// Project:     Cluster cURL (HTTP/HTTPS Transfer Client)
// Author:      mohammadzaid/(cluster) <zkalamgir@proton.me>
// License:     Cluster Community // License:     MIT License Fair-Source License (CCFL-1.0)
// Description: RFC 7230 HTTP/1.1 wire protocol serializer & RFC 4648 Base64 auth.
// ==============================================================================

model HttpHeader:
    key: string
    val: string

model HttpRequest:
    method: string
    url: ParsedUrl
    headers: vector[HttpHeader]
    body: string

// ------------------------------------------------------------------------------
// Function: base64_encode
// Syntax:   fn base64_encode(s: string) -> string
// Purpose:  Encodes raw string data into standard RFC 4648 Base64 format with '=' padding.
// Params:   s - Input text or binary string
// Returns:  Base64 encoded string
// ------------------------------------------------------------------------------
fn base64_encode(s: string) -> string:
    chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out := ""
    slen := len(s)
    i := 0
    while i < slen:
        b0 := byte_at(s, i)
        b1 := 0
        b2 := 0
        has1 := 0
        has2 := 0
        if i + 1 < slen:
            b1 = byte_at(s, i + 1)
            has1 = 1
        if i + 2 < slen:
            b2 = byte_at(s, i + 2)
            has2 = 1

        triplet := (b0 << 16) | (b1 << 8) | b2

        c0 := (triplet >> 18) & 63
        c1 := (triplet >> 12) & 63
        c2 := (triplet >> 6) & 63
        c3 := triplet & 63

        out = out + substring(chars, c0, 1) + substring(chars, c1, 1)
        if has1 == 1:
            out = out + substring(chars, c2, 1)
        else:
            out = out + "="
        if has2 == 1:
            out = out + substring(chars, c3, 1)
        else:
            out = out + "="

        i = i + 3
    return out

// ------------------------------------------------------------------------------
// Function: serialize_http_request
// Syntax:   fn serialize_http_request(req: HttpRequest) -> string
// Purpose:  Serializes an HttpRequest into RFC 7230 compliant HTTP/1.1 wire bytes.
// Params:   req - Structured HttpRequest model
// Returns:  Raw HTTP request wire string with CRLF line terminators
// ------------------------------------------------------------------------------
fn serialize_http_request(req: HttpRequest) -> string:
    c_crlf := chr(13) + chr(10)

    target := req.url.path
    if len(req.url.query) > 0:
        target = target + "?" + req.url.query

    out := req.method + " " + target + " HTTP/1.1" + c_crlf

    has_host := 0
    has_ua := 0
    has_accept := 0
    has_conn := 0
    has_ct := 0
    has_cl := 0

    i := 0
    hlen := len(req.headers)
    while i < hlen:
        h := req.headers[i]
        k_lower := ""
        j := 0
        while j < len(h.key):
            b := byte_at(h.key, j)
            if b >= 65 and b <= 90:
                k_lower = k_lower + chr(b + 32)
            else:
                k_lower = k_lower + chr(b)
            j = j + 1

        if k_lower == "host": has_host = 1
        if k_lower == "user-agent": has_ua = 1
        if k_lower == "accept": has_accept = 1
        if k_lower == "connection": has_conn = 1
        if k_lower == "content-type": has_ct = 1
        if k_lower == "content-length": has_cl = 1

        out = out + h.key + ": " + h.val + c_crlf
        i = i + 1

    if has_host == 0:
        host_header := req.url.host
        if req.url.scheme == "http" and req.url.port != 80:
            host_header = host_header + ":" + req.url.port
        elif req.url.scheme == "https" and req.url.port != 443:
            host_header = host_header + ":" + req.url.port
        out = out + "Host: " + host_header + c_crlf

    if has_ua == 0:
        out = out + "User-Agent: cluster-curl/1.0.0" + c_crlf

    if has_accept == 0:
        out = out + "Accept: */*" + c_crlf

    if has_conn == 0:
        out = out + "Connection: close" + c_crlf

    if len(req.url.userinfo) > 0:
        auth_b64 := base64_encode(req.url.userinfo)
        out = out + "Authorization: Basic " + auth_b64 + c_crlf

    if len(req.body) > 0:
        if has_cl == 0:
            out = out + "Content-Length: " + len(req.body) + c_crlf
        if has_ct == 0:
            out = out + "Content-Type: application/x-www-form-urlencoded" + c_crlf

    out = out + c_crlf
    if len(req.body) > 0:
        out = out + req.body

    return out
