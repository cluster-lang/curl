// ==============================================================================
// Module:      URL Parsing Engine (url.cl)
// Project:     Cluster cURL (HTTP/HTTPS Transfer Client)
// Author:      Zaid Alamgir (ZK Company)
// License:     MIT License
// Description: RFC 3986 Uniform Resource Identifier (URI) parser and decomposition.
// ==============================================================================

model ParsedUrl:
    raw: string
    scheme: string
    host: string
    port: int
    path: string
    query: string
    userinfo: string

// ------------------------------------------------------------------------------
// Function: parse_url
// Syntax:   fn parse_url(raw_url: string) -> ParsedUrl
// Purpose:  Decomposes a raw URL string into scheme, host, port, path, query, and credentials.
// Params:   raw_url - Absolute or relative URL string (e.g. "https://user:pass@example.com:8443/api?q=1")
// Returns:  Structured ParsedUrl model
// ------------------------------------------------------------------------------
fn parse_url(raw_url: string) -> ParsedUrl:
    scheme := "http"
    host := ""
    port := 80
    path := "/"
    query := ""
    userinfo := ""

    cur := raw_url
    if len(cur) >= 8 and substring(cur, 0, 8) == "https://":
        scheme = "https"
        port = 443
        cur = substring(cur, 8, len(cur) - 8)
    elif len(cur) >= 7 and substring(cur, 0, 7) == "http://":
        scheme = "http"
        port = 80
        cur = substring(cur, 7, len(cur) - 7)

    slash_pos := -1
    i := 0
    while i < len(cur):
        if byte_at(cur, i) == 47: // '/'
            slash_pos = i
            i = len(cur)
        i = i + 1

    host_part := cur
    if slash_pos >= 0:
        host_part = substring(cur, 0, slash_pos)
        path = substring(cur, slash_pos, len(cur) - slash_pos)

    q_pos := -1
    i = 0
    while i < len(path):
        if byte_at(path, i) == 63: // '?'
            q_pos = i
            i = len(path)
        i = i + 1

    if q_pos >= 0:
        query = substring(path, q_pos + 1, len(path) - q_pos - 1)
        path = substring(path, 0, q_pos)

    if len(path) == 0:
        path = "/"

    at_pos := -1
    i = 0
    while i < len(host_part):
        if byte_at(host_part, i) == 64: // '@'
            at_pos = i
            i = len(host_part)
        i = i + 1

    if at_pos >= 0:
        userinfo = substring(host_part, 0, at_pos)
        host_part = substring(host_part, at_pos + 1, len(host_part) - at_pos - 1)

    colon_pos := -1
    i = 0
    while i < len(host_part):
        if byte_at(host_part, i) == 58: // ':'
            colon_pos = i
            i = len(host_part)
        i = i + 1

    if colon_pos >= 0:
        host = substring(host_part, 0, colon_pos)
        port_str := substring(host_part, colon_pos + 1, len(host_part) - colon_pos - 1)
        port = to_int(port_str)
    else:
        host = host_part

    return ParsedUrl(raw_url, scheme, host, port, path, query, userinfo)
